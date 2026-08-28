/* sshtry - drive the sans-IO SSH core against a real server, on Linux.
 *
 *   tools/sshbuild.sh
 *   build/sshtry [host] [port] [user] [--compress]
 *
 * This is the half of the client that will NOT go on the Beeb. There, BASIC
 * owns the socket and calls the core; here, this file does. The core itself
 * is byte-identical between the two, which is the whole point of the sans-IO
 * split (src/ssh/ssh.h).
 *
 * Every protocol bug in this project will be found here rather than on
 * hardware, because here there is a debugger, a packet trace, sshd -ddd on
 * the other end, and a turnaround measured in seconds.
 *
 * It parses ~/.ssh/id_ed25519 itself. That parsing deliberately lives HERE
 * and not in the core: OpenSSH's private key container is a storage format,
 * not part of the protocol, and on the Beeb the key will arrive by some
 * quite different route.
 */

#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "../src/ssh/ssh.h"
#include "../vendor/monocypher/monocypher-ed25519.h"

static void die(const char *msg) {
    fprintf(stderr, "sshtry: %s\n", msg);
    exit(1);
}

static void seed_from_urandom(unsigned char out[32]) {
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f || fread(out, 1, 32, f) != 32) die("cannot read /dev/urandom");
    fclose(f);
}

/* ---- OpenSSH private key file ---- */

static int b64val(int c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static unsigned b64decode(const char *in, unsigned char *out, unsigned max) {
    unsigned n = 0, bits = 0;
    unsigned long acc = 0;
    for (; *in; in++) {
        int v = b64val((unsigned char) *in);
        if (v < 0) continue;                    /* newlines, '=' padding */
        acc = (acc << 6) | (unsigned long) v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (n < max) out[n++] = (unsigned char) (acc >> bits);
        }
    }
    return n;
}

static unsigned rd32(const unsigned char *p) {
    return ((unsigned) p[0] << 24) | ((unsigned) p[1] << 16) |
           ((unsigned) p[2] << 8) | (unsigned) p[3];
}

/* Fills pk and sk from an UNENCRYPTED ed25519 key. An encrypted one is
 * refused rather than half-handled: the kdf would have to be implemented,
 * and a wrong answer there looks exactly like a wrong password. */
static void load_key(const char *path, unsigned char pk[32], unsigned char sk[32]) {
    char text[8192], *b, *e;
    unsigned char raw[4096];
    unsigned n, off;
    size_t len;
    FILE *f = fopen(path, "rb");

    if (!f) die("cannot open the private key");
    len = fread(text, 1, sizeof text - 1, f);
    fclose(f);
    text[len] = 0;

    b = strstr(text, "-----BEGIN OPENSSH PRIVATE KEY-----");
    e = strstr(text, "-----END OPENSSH PRIVATE KEY-----");
    if (!b || !e) die("not an OpenSSH-format private key");
    b += strlen("-----BEGIN OPENSSH PRIVATE KEY-----");
    *e = 0;

    n = b64decode(b, raw, sizeof raw);
    if (n < 16 || memcmp(raw, "openssh-key-v1", 15) != 0) die("bad key magic");

    off = 15;
    if (rd32(raw + off) != 4 || memcmp(raw + off + 4, "none", 4) != 0)
        die("the key is passphrase-protected - decrypt it or use another");
    off += 4 + rd32(raw + off);         /* ciphername */
    off += 4 + rd32(raw + off);         /* kdfname */
    off += 4 + rd32(raw + off);         /* kdfoptions */
    off += 4;                           /* number of keys */
    off += 4 + rd32(raw + off);         /* public key blob */
    off += 4;                           /* private section length */
    off += 8;                           /* the two check integers */
    off += 4 + rd32(raw + off);         /* key type */

    if (off + 36 > n || rd32(raw + off) != 32) die("public key is not 32 bytes");
    memcpy(pk, raw + off + 4, 32);
    off += 36;
    if (off + 68 > n || rd32(raw + off) != 64) die("private key is not 64 bytes");
    memcpy(sk, raw + off + 4, 32);      /* the seed; the rest is the pub half */
}

