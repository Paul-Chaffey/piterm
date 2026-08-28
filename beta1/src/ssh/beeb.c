/* beeb.c - the face the core shows to BBC BASIC on copro 15.
 *
 * The core does no I/O (src/ssh/ssh.h). On the Beeb the transport belongs to
 * BASIC, which already has a socket pump worth keeping: adaptive read sizing,
 * escalating backoff, the 64-byte cap, and the short-read handling that
 * specification.md 5.5a paid for in lost data. So this file is not a program.
 * It is a set of entry points BASIC calls, and nothing more.
 *
 * THE ABI, and it is deliberately the dullest one available:
 *
 *   BASIC sets A% to an opcode and CALLs the blob's base address. Arguments
 *   and results live in a parameter block at a fixed address. USR returns the
 *   result in r0. ARMSPIKE proved on hardware that A% arrives in r0 under
 *   both CALL and USR (results/RESSPIKE_0827b), which is what makes this
 *   possible without a parameter-block convention nobody has tested.
 *
 * FIXED ADDRESSES, because BASIC has to know them too and a negotiated
 * layout is one more thing to get out of step:
 *
 *   &4100000  the blob itself, linked here (as ARMSPIKE was)
 *   &4108000  the parameter block, 16 words
 *   &4110000  struct ssh, about 110KB - NOT in .bss, so the blob stays small
 *             and nothing depends on BSS being zeroed on arrival
 *
 * All three sit above BASIC's HIMEM of &4000000 and inside the 200MB of
 * application space the core grants. ARMSPIKE proved &4100000 is real
 * writable memory; the others are the same region.
 *
 * WHAT BASIC MUST STILL DO. Everything this file does not: open the socket,
 * connect it, read from it, write to it, close it. The core never learns
 * that a socket exists.
 */

#include "ssh.h"

/* A WHOLE MEGABYTE between the blob and everything else, and that spacing is
 * not caution - it is a bug already paid for. These addresses were &4108000
 * and &4110000, chosen when the only blob was ARMSPIKE's 131 bytes. The SSH
 * blob is 48KB, so &4108000 landed 32,768 bytes INSIDE it and BASIC wrote its
 * arguments straight into the blob's own code. The session got as far as
 * "connected" and then wedged, because the corrupted instructions had not
 * been reached yet.
 *
 * tools/sshbuild.sh now fails the build if the blob ever grows into PARAM, so
 * this cannot come back quietly. */
#define PARAM   ((volatile unsigned int *) 0x04200000u)
#define SESSION ((struct ssh *)            0x04210000u)

/* Opcodes. Numbered from 1 so that a zeroed parameter block - which is what
 * an uninitialised one looks like - is not a valid request. */
#define OP_INIT     1   /* [1]=compress s->c flag   -> 0 ok, -1 no entropy */
#define OP_AUTH     2   /* [1]=user ptr [2]=pubkey ptr [3]=seed ptr        */
#define OP_SIZE     3   /* [1]=cols [2]=rows                              */
#define OP_INPUT    4   /* [1]=ptr [2]=len          -> 0 ok, -1 failed     */
#define OP_OUTPUT   5   /* [1]=ptr [2]=max          -> bytes to send       */
#define OP_READ     6   /* [1]=ptr [2]=max          -> bytes for the glass */
#define OP_WRITE    7   /* [1]=ptr [2]=len          -> 0 ok, -1 blocked    */
#define OP_STATE    8   /*                          -> the state number    */
#define OP_ERRPTR   9   /*                          -> pointer to the text */
#define OP_VERSION 10   /*                          -> a build stamp       */
#define OP_PASSWD  11   /* [1]=ptr to password      -> 0 ok, -1 refused    */
#define OP_HOSTFP  12   /*                          -> pointer to SHA256:.. */
#define OP_ACCEPT  13   /*                          -> 0 ok, -1 not waiting */

#define BLOB_VERSION 0x5B1CE003u

static char fpbuf[64];   /* "SHA256:" and 43 characters, NUL-terminated */

/* The SoC hardware RNG, proved reachable from user mode on this core by
 * RNGSPIKE (results/RESRAND_0828b). The seed is taken HERE rather than
 * accepted from BASIC, because the only source BASIC could offer is RND, and
 * a predictable ephemeral key does not fail loudly - it produces a session
 * that works and that a listener can decrypt. Making it impossible to supply
 * a bad seed is worth more than an option to supply a good one. */
#define RNG_BASE   0x3F104000u
#define RNG_CTRL   ((volatile unsigned int *) (RNG_BASE + 0x00))
#define RNG_STATUS ((volatile unsigned int *) (RNG_BASE + 0x04))
#define RNG_DATA   ((volatile unsigned int *) (RNG_BASE + 0x08))
#define RNG_WARMUP 0x40000u
#define RNG_SPINS  4000000u

/* Waits per word. RNGSPIKE's first version bailed on a momentarily empty
 * FIFO and stopped at five words every time - the block refills more slowly
 * than a reader drains it, and empty is normal rather than broken. */
