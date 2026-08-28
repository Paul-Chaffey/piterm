/* RNG - can the co-processor get real randomness?
 *
 * The one question in docs/ssh.md's spike list with no fallback attached. SSH
 * needs a CSPRNG for the ephemeral X25519 key and for nonces; BASIC's RND is
 * not one, and a predictable ephemeral key does not fail loudly - it produces
 * a working session that a listener can decrypt. So this is answered before
 * any protocol is written, not after.
 *
 * The Pi's SoC has a hardware RNG. On BCM2837 (the 3A+) the peripheral bus
 * address 0x7E104000 maps to physical 0x3F104000:
 *
 *   +0x00  CTRL       bit 0 enables it
 *   +0x04  STATUS     top 8 bits are the count of words available
 *   +0x08  DATA       read a word
 *   +0x0C  FF_THRESH
 *
 * WHETHER IT IS REACHABLE FROM HERE IS THE WHOLE QUESTION. PiTubeDirect runs
 * bare metal with the MMU on, and user code runs in user mode
 * (copro-armnative.c says so of its own handlers). If the peripheral window
 * is mapped with full access this simply works; if it is not, the first read
 * takes a data abort.
 *
 * A DATA ABORT IS THE GOOD FAILURE. The core installs a default data abort
 * handler, so an unmapped read should report rather than wedge. The staged
 * counter below plus the "about to" line rngspike.bas writes before calling
 * means even a wedge says which access did it.
 *
 * OS_EnterOS (SWI &16) would give SVC mode and almost certainly access. It is
 * NOT attempted here on purpose: getting back to user mode cleanly afterwards
 * is not obviously possible from C, and getting it wrong takes BASIC down
 * with it. If the user-mode read aborts, that is the next thing to try, and
 * it should be tried in a program that expects not to return.
 *
 * Loading, calling and the parameter block are exactly as src/spike1.c
 * describes them. Read that first.
 */

#define PARAM ((volatile unsigned int *) 0x04108000u)

#define P_STAGE   0     /* out: how far it got */
#define P_MAGIC   1     /* out: proof this code ran */
#define P_STATUS  2     /* out: STATUS as first read */
#define P_CTRL    3     /* out: CTRL as first read */
#define P_SPINS   4     /* out: how long the warm-up took */
#define P_COUNT   5     /* out: words actually collected */
#define P_WORDS   6     /* out: [6..13] eight words */

#define MAGIC 0x5B1CE002u

#define RNG_BASE   0x3F104000u
#define RNG_CTRL   ((volatile unsigned int *) (RNG_BASE + 0x00))
#define RNG_STATUS ((volatile unsigned int *) (RNG_BASE + 0x04))
#define RNG_DATA   ((volatile unsigned int *) (RNG_BASE + 0x08))

/* The datasheet's warm-up value. Writing it to STATUS tells the block how
 * many cycles to discard before the first word is trustworthy. */
#define WARMUP 0x40000u

/* Bounded, because a peripheral that is mapped but not clocked would answer
 * "no words ready" for ever and a co-processor spinning in a blob cannot be
 * escaped. At 1.2GHz this is a fraction of a second. */
#define MAX_SPINS 4000000u

static inline void os_writec(unsigned int c) {
    register unsigned int r0 __asm__("r0") = c;
    __asm__ volatile ("svc #0x00" : : "r"(r0) : "memory", "lr", "cc");
}

static inline void os_write0(const char *s) {
    register const char *r0 __asm__("r0") = s;
    __asm__ volatile ("svc #0x02" : "+r"(r0) : : "memory", "lr", "cc");
}

static inline void os_newline(void) {
    __asm__ volatile ("svc #0x03" : : : "memory", "r0", "lr", "cc");
}

unsigned int _start(unsigned int r0) {
    unsigned int i, spins, count;

    (void) r0;

    PARAM[P_STAGE] = 1;
    PARAM[P_MAGIC] = MAGIC;
    PARAM[P_COUNT] = 0;
    PARAM[P_SPINS] = 0;
    for (i = 0; i < 8; i++) {
        PARAM[P_WORDS + i] = 0;
    }

    os_write0("RNG");
    os_newline();

    /* Stage 2 is the risky one: the first touch of the peripheral window.
     * If the log ends here, the mapping is the answer. */
    PARAM[P_STAGE] = 2;
    PARAM[P_STATUS] = *RNG_STATUS;
    PARAM[P_CTRL]   = *RNG_CTRL;

    PARAM[P_STAGE] = 3;

    /* Only enable it if it is not already running - the firmware may have
     * done this, and rewriting the warm-up would throw away a block that is
     * already good. */
    if ((*RNG_CTRL & 1u) == 0u) {
        *RNG_STATUS = WARMUP;
        *RNG_CTRL = *RNG_CTRL | 1u;
    }

    PARAM[P_STAGE] = 4;

    spins = 0;
    while ((*RNG_STATUS >> 24) == 0u && spins < MAX_SPINS) {
        spins++;
    }
    PARAM[P_SPINS] = spins;

    PARAM[P_STAGE] = 5;

    /* WAIT PER WORD, do not bail on an empty FIFO.
     *
     * The first version broke out the moment STATUS said zero words, and on
     * hardware that stopped at FIVE every time (RESRAND, 2026-08-28): the
     * FIFO held four when we arrived, and reading drains it faster than the
     * block refills. Momentarily empty is not dead - it is the normal state
     * of a generator being read faster than it generates, and the only
     * correct response is to wait, exactly as the warm-up does.
     *
     * spins accumulates across all eight words, so what comes back is also a
     * throughput measurement: how long 32 bytes of seed actually costs. That
     * matters, because SSH wants 32 bytes for an ephemeral key and this is
     * the number that says whether to pull them directly or seed a software
     * CSPRNG from them once. */
    count = 0;
    for (i = 0; i < 8u; i++) {
        unsigned int wait = 0;
        while ((*RNG_STATUS >> 24) == 0u && wait < MAX_SPINS) {
            wait++;
        }
        spins += wait;
        if ((*RNG_STATUS >> 24) == 0u) {
            break;              /* genuinely not producing */
        }
        PARAM[P_WORDS + i] = *RNG_DATA;
        count++;
    }
    PARAM[P_SPINS] = spins;
    PARAM[P_COUNT] = count;

    PARAM[P_STAGE] = 6;
    os_writec('.');
    os_newline();

    return count;
}
