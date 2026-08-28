/* sshtest - the offline checks, run on every build.
 *
 * A hash that is subtly wrong does not announce itself. It produces a
 * handshake that fails with "bad signature", and the day after that is spent
 * looking at the signature code. So the primitives are checked against
 * published vectors before anything is built on them.
 *
 * Runs on Linux only - it is a test, not part of the client.
 */

#include <stdio.h>
#include <string.h>

#include "../src/ssh/sha256.h"

static int fails;

static void hex(const unsigned char *p, unsigned n, char *out) {
    static const char d[] = "0123456789abcdef";
    unsigned i;
    for (i = 0; i < n; i++) {
        out[i * 2] = d[p[i] >> 4];
        out[i * 2 + 1] = d[p[i] & 15];
    }
    out[n * 2] = 0;
}

static void check(const char *what, const unsigned char *got, unsigned n,
                  const char *want) {
    char s[160];
    hex(got, n, s);
    if (strcmp(s, want) == 0) {
        printf("  ok    %s\n", what);
    } else {
        printf("  FAIL  %s\n        got  %s\n        want %s\n", what, s, want);
        fails++;
    }
}

int main(void) {
    unsigned char out[32];
    struct sha256 s;
    unsigned i;

    printf("sha256, FIPS 180-4 vectors:\n");

    sha256((const unsigned char *) "abc", 3, out);
    check("\"abc\"", out, 32,
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");

    sha256((const unsigned char *) "", 0, out);
    check("empty", out, 32,
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

    sha256((const unsigned char *)
           "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56, out);
    check("56-byte", out, 32,
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");

    /* A million 'a'. This is the vector that catches a broken length field,
     * which is exactly the bug a short test would miss. */
    sha256_init(&s);
    for (i = 0; i < 1000000; i++) sha256_update(&s, (const unsigned char *) "a", 1);
    sha256_final(&s, out);
    check("one million 'a'", out, 32,
          "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");

    /* Streaming in awkward chunks must equal the one-shot. The exchange hash
     * is fed eight fields of arbitrary length, so this is the shape the real
     * use has. */
    {
        unsigned char a[32], b[32];
        const char *msg = "The quick brown fox jumps over the lazy dog";
        unsigned len = (unsigned) strlen(msg);
        unsigned chunk;
        sha256((const unsigned char *) msg, len, a);
        for (chunk = 1; chunk <= 17; chunk++) {
            unsigned off = 0;
            sha256_init(&s);
            while (off < len) {
                unsigned n = len - off < chunk ? len - off : chunk;
                sha256_update(&s, (const unsigned char *) msg + off, n);
                off += n;
            }
            sha256_final(&s, b);
            if (memcmp(a, b, 32) != 0) {
                printf("  FAIL  streaming in chunks of %u differs\n", chunk);
                fails++;
                break;
            }
        }
        if (chunk > 17) printf("  ok    streaming, chunks of 1..17\n");
    }

    printf("\n%s\n", fails ? "FAILED" : "all passed");
    return fails ? 1 : 0;
}