/* ---- what the server offered, straight out of its KEXINIT ---- */

static void dump_server_lists(const struct ssh *s) {
    static const char *label[10] = {
        "kex", "host key", "cipher c->s", "cipher s->c", "mac c->s",
        "mac s->c", "compress c->s", "compress s->c", "lang c->s", "lang s->c"
    };
    unsigned off = 17;
    int i;
    for (i = 0; i < 10; i++) {
        unsigned len;
        if (off + 4 > s->i_s_len) return;
        len = rd32(s->i_s + off);
        off += 4;
        if (off + len > s->i_s_len) return;
        if (i < 2 || i == 6 || i == 7)
            printf("  %-14s %.*s\n", label[i], (int) len, (const char *) s->i_s + off);
        off += len;
    }
}

static void print_fingerprint(const unsigned char fp[32]) {
    static const char B[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    unsigned j, v;
    printf("SHA256:");
    for (j = 0; j + 3 <= 30; j += 3) {
        v = ((unsigned) fp[j] << 16) | ((unsigned) fp[j + 1] << 8) | fp[j + 2];
        putchar(B[(v >> 18) & 63]); putchar(B[(v >> 12) & 63]);
        putchar(B[(v >> 6) & 63]);  putchar(B[v & 63]);
    }
    v = ((unsigned) fp[30] << 16) | ((unsigned) fp[31] << 8);
    putchar(B[(v >> 18) & 63]); putchar(B[(v >> 12) & 63]); putchar(B[(v >> 6) & 63]);
    putchar('\n');
}

int main(int argc, char **argv) {
    const char *host = "127.0.0.1";
    const char *user = getenv("USER") ? getenv("USER") : "root";
    const char *work = NULL;
    char cmdbuf[512];
    const char *cmd = "echo SSHOK-$((6*7))\n";
    unsigned long wire = 0, app = 0;
    char keypath[512];
    int port = 22, compress = 0, i;
    struct sockaddr_in sa;
    struct timeval tv;
    struct ssh s;
    unsigned char seed[32], pk[32], sk[32], buf[4096];
    int fd, rounds = 0, sent = 0, done = 0, nokey = 0;
    const char *pass = NULL;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--compress") == 0) compress = 1;
        else if (strcmp(argv[i], "--run") == 0 && i + 1 < argc) work = argv[++i];
        else if (strcmp(argv[i], "--pass") == 0 && i + 1 < argc) pass = argv[++i];
        else if (strcmp(argv[i], "--nokey") == 0) nokey = 1;
        else if (i == 1) host = argv[i];
        else if (i == 2) port = atoi(argv[i]);
        else if (i == 3) user = argv[i];
    }
    snprintf(keypath, sizeof keypath, "%s/.ssh/id_ed25519",
             getenv("HOME") ? getenv("HOME") : ".");

    if (work) {
        /* The marker still terminates the run, so a workload of any size
         * ends deterministically rather than on a timeout. */
        snprintf(cmdbuf, sizeof cmdbuf, "%s; echo SSHOK-$((6*7))\n", work);
        cmd = cmdbuf;
    }

    seed_from_urandom(seed);
    load_key(keypath, pk, sk);
    ssh_init(&s, seed, compress);
    if (!nokey) {
        if (ssh_set_auth(&s, user, pk, sk) < 0) die(s.err);
    } else {
        /* Deliberately offer a key the server will not know, so the password
         * path is what gets exercised rather than assumed. */
        unsigned char bogus_pk[32], bogus_sk[32], seed2[32], expanded[64];
        seed_from_urandom(seed2);
        memcpy(bogus_sk, seed2, 32);
        crypto_ed25519_key_pair(expanded, bogus_pk, seed2);
        ssh_set_auth(&s, user, bogus_pk, bogus_sk);
    }

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) die("socket");
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short) port);
    if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) die("host must be a dotted quad");
    if (connect(fd, (struct sockaddr *) &sa, sizeof sa) < 0) die("connect");

    /* So a server that stops talking ends the test instead of hanging it. */
    tv.tv_sec = 5; tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    printf("connected to %s:%d as %s%s\n\n--- session ---\n", host, port, user,
           compress ? ", asking for zlib server->client" : "");

    /* The pump, deliberately the same shape PTERM's will be: drain whatever
     * the core wants sent, then feed it whatever arrived. */
    while (s.state != SSH_ST_ERROR && !done && rounds++ < 400) {
        unsigned n;
        ssize_t got;

        while ((n = ssh_output(&s, buf, sizeof buf)) > 0) {
            if (write(fd, buf, n) != (ssize_t) n) die("write");
        }

        while ((n = ssh_read(&s, buf, sizeof buf - 1)) > 0) {
            buf[n] = 0;
            app += n;
            if (!work) fputs((const char *) buf, stdout);
            if (strstr((const char *) buf, "SSHOK-42")) done = 1;
        }

        if (s.state == SSH_ST_NEEDHOST) {
            char fp[64];
            if (ssh_hostkey_fp(&s, fp, sizeof fp) < 0) { printf("no fingerprint\n"); break; }
            printf("host key %s\n", fp);
            /* This harness accepts whatever it is told, which is exactly what
             * PTERM must NOT do - the point of printing it here is that the
             * value can be compared against ssh-keygen -l by eye. */
            if (ssh_accept_host(&s) < 0) { printf("accept refused\n"); break; }
            continue;
        }

        if (s.state == SSH_ST_NEEDPASS) {
            if (!pass) { printf("\nserver wants a password and none given\n"); break; }
            printf("key refused; sending password\n");
            if (ssh_set_password(&s, pass) < 0) break;
            continue;
        }

        if (s.state == SSH_ST_OPEN && !sent) {
            ssh_write(&s, (const unsigned char *) cmd, (unsigned) strlen(cmd));
            sent = 1;
            continue;
        }
        if (done) break;

        got = read(fd, buf, sizeof buf);
        if (got < 0) { printf("\n(read timed out while %s)\n", ssh_strstate(&s)); break; }
        if (got == 0) { printf("\nserver closed while %s\n", ssh_strstate(&s)); break; }
        wire += (unsigned long) got;
        if (ssh_input(&s, buf, (unsigned) got) < 0) break;
    }

    printf("--- end ---\n\nclient  %s\nserver  %s\n\n", s.v_c, s.v_s);
    if (s.state == SSH_ST_ERROR) {
        printf("FAILED: %s\n", s.err);
        close(fd);
        return 1;
    }

    printf("server offered:\n");
    dump_server_lists(&s);
    printf("\nnegotiated:\n");
    printf("  kex            %s\n", s.algs.kex);
    printf("  host key       %s\n", s.algs.hostkey);
    printf("  cipher         %s\n", s.algs.enc_sc);
    printf("  compress c->s  %s\n", s.algs.comp_cs);
    printf("  compress s->c  %s\n", s.algs.comp_sc);
    printf("  strict kex     %s\n", s.strict_kex ? "yes" : "NO");
    printf("  host key fp    ");
    print_fingerprint(s.hostkey_fp);

    /* THE NUMBER THIS EXISTS TO PRODUCE. app is what the terminal has to
     * render; wire is what the Sprow module has to carry at 4,268 bytes a
     * second. Their ratio is the whole argument of docs/ssh.md, measured
     * rather than simulated. */
    printf("\nbytes on the wire   %lu\n", wire);
    printf("bytes to the screen %lu\n", app);
    if (app)
        printf("ratio               %.3fx  (%.1f seconds of Tube time at 4268 B/s)\n",
               (double) wire / (double) app, (double) wire / 4268.0);

    printf("\n%s\n", done ? "PASS - a shell ran a command and the answer came back"
                          : "INCOMPLETE - never saw the command's output");
    close(fd);
    return done ? 0 : 1;
}