static int hw_seed(unsigned char out[32]) {
    unsigned i, w;
    if ((*RNG_CTRL & 1u) == 0u) {
        *RNG_STATUS = RNG_WARMUP;
        *RNG_CTRL = *RNG_CTRL | 1u;
    }
    for (i = 0; i < 8; i++) {
        unsigned spins = 0, v;
        while ((*RNG_STATUS >> 24) == 0u && spins < RNG_SPINS) spins++;
        if ((*RNG_STATUS >> 24) == 0u) return -1;
        v = *RNG_DATA;
        out[i * 4]     = (unsigned char) (v >> 24);
        out[i * 4 + 1] = (unsigned char) (v >> 16);
        out[i * 4 + 2] = (unsigned char) (v >> 8);
        out[i * 4 + 3] = (unsigned char) v;
    }
    w = 0;
    for (i = 0; i < 32; i++) w |= out[i];
    return w ? 0 : -1;          /* all zero is a dead block, not a seed */
}

/* The linker script provides these so the shim can clear its own BSS. The
 * blob is loaded by *LOAD, which writes only what is in the file, so
 * anything the compiler put in BSS arrives holding whatever was there
 * before - and on a machine where the previous run's data is still in RAM
 * that is a bug which reproduces only sometimes. */
extern unsigned char __bss_start__[];
extern unsigned char __bss_end__[];

static void clear_bss(void) {
    unsigned char *p = __bss_start__;
    while (p < __bss_end__) *p++ = 0;
}

__attribute__((section(".text.entry")))
unsigned int _start(unsigned int op) {
    volatile unsigned int *a = PARAM;
    struct ssh *s = SESSION;

    switch (op) {
    case OP_INIT: {
        unsigned char seed[32];
        unsigned i;
        clear_bss();
        if (hw_seed(seed) < 0) return (unsigned int) -1;
        ssh_init(s, seed, (int) a[1]);
        for (i = 0; i < 32; i++) seed[i] = 0;
        return 0;
    }

    case OP_AUTH: {
        /* BBC BASIC'S $ TERMINATES WITH CR, NOT NUL. $nm%="user" stores
         * 'p','a','u','l',&0D - so C's strlen runs past the name and takes
         * the CR and whatever follows until a zero byte happens to appear.
         * The server then sees a user it does not have and refuses the key,
         * which is what happened on 2026-08-28: the whole key exchange
         * succeeded and authentication failed for a name with a carriage
         * return on the end.
         *
         * Copied here with BOTH terminators honoured, so a caller using
         * BASIC's native string form cannot get this wrong. */
        char name[64];
        const char *src = (const char *) a[1];
        unsigned i = 0;
        while (i < sizeof name - 1 && src[i] != 0 && src[i] != 13) {
            name[i] = src[i];
            i++;
        }
        name[i] = 0;
        return (unsigned int) ssh_set_auth(s, name,
                                           (const unsigned char *) a[2],
                                           (const unsigned char *) a[3]);
    }

    case OP_SIZE:
        ssh_set_size(s, a[1], a[2]);
        return 0;

    case OP_INPUT:
        return (unsigned int) ssh_input(s, (const unsigned char *) a[1], a[2]);

    case OP_OUTPUT:
        return ssh_output(s, (unsigned char *) a[1], a[2]);

    case OP_READ:
        return ssh_read(s, (unsigned char *) a[1], a[2]);

    case OP_WRITE:
        return (unsigned int) ssh_write(s, (const unsigned char *) a[1], a[2]);

    case OP_STATE:
        return (unsigned int) s->state;

    case OP_ERRPTR:
        return (unsigned int) (unsigned long) s->err;

    /* Kept in a static rather than written into the parameter block: BASIC
     * reads it a byte at a time the way it reads the error text, and one
     * pattern for both is one thing to get wrong. */
    case OP_HOSTFP:
        if (ssh_hostkey_fp(s, fpbuf, sizeof fpbuf) < 0) fpbuf[0] = 0;
        return (unsigned int) (unsigned long) fpbuf;

    case OP_ACCEPT:
        return (unsigned int) ssh_accept_host(s);

    case OP_PASSWD: {
        /* Copied out and the caller's buffer left to it - BASIC has no way
         * to wipe a string, so the shortest life the password can have here
         * is: into the packet, then gone. ssh_set_password clears its own
         * copy as soon as it is sent. */
        char pw[128];
        const char *src = (const char *) a[1];
        unsigned i = 0;
        while (i < sizeof pw - 1 && src[i] != 0 && src[i] != 13) {
            pw[i] = src[i];
            i++;
        }
        pw[i] = 0;
        {
            int r = ssh_set_password(s, pw);
            for (i = 0; i < sizeof pw; i++) pw[i] = 0;
            return (unsigned int) r;
        }
    }

    case OP_VERSION:
        return BLOB_VERSION;

    default:
        return (unsigned int) -1;
    }
}
