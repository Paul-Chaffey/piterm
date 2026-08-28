/* ssh.h - the sans-IO SSH client core.
 *
 * NO I/O HAPPENS IN HERE. Not a socket, not a file, not a clock, not an
 * allocation. Bytes arrive through ssh_input, bytes to send leave through
 * ssh_output, terminal data crosses through ssh_read and ssh_write. Whoever
 * calls it owns the transport.
 *
 * That is the whole design, and it buys three things this project needs:
 *
 *   BASIC KEEPS THE SOCKET. PTERM's pump took several sessions to tune - the
 *   adaptive sizing, the escalating backoff, the 64-byte cap, the short-read
 *   handling that specification.md 5.5a paid for. None of it gets rewritten
 *   in C. FNnet_recv hands ciphertext in and takes plaintext out.
 *
 *   IT RUNS ON LINUX. The same source compiles natively and can be driven
 *   against a real sshd on the deskbox box, which is where every protocol
 *   bug will be found. Finding them on the Beeb, over a Tube, through
 *   LANManFS, with a monitor for output, would be an act of self-harm.
 *
 *   IT IS TESTABLE. Feed it a recorded server transcript and the whole
 *   handshake replays with no network at all - the same trick as PTERM's
 *   replay$ and the pyte comparison.
 *
 * FREESTANDING. No libc: there is none on the parasite. The few string
 * operations needed are written out in ssh.c.
 *
 * Buffers are fixed and live in the struct. 200MB of application space means
 * the sizes below are not a constraint; they are a bound, so that a hostile
 * or broken peer cannot make us grow.
 */

#ifndef SSH_H
#define SSH_H

#define SSH_IN_MAX    16384     /* one inbound packet, plus slack */
#define SSH_OUT_MAX    8192     /* queued bytes waiting for the socket */
#define SSH_APP_MAX   16384     /* decrypted terminal data waiting for BASIC */
#define SSH_DICT_MAX  32768     /* inflate's window - fixed by the format */
#define SSH_ERR_MAX      96
#define SSH_NAME_MAX     64
#define SSH_VER_MAX     256

/* Where the handshake has got to. Anything below SSH_ST_ERROR is progress. */
enum ssh_state {
    SSH_ST_VERSION = 0,   /* waiting for the server's identification line */
    SSH_ST_KEXINIT,       /* ours sent, waiting for theirs */
    SSH_ST_KEXREPLY,      /* ECDH_INIT sent, waiting for the reply */
    SSH_ST_NEWKEYS,       /* keys derived, waiting for the server's NEWKEYS */
    SSH_ST_SERVICE,       /* encrypted, ssh-userauth requested */
    SSH_ST_AUTH,          /* publickey request sent */
    SSH_ST_CHANNEL,       /* authenticated, session channel requested */
    SSH_ST_PTY,           /* channel open, pty requested */
    SSH_ST_SHELL,         /* pty granted, shell requested */
    SSH_ST_OPEN,          /* a shell is running - this is the working state */
    SSH_ST_ERROR,
    /* AFTER error on purpose, so the numbers before it do not move: BASIC
     * hardcodes 9 for OPEN and 10 for ERROR, and renumbering the enum would
     * silently change what test/sshbeeb.bas and PTERM are testing. */
    SSH_ST_CLOSED,        /* the far end ended the session - NOT a fault */
    /* The key was refused and a password may work. The caller is expected to
     * ask for one and call ssh_set_password; nothing happens until it does,
     * because only the caller has a keyboard. */
    SSH_ST_NEEDPASS,
    /* The host key is verified as SELF-consistent - the server holds the
     * private half of what it showed - but nothing has said it is the right
     * host. The core stops here until ssh_accept_host, for the same reason
     * it stops at NEEDPASS: only the caller can answer. */
    SSH_ST_NEEDHOST
};

/* The negotiated set, filled in when SSH_ST_NEGOTIATED is reached. */
struct ssh_algs {
    char kex[SSH_NAME_MAX];
    char hostkey[SSH_NAME_MAX];
    char enc_cs[SSH_NAME_MAX];
    char enc_sc[SSH_NAME_MAX];
    char mac_cs[SSH_NAME_MAX];
    char mac_sc[SSH_NAME_MAX];
    char comp_cs[SSH_NAME_MAX];
    char comp_sc[SSH_NAME_MAX];
};

struct ssh {
    int state;
    char err[SSH_ERR_MAX];

    /* Both identification strings, kept WITHOUT their CRLF because the
     * exchange hash is computed over exactly that form (RFC 4253 8). They
     * are needed long after the version exchange is over. */
    char v_c[SSH_VER_MAX];
    char v_s[SSH_VER_MAX];

    unsigned char in[SSH_IN_MAX];
    unsigned in_len;

    unsigned char out[SSH_OUT_MAX];
    unsigned out_len;

    unsigned char app[SSH_APP_MAX];
    unsigned app_len;

    /* The peer's KEXINIT payload, kept whole: it goes into the exchange
     * hash verbatim and cannot be reconstructed from the parsed names. */
    unsigned char i_s[4096];
    unsigned i_s_len;
    unsigned char i_c[1024];
    unsigned i_c_len;

    struct ssh_algs algs;

    /* Set when the server advertised kex-strict-s-v00@openssh.com and we
     * advertised the client half. See ssh.c for what it obliges us to do. */
    int strict_kex;

    unsigned char cookie[16];

    /* The CSPRNG. Seeded once from the caller's 32 bytes - the SoC RNG on
     * the Beeb, /dev/urandom here - and rekeyed on every draw, so a later
     * compromise of the state does not reveal the ephemeral key that has
     * already been used. */
    unsigned char rng_key[32];
    unsigned long long rng_ctr;

