/* sha256.h - the one primitive Monocypher does not carry.
 *
 * Monocypher gives X25519, Ed25519, ChaCha20, Poly1305 and SHA-512, which is
 * the whole suite except this: curve25519-sha256 names its hash in the
 * algorithm, and RFC 4253's key derivation uses the same one. About 150
 * lines, so vendoring a second library for it would cost more than writing
 * it.
 *
 * Freestanding, no libc, no allocation. Streaming, because the exchange hash
 * is computed over eight fields that are never contiguous in memory.
 */

#ifndef SHA256_H
#define SHA256_H

struct sha256 {
    unsigned int  h[8];
    unsigned char buf[64];
    unsigned      len;          /* bytes currently in buf */
    unsigned      total;        /* message length in bytes - see note in .c */
};

void sha256_init(struct sha256 *s);
void sha256_update(struct sha256 *s, const unsigned char *p, unsigned n);
void sha256_final(struct sha256 *s, unsigned char out[32]);

/* One-shot, for the many places that hash a single buffer. */
void sha256(const unsigned char *p, unsigned n, unsigned char out[32]);

#endif