    /* Key exchange. The ephemeral secret exists for one handshake and is
     * wiped as soon as the shared secret is derived from it. */
    unsigned char eph_sk[32];
    unsigned char eph_pk[32];
    /* The shared secret K as an mpint. FORTY, NOT THIRTY-SIX: an mpint whose
     * top bit is set gains a leading zero byte, so the worst case is 4 length
     * + 1 zero + 32 = 37. At 36 the last byte landed in kmp_len, which the
     * very next statement overwrote - the exchange hash then used a byte of
     * its own length field instead of K, and the handshake failed for exactly
     * the half of all secrets with the high bit set. */
    unsigned char kmp[40];
    unsigned      kmp_len;
    unsigned char session_id[32]; /* H from the FIRST exchange, then fixed */

    /* The server's host key, kept whole: the exchange hash covers it
     * verbatim, and the caller needs it to decide about trust. */
    unsigned char hostkey[512];
    unsigned      hostkey_len;
    unsigned char hostkey_fp[32]; /* SHA-256 of the blob - ssh-keygen's form */
    unsigned char host_ok;        /* the caller has approved hostkey_fp */

    /* Transport keys. Two directions, switched on independently: ours when
     * we send NEWKEYS, theirs when we receive it. */
    int           enc_out, enc_in;
    unsigned char key_cs[64], key_sc[64];
    unsigned      seq_out, seq_in;

    unsigned char pkt[SSH_IN_MAX];   /* decrypted payload */

    /* Decompression, server-to-client only. The dictionary is inflate's
     * 32KB window and is written circularly; infl is the same bytes made
     * contiguous, because a packet has to be parsed as one run. */
    int           comp_in;
    unsigned char dict[SSH_DICT_MAX];
    unsigned      dict_ofs;
    unsigned char infl[SSH_IN_MAX];
    void         *inflator;          /* a tinfl_decompressor, opaque here */

    /* Authentication. The key is supplied by the caller, already unwrapped:
     * parsing OpenSSH's private key container is the caller's business, not
     * the protocol's, and on the Beeb it will not be done in C at all. */
    char          user[64];
    char          pass[128];
    int           have_pass;      /* a password has been supplied */
    int           tried_pass;     /* ...and already sent, so a second
                                     failure is a real refusal */
    unsigned char auth_pk[32];
    unsigned char auth_sk[64];   /* Monocypher's expanded form: seed || public */
    int           have_key;

    /* The session channel. One channel, because this is a terminal and not
     * a general SSH implementation - no forwarding, no subsystems. */
    unsigned      chan_local, chan_remote;
    unsigned      win_out;      /* what the server will still accept */
    unsigned      win_in;       /* what we have told the server we will take */
    unsigned      win_used;     /* consumed since the last adjust */
    unsigned      max_out;      /* the server's largest acceptable packet */

    unsigned      rows, cols;
    int           want_compress_sc;
};

/* Terminal geometry, sent in pty-req and again on every resize. */
void ssh_set_size(struct ssh *s, unsigned cols, unsigned rows);

/* The user name and an Ed25519 key: pk is the 32-byte public key, seed the
 * 32-byte private seed. Returns -1 if the two do not belong together, which
 * catches a mis-parsed key file at the point of loading rather than as an
 * unexplained authentication failure. Must be set before userauth. */
int ssh_set_auth(struct ssh *s, const char *user,
                 const unsigned char pk[32], const unsigned char seed[32]);

/* Supplies a password after SSH_ST_NEEDPASS and sends the request. The
 * password is wiped from this struct as soon as it has been sent. */
int ssh_set_password(struct ssh *s, const char *pw);

/* Approves the host key and lets the handshake continue. Returns -1 if the
 * session is not waiting at SSH_ST_NEEDHOST. Refusing is not a call: the
 * caller simply closes the socket, which is the only honest response to a
 * key it does not recognise. */
int ssh_accept_host(struct ssh *s);

/* The fingerprint in the form ssh-keygen -l prints, "SHA256:" and 43
 * characters of unpadded base64, NUL-terminated. Returns the length, or -1
 * if there is no host key yet or the buffer is too small. Comparing what a
 * person reads off two screens is the whole mechanism, so the format has to
 * be the one the other screen uses. */
int ssh_hostkey_fp(struct ssh *s, char *out, unsigned max);

/* Terminal data towards the server. Returns 0, or -1 if the channel window
 * or the output queue is full - the caller should drain and retry. */
int ssh_write(struct ssh *s, const unsigned char *p, unsigned n);

/* seed must be 32 bytes of real randomness. On the Beeb that is the SoC RNG
 * (src/rng.c); on Linux it is /dev/urandom. The core never invents any. */
/* compress_sc asks for zlib@openssh.com on the SERVER-TO-CLIENT direction
 * only. That asymmetry is deliberate and is explained in ssh.c. */
void ssh_init(struct ssh *s, const unsigned char seed[32], int compress_sc);

/* Bytes off the wire. Returns 0, or -1 with s->err set. */
int ssh_input(struct ssh *s, const unsigned char *p, unsigned n);

/* Bytes for the wire. Returns how many were copied out. */
unsigned ssh_output(struct ssh *s, unsigned char *buf, unsigned max);

/* Decrypted terminal data. Returns how many were copied out. */
unsigned ssh_read(struct ssh *s, unsigned char *buf, unsigned max);

const char *ssh_strstate(const struct ssh *s);

#endif
