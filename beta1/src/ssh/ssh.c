/* ssh.c - version exchange, binary packet framing, algorithm negotiation.
 *
 * This is the transport layer's first half, and it stops at the point where
 * crypto would begin. Everything here is unencrypted by definition: the
 * version exchange and the two KEXINIT packets happen before any key exists.
 *
 * WHAT IT DOES NOT DO YET: the key exchange itself, host key verification,
 * NEWKEYS, authentication, channels. Those land next. The value of stopping
 * here is that it can be pointed at a real sshd today and will either
 * negotiate a cipher suite or say exactly why not.
 *
 * See ssh.h for why there is no I/O in this file.
 */

#include "ssh.h"
#include "sha256.h"
#include "../../vendor/monocypher/monocypher.h"
#include "../../vendor/monocypher/monocypher-ed25519.h"
#include "../../vendor/miniz/miniz_tinfl.h"

/* ---- freestanding odds and ends. No libc on the parasite. ---- */

static void xmemcpy(void *d, const void *s, unsigned n) {
    unsigned char *a = (unsigned char *) d;
    const unsigned char *b = (const unsigned char *) s;
    while (n--) *a++ = *b++;
}

static unsigned xstrlen(const char *s) {
    unsigned n = 0;
    while (s[n]) n++;
    return n;
}

static int xmemcmp(const void *x, const void *y, unsigned n) {
    const unsigned char *a = x, *b = y;
    while (n--) { if (*a != *b) return (int) *a - (int) *b; a++; b++; }
    return 0;
}

/* Copies at most max-1 bytes and always terminates. */
static void xcopy(char *d, unsigned max, const char *s, unsigned n) {
    unsigned i;
    if (max == 0) return;
    if (n > max - 1) n = max - 1;
    for (i = 0; i < n; i++) d[i] = s[i];
    d[n] = 0;
}

static void fail(struct ssh *s, const char *msg) {
    if (s->state == SSH_ST_ERROR) return;   /* keep the FIRST error */
    s->state = SSH_ST_ERROR;
    xcopy(s->err, SSH_ERR_MAX, msg, xstrlen(msg));
}

/* ---- output queue ---- */

static int emit(struct ssh *s, const unsigned char *p, unsigned n) {
    if (s->out_len + n > SSH_OUT_MAX) {
        fail(s, "output queue full - drain ssh_output more often");
        return -1;
    }
    xmemcpy(s->out + s->out_len, p, n);
    s->out_len += n;
    return 0;
}

unsigned ssh_output(struct ssh *s, unsigned char *buf, unsigned max) {
    unsigned n = s->out_len < max ? s->out_len : max;
    unsigned i;
    xmemcpy(buf, s->out, n);
    for (i = n; i < s->out_len; i++) s->out[i - n] = s->out[i];
    s->out_len -= n;
    return n;
}

unsigned ssh_read(struct ssh *s, unsigned char *buf, unsigned max) {
    unsigned n = s->app_len < max ? s->app_len : max;
    unsigned i;
    xmemcpy(buf, s->app, n);
    for (i = n; i < s->app_len; i++) s->app[i - n] = s->app[i];
    s->app_len -= n;
    return n;
}

/* ---- what we offer ----
 *
 * ONE ALGORITHM PER SLOT WHERE IT MATTERS, deliberately. A client that
 * offers a suite it has not implemented negotiates its way into a state it
 * cannot honour, and the failure surfaces three messages later as a MAC
 * error. If the server will not do these, the right outcome is a clear
 * refusal here.
 *
 * curve25519-sha256 is offered under both its RFC 8731 name and the
 * @libssh.org name it shipped under first; they are the same algorithm.
 *
 * The MAC lists are placeholders. chacha20-poly1305@openssh.com is an AEAD
 * and carries its own tag, so the negotiated MAC is not used at all - but
 * the field may not be empty, and OpenSSH expects a plausible name.
 *
 * COMPRESSION IS OFFERED WITH zlib FIRST, because on this machine it is the
 * point of the exercise: docs/ssh.md measures 4-9x. Measured against stock
 * OpenSSH 10.2p1 on 2026-08-28: it offers "none,zlib@openssh.com" with no
 * configuration at all, and since negotiation takes the CLIENT's first
 * preference, putting zlib first wins it.
 *
 * STRICT KEX IS NOT OPTIONAL FOR US. kex-strict-c-v00@openssh.com is the
 * client half of OpenSSH's Terrapin mitigation (CVE-2023-48795), and
 * Terrapin is a prefix-truncation attack against precisely the cipher this
 * client chose - chacha20-poly1305@openssh.com is the worst affected. The
 * marker goes LAST in the list because it is a signal, not an algorithm: it
 * cannot be selected, since the server advertises the -s- spelling and
 * negotiation matches on the exact name.
 *
 * Advertising it takes on two obligations, both of which land with NEWKEYS
 * and neither of which exists yet:
 *   - reset both sequence numbers to zero at every NEWKEYS
 *   - treat IGNORE, DEBUG and UNIMPLEMENTED during the initial KEX as fatal
 * strict_kex records that we owe them.
 */
static const char *OFFER_KEX     = "curve25519-sha256,curve25519-sha256@libssh.org,"
                                   "kex-strict-c-v00@openssh.com";
static const char *STRICT_S      = "kex-strict-s-v00@openssh.com";
static const char *OFFER_HOSTKEY = "ssh-ed25519";
static const char *OFFER_ENC     = "chacha20-poly1305@openssh.com";
static const char *OFFER_MAC     = "hmac-sha2-256";
/* COMPRESSION IS ASKED FOR IN ONE DIRECTION ONLY, and that is a design
 * decision rather than a shortcut. The two directions negotiate separately,
 * and on this machine every byte that matters travels server-to-client: the
 * 4-9x in docs/ssh.md is all downstream. Asking for it downstream only means
 * the client needs INFLATE and never DEFLATE - roughly half the code, and the
 * half that is simpler. Keystrokes go uncompressed and lose nothing: they are
 * a few bytes a second against a 3.28ms send call.
 *
 * OFFER_COMP_SC still lists none second, so a server that refuses zlib gets a
 * working session rather than a failed negotiation. */
static const char *OFFER_COMP_CS = "none";
static const char *OFFER_COMP_SC = "zlib@openssh.com,none";
static const char *OFFER_COMP_NO = "none";
static const char *OFFER_LANG    = "";

#define SSH_MSG_DISCONNECT       1
#define SSH_MSG_IGNORE           2
#define SSH_MSG_UNIMPLEMENTED    3
#define SSH_MSG_DEBUG            4
#define SSH_MSG_SERVICE_REQUEST  5
#define SSH_MSG_SERVICE_ACCEPT   6
#define SSH_MSG_EXT_INFO         7
#define SSH_MSG_KEXINIT         20
#define SSH_MSG_NEWKEYS         21
#define SSH_MSG_KEX_ECDH_INIT   30
#define SSH_MSG_KEX_ECDH_REPLY  31
#define SSH_MSG_USERAUTH_REQUEST      50
#define SSH_MSG_USERAUTH_FAILURE      51
#define SSH_MSG_USERAUTH_SUCCESS      52
#define SSH_MSG_USERAUTH_BANNER       53
#define SSH_MSG_USERAUTH_PK_OK        60
#define SSH_MSG_GLOBAL_REQUEST        80
#define SSH_MSG_CHANNEL_OPEN          90
#define SSH_MSG_CHANNEL_OPEN_CONFIRM  91
#define SSH_MSG_CHANNEL_OPEN_FAILURE  92
#define SSH_MSG_CHANNEL_WINDOW_ADJUST 93
#define SSH_MSG_CHANNEL_DATA          94
#define SSH_MSG_CHANNEL_EXTENDED_DATA 95
#define SSH_MSG_CHANNEL_EOF           96
#define SSH_MSG_CHANNEL_CLOSE         97
#define SSH_MSG_CHANNEL_REQUEST       98
#define SSH_MSG_CHANNEL_SUCCESS       99
#define SSH_MSG_CHANNEL_FAILURE      100

/* Forward declarations. The file reads best in protocol order - framing,
 * then negotiation, then the exchange - but negotiation hands straight on to
 * the exchange, so these few have to be announced early. */
static int send_ecdh_init(struct ssh *s);
static int send_userauth_pass(struct ssh *s);
static int inflate_payload(struct ssh *s, const unsigned char *in, unsigned in_len,
                           const unsigned char **out, unsigned *out_len);

/* ---- big-endian helpers ---- */

static void put32(unsigned char *p, unsigned v) {
    p[0] = (unsigned char) (v >> 24);
    p[1] = (unsigned char) (v >> 16);
    p[2] = (unsigned char) (v >> 8);
    p[3] = (unsigned char) v;
}

static unsigned get32(const unsigned char *p) {
    return ((unsigned) p[0] << 24) | ((unsigned) p[1] << 16) |
           ((unsigned) p[2] << 8) | (unsigned) p[3];
}

/* ---- version exchange ---- */

#define CLIENT_ID "SSH-2.0-PiTerm_0.1"

/* RFC 4253 4.2: the server may send any number of other lines before its
 * identification string, and a client must ignore them. Real servers do -
 * that is where a banner goes. Only a line beginning "SSH-" counts. */
static int take_version(struct ssh *s) {
    unsigned i, start = 0;
    for (i = 0; i + 1 < s->in_len; i++) {
        if (s->in[i] != '\r' || s->in[i + 1] != '\n') continue;
        {
            unsigned len = i - start;
            if (len >= 4 && xmemcmp(s->in + start, "SSH-", 4) == 0) {
                if (len < 8 || xmemcmp(s->in + start, "SSH-2.0-", 8) != 0) {
                    fail(s, "server is not SSH-2.0");
                    return -1;
                }
                xcopy(s->v_s, SSH_VER_MAX, (const char *) s->in + start, len);
                /* consume through the CRLF */
                {
                    unsigned used = i + 2, j;
                    for (j = used; j < s->in_len; j++) s->in[j - used] = s->in[j];
                    s->in_len -= used;
                }
                return 1;
            }
        }
        start = i + 2;
        i++;                    /* step over the LF as well */
    }
    if (s->in_len >= SSH_VER_MAX * 4) {
        fail(s, "no SSH- line in a great deal of preamble");
        return -1;
    }
    return 0;                   /* not yet - wait for more */
}

/* ---- packet framing, unencrypted ----
 *
 * uint32 packet_length, byte padding_length, payload, padding. No MAC while
 * no keys exist. The cipher is "none", whose block size is taken as 8, so
 * 4 + 1 + payload + padding must be a multiple of 8 with at least 4 bytes of
 * padding (RFC 4253 6).
 *
 * The padding is NOT random here and does not need to be: nothing is
 * encrypted yet, so it hides nothing. Once keys exist it must come from the
 * CSPRNG, and that is a note for the commit that adds it, not a TODO left to
 * rot in the source.
 */
static int send_packet(struct ssh *s, const unsigned char *payload, unsigned n) {
    unsigned char hdr[5];
    unsigned char pad[16];
    unsigned padlen = 8 - ((5 + n) % 8);
    unsigned i;
    if (padlen < 4) padlen += 8;
    put32(hdr, 1 + n + padlen);
    hdr[4] = (unsigned char) padlen;
    for (i = 0; i < padlen; i++) pad[i] = 0;
    if (emit(s, hdr, 5) < 0) return -1;
    if (emit(s, payload, n) < 0) return -1;
    return emit(s, pad, padlen);
}

/* Returns the whole packet's length on the wire and sets payload and plen to
 * point at its payload; 0 if more bytes are needed; -1 on a protocol error.
 * The caller passes the return value to drop_packet once it has finished
 * with the payload. */
static int take_packet(struct ssh *s, const unsigned char **payload, unsigned *plen) {
    unsigned len, padlen, total;
    if (s->in_len < 5) return 0;
    len = get32(s->in);
    if (len < 8 || len > SSH_IN_MAX - 4) {
        fail(s, "absurd packet length");
        return -1;
    }
    total = 4 + len;
    if (s->in_len < total) return 0;
    padlen = s->in[4];
    if (padlen + 1 > len) {
        fail(s, "padding longer than the packet");
        return -1;
    }
    /* The payload points INTO s->in and stays valid only until drop_packet
     * shifts the buffer, which is why the caller is handed the total to drop
     * rather than this doing it. */
    *payload = s->in + 5;
    *plen = len - padlen - 1;
    return (int) total;
}

static void drop_packet(struct ssh *s, unsigned total) {
    unsigned i;
    for (i = total; i < s->in_len; i++) s->in[i - total] = s->in[i];
    s->in_len -= total;
}

/* ---- name-list handling ---- */

/* A name-list is a uint32 length followed by that many bytes of
 * comma-separated names. Returns 0 and advances *off past it. */
static int list_at(const unsigned char *p, unsigned n, unsigned *off,
                   const char **out, unsigned *len) {
    unsigned l;
    if (*off + 4 > n) return -1;
    l = get32(p + *off);
    if (*off + 4 + l > n) return -1;
    *out = (const char *) p + *off + 4;
    *len = l;
    *off += 4 + l;
    return 0;
}

/* True if `name` (of length nlen) appears in the comma-separated list. */
static int in_list(const char *list, unsigned llen, const char *name, unsigned nlen) {
    unsigned i = 0, start = 0;
    for (i = 0; i <= llen; i++) {
        if (i == llen || list[i] == ',') {
            if (i - start == nlen && xmemcmp(list + start, name, nlen) == 0) return 1;
            start = i + 1;
        }
    }
    return 0;
}

/* RFC 4253 7.1: the choice is the CLIENT's first preference that the server
 * also supports. Not the server's first - getting this backwards silently
 * picks a different algorithm than the server computed the exchange hash
 * with, and the failure appears much later as a bad signature.
 */
static int negotiate(struct ssh *s, const char *ours,
                     const char *theirs, unsigned tlen,
                     char *out, const char *what) {
    unsigned olen = xstrlen(ours);
    unsigned i, start = 0;
    for (i = 0; i <= olen; i++) {
        if (i == olen || ours[i] == ',') {
            if (i > start && in_list(theirs, tlen, ours + start, i - start)) {
                xcopy(out, SSH_NAME_MAX, ours + start, i - start);
                return 0;
            }
            start = i + 1;
        }
    }
    fail(s, what);
    return -1;
}

static int build_kexinit(struct ssh *s) {
    unsigned char *p = s->i_c;
    unsigned off = 0, i;
    const char *lists[10];
    lists[0] = OFFER_KEX;     lists[1] = OFFER_HOSTKEY;
    lists[2] = OFFER_ENC;     lists[3] = OFFER_ENC;
    lists[4] = OFFER_MAC;     lists[5] = OFFER_MAC;
    lists[6] = OFFER_COMP_CS;
    lists[7] = s->want_compress_sc ? OFFER_COMP_SC : OFFER_COMP_NO;
    lists[8] = OFFER_LANG;    lists[9] = OFFER_LANG;

    p[off++] = SSH_MSG_KEXINIT;
    xmemcpy(p + off, s->cookie, 16);
    off += 16;
    for (i = 0; i < 10; i++) {
        unsigned l = xstrlen(lists[i]);
        if (off + 4 + l + 5 > sizeof s->i_c) { fail(s, "KEXINIT too large"); return -1; }
        put32(p + off, l);
        off += 4;
        xmemcpy(p + off, lists[i], l);
        off += l;
    }
    p[off++] = 0;               /* first_kex_packet_follows */
    put32(p + off, 0);          /* reserved */
    off += 4;
    s->i_c_len = off;
    return send_packet(s, s->i_c, off);
}

static int handle_kexinit(struct ssh *s, const unsigned char *p, unsigned n) {
    unsigned off = 17;          /* type byte + 16-byte cookie */
    const char *l[10];
    unsigned ll[10];
    unsigned i;

    if (n > sizeof s->i_s) { fail(s, "server KEXINIT larger than we keep"); return -1; }
    xmemcpy(s->i_s, p, n);
    s->i_s_len = n;

    for (i = 0; i < 10; i++) {
        if (list_at(p, n, &off, &l[i], &ll[i]) < 0) {
            fail(s, "malformed KEXINIT name-list");
            return -1;
        }
    }
    s->strict_kex = in_list(l[0], ll[0], STRICT_S, xstrlen(STRICT_S));

    if (negotiate(s, OFFER_KEX,     l[0], ll[0], s->algs.kex,     "no common key exchange") < 0) return -1;
    if (negotiate(s, OFFER_HOSTKEY, l[1], ll[1], s->algs.hostkey, "no common host key type") < 0) return -1;
    if (negotiate(s, OFFER_ENC,     l[2], ll[2], s->algs.enc_cs,  "no common cipher (to server)") < 0) return -1;
    if (negotiate(s, OFFER_ENC,     l[3], ll[3], s->algs.enc_sc,  "no common cipher (from server)") < 0) return -1;
    if (negotiate(s, OFFER_MAC,     l[4], ll[4], s->algs.mac_cs,  "no common MAC (to server)") < 0) return -1;
    if (negotiate(s, OFFER_MAC,     l[5], ll[5], s->algs.mac_sc,  "no common MAC (from server)") < 0) return -1;
    if (negotiate(s, OFFER_COMP_CS, l[6], ll[6], s->algs.comp_cs, "no common compression (to server)") < 0) return -1;
    if (negotiate(s, s->want_compress_sc ? OFFER_COMP_SC : OFFER_COMP_NO,
                  l[7], ll[7], s->algs.comp_sc, "no common compression (from server)") < 0) return -1;

    /* Straight on into the exchange: RFC 4253 lets the client send
     * KEX_ECDH_INIT as soon as it knows the algorithm, and waiting buys
     * nothing. */
    if (send_ecdh_init(s) < 0) return -1;
    s->state = SSH_ST_KEXREPLY;
    return 0;
}


/* ---- CSPRNG ----
 *
 * Seeded once from the caller's 32 bytes and REKEYED ON EVERY DRAW: each
 * block yields a fresh key as well as output, so the state that exists after
 * a draw cannot reproduce what that draw returned. Cheap, and it means a
 * later compromise does not expose an ephemeral key already used.
 */
static const unsigned char ZERO64[64] = { 0 };

static void rng(struct ssh *s, unsigned char *out, unsigned n) {
    unsigned char block[64];
    unsigned char nonce[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
    while (n) {
        unsigned take = n < 32 ? n : 32;
        unsigned i;
        crypto_chacha20_djb(block, ZERO64, 64, s->rng_key, nonce, s->rng_ctr++);
        for (i = 0; i < 32; i++) s->rng_key[i] = block[i];
        for (i = 0; i < take; i++) out[i] = block[32 + i];
        out += take;
        n -= take;
    }
    crypto_wipe(block, sizeof block);
}

/* ---- SSH wire encodings ---- */

static unsigned put_string(unsigned char *out, const unsigned char *p, unsigned n) {
    put32(out, n);
    xmemcpy(out + 4, p, n);
    return 4 + n;
}

/* An mpint is a signed big-endian integer: leading zero bytes are stripped,
 * and a zero byte is prepended when the top bit would otherwise make it
 * negative. Getting this wrong gives an exchange hash that differs from the
 * server's, and the only symptom is "bad signature" - which sends you
 * looking at the signature. */
static unsigned put_mpint(unsigned char *out, const unsigned char *v, unsigned n) {
    unsigned i = 0;
    while (i < n && v[i] == 0) i++;
    if (i == n) { put32(out, 0); return 4; }
    if (v[i] & 0x80) {
        put32(out, n - i + 1);
        out[4] = 0;
        xmemcpy(out + 5, v + i, n - i);
        return 5 + n - i;
    }
    put32(out, n - i);
    xmemcpy(out + 4, v + i, n - i);
    return 4 + n - i;
}

/* Reads a length-prefixed string, bounds-checked against the packet. */
static int get_string(const unsigned char *p, unsigned n, unsigned *off,
                      const unsigned char **out, unsigned *len) {
    unsigned l;
    if (*off + 4 > n) return -1;
    l = get32(p + *off);
    if (l > n || *off + 4 + l > n) return -1;
    *out = p + *off + 4;
    *len = l;
    *off += 4 + l;
    return 0;
}

static void hash_string(struct sha256 *h, const unsigned char *p, unsigned n) {
    unsigned char l[4];
    put32(l, n);
    sha256_update(h, l, 4);
    sha256_update(h, p, n);
}

/* ---- chacha20-poly1305@openssh.com ----
 *
 * Two independent ChaCha20 instances, per OpenSSH's PROTOCOL.chacha20poly1305:
 * the first 256 bits of the 512-bit key are K_2, which encrypts the payload,
 * and the second 256 bits are K_1, which encrypts the 4-byte length on its
 * own. The nonce for both is the packet sequence number, big-endian.
 *
 * Counter 0 of K_2 produces the Poly1305 key; the payload starts at counter
 * 1. The tag covers the ENCRYPTED length and the ENCRYPTED payload, which is
 * why the length must be kept in its ciphertext form until after the check.
 */
static void seq_nonce(unsigned char nonce[8], unsigned seq) {
    nonce[0] = 0; nonce[1] = 0; nonce[2] = 0; nonce[3] = 0;
    nonce[4] = (unsigned char) (seq >> 24);
    nonce[5] = (unsigned char) (seq >> 16);
    nonce[6] = (unsigned char) (seq >> 8);
    nonce[7] = (unsigned char) seq;
}

static void cc_length(const unsigned char key[64], unsigned seq,
                      unsigned char out[4], const unsigned char in[4]) {
    unsigned char nonce[8];
    seq_nonce(nonce, seq);
    crypto_chacha20_djb(out, in, 4, key + 32, nonce, 0);
}

static void cc_polykey(const unsigned char key[64], unsigned seq,
                       unsigned char out[32]) {
    unsigned char nonce[8], block[64];
    unsigned i;
    seq_nonce(nonce, seq);
    crypto_chacha20_djb(block, ZERO64, 64, key, nonce, 0);
    for (i = 0; i < 32; i++) out[i] = block[i];
    crypto_wipe(block, sizeof block);
}

static void cc_payload(const unsigned char key[64], unsigned seq,
                       unsigned char *out, const unsigned char *in, unsigned n) {
    unsigned char nonce[8];
    seq_nonce(nonce, seq);
    crypto_chacha20_djb(out, in, n, key, nonce, 1);
}

/* ---- packet output ---- */

/* Padding rule differs once an AEAD is in play: the 4-byte length is
 * encrypted separately and is NOT part of the padded block, so the multiple
 * of 8 is taken over (padding_length + payload + padding) alone. OpenSSH's
 * packet.c does the same by subtracting its aadlen. Using the plaintext rule
 * here produces packets the server rejects as badly padded. */
static int send_packet_enc(struct ssh *s, const unsigned char *payload, unsigned n) {
    unsigned char plain[SSH_OUT_MAX], ct[SSH_OUT_MAX], lenc[4], hdr[4], tag[16];
    unsigned char polykey[32];
    unsigned padlen = 8 - ((1 + n) % 8);
    unsigned len, i;

    if (padlen < 4) padlen += 8;
    len = 1 + n + padlen;
    if (len + 20 > SSH_OUT_MAX) { fail(s, "packet too large to send"); return -1; }

    plain[0] = (unsigned char) padlen;
    xmemcpy(plain + 1, payload, n);
    rng(s, plain + 1 + n, padlen);

    put32(hdr, len);
    cc_length(s->key_cs, s->seq_out, lenc, hdr);
    cc_polykey(s->key_cs, s->seq_out, polykey);
    cc_payload(s->key_cs, s->seq_out, ct, plain, len);

    /* The tag is over the ciphertext, length field included. */
    {
        unsigned char both[SSH_OUT_MAX];
        for (i = 0; i < 4; i++) both[i] = lenc[i];
        xmemcpy(both + 4, ct, len);
        crypto_poly1305(tag, both, 4 + len, polykey);
        crypto_wipe(both, 4 + len);
    }

    if (emit(s, lenc, 4) < 0) return -1;
    if (emit(s, ct, len) < 0) return -1;
    if (emit(s, tag, 16) < 0) return -1;
    s->seq_out++;
    crypto_wipe(plain, len);
    crypto_wipe(polykey, sizeof polykey);
    return 0;
}

static int send_msg(struct ssh *s, const unsigned char *payload, unsigned n) {
    return s->enc_out ? send_packet_enc(s, payload, n)
                      : send_packet(s, payload, n);
}

/* ---- packet input, encrypted ---- */

static int take_packet_enc(struct ssh *s, const unsigned char **payload,
                           unsigned *plen) {
    unsigned char hdr[4], polykey[32], tag[16];
    unsigned len, total, padlen;

    if (s->in_len < 4) return 0;
    cc_length(s->key_sc, s->seq_in, hdr, s->in);
    len = get32(hdr);
    if (len < 8 || len > SSH_IN_MAX - 32) { fail(s, "absurd packet length"); return -1; }
    total = 4 + len + 16;
    if (s->in_len < total) return 0;

    cc_polykey(s->key_sc, s->seq_in, polykey);
    crypto_poly1305(tag, s->in, 4 + len, polykey);
    crypto_wipe(polykey, sizeof polykey);
    if (crypto_verify16(tag, s->in + 4 + len) != 0) {
        /* One flipped or dropped byte anywhere lands here. On this machine
         * that is worth saying plainly: docs/ssh.md 3 explains why the Tube
         * and the module's read semantics make it a live risk rather than a
         * theoretical one. */
        fail(s, "Poly1305 tag mismatch - the stream is corrupt");
        return -1;
    }

    cc_payload(s->key_sc, s->seq_in, s->pkt, s->in + 4, len);
    padlen = s->pkt[0];
    if (padlen + 1 > len) { fail(s, "padding longer than the packet"); return -1; }
    *payload = s->pkt + 1;
    *plen = len - padlen - 1;
    s->seq_in++;

    /* Compression sits BELOW the message layer: what was compressed is the
     * payload, so it is expanded before anyone looks at the message type. */
    if (s->comp_in && inflate_payload(s, *payload, *plen, payload, plen) < 0) return -1;
    return (int) total;
}


/* ---- decompression, server to client ----
 *
 * zlib@openssh.com is one continuous zlib stream per direction, flushed with
 * Z_SYNC_FLUSH at every packet, and it starts at USERAUTH_SUCCESS rather
 * than at NEWKEYS - that is what the "delayed" means. Because the stream is
 * continuous, the 32KB window carries ACROSS packets, and that is where the
 * win comes from: the second redraw of a screen is largely a reference to
 * the first. docs/ssh.md measures 4-9x for exactly that reason.
 *
 * miniz's tinfl is used rather than a hand-written inflate. Inflate is a
 * well-known source of subtle bugs and a wrong one here does not fail
 * loudly - it delivers plausible-looking rubbish to a terminal.
 *
 * The dictionary is written circularly, which is tinfl's native mode and
 * costs no copying; the bytes are then made contiguous for the parser.
 */
static tinfl_decompressor s_inflator;   /* one connection at a time */

static int inflate_payload(struct ssh *s, const unsigned char *in, unsigned in_len,
                           const unsigned char **out, unsigned *out_len) {
    unsigned produced = 0;
    size_t consumed = 0;

    for (;;) {
        size_t isz = in_len - consumed;
        size_t osz = SSH_DICT_MAX - s->dict_ofs;
        tinfl_status st = tinfl_decompress(
            (tinfl_decompressor *) s->inflator,
            in + consumed, &isz,
            s->dict, s->dict + s->dict_ofs, &osz,
            TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_HAS_MORE_INPUT);

        if (produced + osz > SSH_IN_MAX) { fail(s, "inflated packet too large"); return -1; }
        xmemcpy(s->infl + produced, s->dict + s->dict_ofs, (unsigned) osz);
        produced += (unsigned) osz;
        s->dict_ofs = (s->dict_ofs + (unsigned) osz) & (SSH_DICT_MAX - 1);
        consumed += isz;

        if (st == TINFL_STATUS_HAS_MORE_OUTPUT) continue;
        if (st == TINFL_STATUS_NEEDS_MORE_INPUT) break;   /* a sync flush ends here */
        if (st < 0) { fail(s, "inflate failed - the compressed stream is corrupt"); return -1; }
        if (consumed >= in_len) break;
    }

    *out = s->infl;
    *out_len = produced;
    return 0;
}

/* ---- the key exchange ---- */

static int send_ecdh_init(struct ssh *s) {
    unsigned char msg[64];
    unsigned n = 0;

    rng(s, s->eph_sk, 32);
    crypto_x25519_public_key(s->eph_pk, s->eph_sk);

    msg[n++] = SSH_MSG_KEX_ECDH_INIT;
    n += put_string(msg + n, s->eph_pk, 32);
    return send_msg(s, msg, n);
}

static void derive(struct ssh *s, const unsigned char H[32], char letter,
                   unsigned char *out, unsigned n) {
    struct sha256 h;
    unsigned char k[32];
    unsigned char c = (unsigned char) letter;
    unsigned i, take;

    sha256_init(&h);
    sha256_update(&h, s->kmp, s->kmp_len);
    sha256_update(&h, H, 32);
    sha256_update(&h, &c, 1);
    sha256_update(&h, s->session_id, 32);
    sha256_final(&h, k);

    take = n < 32 ? n : 32;
    for (i = 0; i < take; i++) out[i] = k[i];

    if (n > 32) {
        unsigned char k2[32];
        sha256_init(&h);
        sha256_update(&h, s->kmp, s->kmp_len);
        sha256_update(&h, H, 32);
        sha256_update(&h, k, 32);
        sha256_final(&h, k2);
        for (i = 0; i < n - 32; i++) out[32 + i] = k2[i];
        crypto_wipe(k2, sizeof k2);
    }
    crypto_wipe(k, sizeof k);
}

static int handle_ecdh_reply(struct ssh *s, const unsigned char *p, unsigned n) {
    const unsigned char *ks, *qs, *sig, *pk, *sigblob;
    unsigned kslen, qslen, siglen, off = 1, o2, pklen, sblen;
    unsigned char shared[32], H[32], newkeys[1];
    struct sha256 h;
    unsigned i, zero = 1;

    if (get_string(p, n, &off, &ks, &kslen) < 0 ||
        get_string(p, n, &off, &qs, &qslen) < 0 ||
        get_string(p, n, &off, &sig, &siglen) < 0) {
        fail(s, "malformed KEX_ECDH_REPLY");
        return -1;
    }
    if (qslen != 32) { fail(s, "server ephemeral key is not 32 bytes"); return -1; }
    if (kslen > sizeof s->hostkey) { fail(s, "host key larger than we keep"); return -1; }

    xmemcpy(s->hostkey, ks, kslen);
    s->hostkey_len = kslen;
    sha256(ks, kslen, s->hostkey_fp);

    crypto_x25519(shared, s->eph_sk, qs);
    crypto_wipe(s->eph_sk, sizeof s->eph_sk);
    /* An all-zero shared secret means a low-order public key was supplied
     * and the exchange has no secrecy at all. Monocypher does not refuse it
     * for us in this API, so it is refused here. */
    for (i = 0; i < 32; i++) if (shared[i] != 0) zero = 0;
    if (zero) { fail(s, "server sent a low-order point"); return -1; }

    s->kmp_len = put_mpint(s->kmp, shared, 32);
    crypto_wipe(shared, sizeof shared);

    /* H = HASH(V_C, V_S, I_C, I_S, K_S, Q_C, Q_S, K), all as strings except
     * K, which is an mpint. RFC 8731 for the curve25519 specifics. */
    sha256_init(&h);
    hash_string(&h, (const unsigned char *) s->v_c, xstrlen(s->v_c));
    hash_string(&h, (const unsigned char *) s->v_s, xstrlen(s->v_s));
    hash_string(&h, s->i_c, s->i_c_len);
    hash_string(&h, s->i_s, s->i_s_len);
    hash_string(&h, ks, kslen);
    hash_string(&h, s->eph_pk, 32);
    hash_string(&h, qs, 32);
    sha256_update(&h, s->kmp, s->kmp_len);
    sha256_final(&h, H);

    /* The host key blob is  string "ssh-ed25519", string key(32)  and the
     * signature blob has the same shape with a 64-byte signature. */
    o2 = 0;
    if (get_string(ks, kslen, &o2, &pk, &pklen) < 0) { fail(s, "bad host key blob"); return -1; }
    if (pklen != 11 || xmemcmp(pk, "ssh-ed25519", 11) != 0) {
        fail(s, "host key is not ssh-ed25519");
        return -1;
    }
    if (get_string(ks, kslen, &o2, &pk, &pklen) < 0 || pklen != 32) {
        fail(s, "host key is not 32 bytes");
        return -1;
    }
    o2 = 0;
    if (get_string(sig, siglen, &o2, &sigblob, &sblen) < 0) { fail(s, "bad signature blob"); return -1; }
    if (sblen != 11 || xmemcmp(sigblob, "ssh-ed25519", 11) != 0) {
        fail(s, "signature is not ssh-ed25519");
        return -1;
    }
    if (get_string(sig, siglen, &o2, &sigblob, &sblen) < 0 || sblen != 64) {
        fail(s, "signature is not 64 bytes");
        return -1;
    }

    /* This proves the server holds the private half of the key it presented.
     * It does NOT prove the key is the one we meant to talk to - that is
     * known_hosts, and it belongs to the caller, which is why hostkey and
     * hostkey_fp are exposed rather than judged here. */
    if (crypto_ed25519_check(sigblob, pk, H, 32) != 0) {
        fail(s, "host key signature does not verify");
        return -1;
    }

    /* First exchange: the session id is H, and stays H for the life of the
     * connection even when later rekeys produce a new H. */
    for (i = 0; i < 32; i++) s->session_id[i] = H[i];

    derive(s, H, 'C', s->key_cs, 64);
    derive(s, H, 'D', s->key_sc, 64);

    newkeys[0] = SSH_MSG_NEWKEYS;
    if (send_msg(s, newkeys, 1) < 0) return -1;
    s->enc_out = 1;
    if (s->strict_kex) s->seq_out = 0;   /* the debt from advertising it */

    /* Stop here unless the caller has already said this key is the right
     * one. The signature above proves the server holds the private half of
     * the key it presented, which any impostor's own key satisfies too. */
    s->state = s->host_ok ? SSH_ST_NEWKEYS : SSH_ST_NEEDHOST;
    return 0;
}

static int send_service_request(struct ssh *s) {
    unsigned char msg[32];
    unsigned n = 0;
    msg[n++] = SSH_MSG_SERVICE_REQUEST;
    n += put_string(msg + n, (const unsigned char *) "ssh-userauth", 12);
    return send_msg(s, msg, n);
}


/* ---- authentication ----
 *
 * publickey with Ed25519, and nothing else. Password authentication is not
 * implemented and will not be: the gateway of docs/ssh.md exists precisely
 * so that no password is ever typed at the Beeb, and a client that can send
 * one invites someone to.
 *
 * The signature covers  string(session_id) || the request up to and
 * including the public key blob.  RFC 4252 7. The session id is what binds
 * the signature to THIS connection; without it a captured signature would
 * replay against any server holding the same key.
 */
static unsigned put_pubkey_blob(unsigned char *out, const unsigned char pk[32]) {
    unsigned n = 0;
    n += put_string(out + n, (const unsigned char *) "ssh-ed25519", 11);
    n += put_string(out + n, pk, 32);
    return n;
}

static int send_userauth(struct ssh *s) {
    unsigned char blob[64], req[512], signed_data[640], sig[64], sigblob[128];
    unsigned bn, rn = 0, sn = 0, gn = 0;

    if (!s->have_key) { fail(s, "no key set - call ssh_set_auth"); return -1; }

    bn = put_pubkey_blob(blob, s->auth_pk);

    req[rn++] = SSH_MSG_USERAUTH_REQUEST;
    rn += put_string(req + rn, (const unsigned char *) s->user, xstrlen(s->user));
    rn += put_string(req + rn, (const unsigned char *) "ssh-connection", 14);
    rn += put_string(req + rn, (const unsigned char *) "publickey", 9);
    req[rn++] = 1;                                  /* signature follows */
    rn += put_string(req + rn, (const unsigned char *) "ssh-ed25519", 11);
    rn += put_string(req + rn, blob, bn);

    sn += put_string(signed_data + sn, s->session_id, 32);
    xmemcpy(signed_data + sn, req, rn);
    sn += rn;

    crypto_ed25519_sign(sig, s->auth_sk, signed_data, sn);

    gn += put_string(sigblob + gn, (const unsigned char *) "ssh-ed25519", 11);
    gn += put_string(sigblob + gn, sig, 64);

    /* The signature field is a STRING CONTAINING the blob, not the blob
     * appended. Getting this wrong is not a silent mismatch: sshd answers
     * "parse signature packet: unexpected bytes remain after decoding" and
     * drops the connection, which from the client looks like a plain refusal
     * with no reason given. */
    rn += put_string(req + rn, sigblob, gn);

    crypto_wipe(signed_data, sn);
    return send_msg(s, req, rn);
}

/* Password authentication. NOT offered first and never offered alone: the
 * key is tried, and this runs only if the server refuses it - which is what
 * ssh itself does, and it means the usual case sends no password at all.
 *
 * Earlier versions of this file said passwords "are not implemented and will
 * not be". That was reasoning carried over from the telnet gateway, where a
 * password crossed the LAN in clear. Inside SSH it is encrypted like
 * everything else, so the objection applied to the gateway and not here.
 */
static int send_userauth_pass(struct ssh *s) {
    unsigned char req[512];
    unsigned n = 0, i;

    req[n++] = SSH_MSG_USERAUTH_REQUEST;
    n += put_string(req + n, (const unsigned char *) s->user, xstrlen(s->user));
    n += put_string(req + n, (const unsigned char *) "ssh-connection", 14);
    n += put_string(req + n, (const unsigned char *) "password", 8);
    req[n++] = 0;                       /* not a change-password request */
    n += put_string(req + n, (const unsigned char *) s->pass, xstrlen(s->pass));

    s->tried_pass = 1;
    /* Gone from the struct the moment it is in the packet. */
    for (i = 0; i < sizeof s->pass; i++) s->pass[i] = 0;
    s->have_pass = 0;

    if (send_msg(s, req, n) < 0) return -1;
    crypto_wipe(req, n);
    return 0;
}

static int drain(struct ssh *s);

static const char B64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int ssh_hostkey_fp(struct ssh *s, char *out, unsigned max) {
    static const char pre[] = "SHA256:";
    unsigned i, o = 0, bits = 0, acc = 0;
    if (s->hostkey_len == 0) return -1;
    if (max < sizeof pre + 43) return -1;
    for (i = 0; i < sizeof pre - 1; i++) out[o++] = pre[i];
    /* Unpadded base64, which is what ssh-keygen prints: 32 bytes is 256 bits
     * and 43 characters carry 258, so the last one is short and there is no
     * "=" on the end. */
    for (i = 0; i < 32; i++) {
        acc = (acc << 8) | s->hostkey_fp[i];
        bits += 8;
        while (bits >= 6) { bits -= 6; out[o++] = B64[(acc >> bits) & 63]; }
    }
    if (bits) out[o++] = B64[(acc << (6 - bits)) & 63];
    out[o] = 0;
    return (int) o;
}

int ssh_accept_host(struct ssh *s) {
    if (s->state != SSH_ST_NEEDHOST) return -1;
    s->host_ok = 1;
    s->state = SSH_ST_NEWKEYS;
    return drain(s);
}

int ssh_set_password(struct ssh *s, const char *pw) {
    unsigned i;
    if (s->state != SSH_ST_NEEDPASS) { fail(s, "no password was asked for"); return -1; }
    for (i = 0; i + 1 < sizeof s->pass && pw[i] && pw[i] != 13; i++) s->pass[i] = pw[i];
    s->pass[i] = 0;
    s->have_pass = 1;
    s->state = SSH_ST_AUTH;
    return send_userauth_pass(s);
}

/* ---- the session channel ----
 *
 * WHY THE WINDOW IS SMALL. RFC 4254's window is end-to-end flow control that
 * lives below the application, and unlike XOFF/XON nothing on the target can
 * switch it off - full-screen-apps.md explains why that matters here.
 * Advertising a small window means the server BLOCKS instead of filling the
 * module's 76KB buffer, so the 18-second wait after pressing q cannot form.
 * 8KB is about two seconds of Tube time: enough to keep the link busy, small
 * enough that a runaway program stops rather than queues.
 */
#define WIN_INITIAL 8192
#define WIN_REFILL  4096

static int send_channel_open(struct ssh *s) {
    unsigned char msg[64];
    unsigned n = 0;
    msg[n++] = SSH_MSG_CHANNEL_OPEN;
    n += put_string(msg + n, (const unsigned char *) "session", 7);
    put32(msg + n, s->chan_local); n += 4;
    put32(msg + n, WIN_INITIAL);   n += 4;
    put32(msg + n, 4096);          n += 4;   /* our largest packet */
    s->win_in = WIN_INITIAL;
    s->win_used = 0;
    return send_msg(s, msg, n);
}

static int send_pty_req(struct ssh *s) {
    unsigned char msg[256];
    unsigned n = 0;
    msg[n++] = SSH_MSG_CHANNEL_REQUEST;
    put32(msg + n, s->chan_remote); n += 4;
    n += put_string(msg + n, (const unsigned char *) "pty-req", 7);
    msg[n++] = 1;                                   /* want reply */
    n += put_string(msg + n, (const unsigned char *) "xterm-256color", 14);
    put32(msg + n, s->cols); n += 4;
    put32(msg + n, s->rows); n += 4;
    put32(msg + n, 0); n += 4;                      /* pixel width */
    put32(msg + n, 0); n += 4;                      /* pixel height */
    /* Empty modes: the defaults are what a terminal wants, and every mode we
     * might set is one the far end's applications will change anyway. */
    put32(msg + n, 0); n += 4;
    return send_msg(s, msg, n);
}

static int send_shell(struct ssh *s) {
    unsigned char msg[64];
    unsigned n = 0;
    msg[n++] = SSH_MSG_CHANNEL_REQUEST;
    put32(msg + n, s->chan_remote); n += 4;
    n += put_string(msg + n, (const unsigned char *) "shell", 5);
    msg[n++] = 1;
    return send_msg(s, msg, n);
}

static int send_window_adjust(struct ssh *s, unsigned add) {
    unsigned char msg[16];
    unsigned n = 0;
    msg[n++] = SSH_MSG_CHANNEL_WINDOW_ADJUST;
    put32(msg + n, s->chan_remote); n += 4;
    put32(msg + n, add); n += 4;
    s->win_in += add;
    return send_msg(s, msg, n);
}

void ssh_set_size(struct ssh *s, unsigned cols, unsigned rows) {
    s->cols = cols;
    s->rows = rows;
    if (s->state == SSH_ST_OPEN) {
        unsigned char msg[64];
        unsigned n = 0;
        msg[n++] = SSH_MSG_CHANNEL_REQUEST;
        put32(msg + n, s->chan_remote); n += 4;
        n += put_string(msg + n, (const unsigned char *) "window-change", 13);
        msg[n++] = 0;                               /* no reply for this one */
        put32(msg + n, cols); n += 4;
        put32(msg + n, rows); n += 4;
        put32(msg + n, 0); n += 4;
        put32(msg + n, 0); n += 4;
        send_msg(s, msg, n);
    }
}

int ssh_set_auth(struct ssh *s, const char *user,
                 const unsigned char pk[32], const unsigned char seed[32]) {
    unsigned char scratch[32], derived[32];
    unsigned i;

    xcopy(s->user, sizeof s->user, user, xstrlen(user));

    /* Monocypher signs with the EXPANDED key, seed || public, and builds it
     * from the seed - wiping the seed as it goes, hence the copy. Deriving
     * the public half rather than trusting the file also checks the two
     * halves belong together, which turns a mis-parsed key container into an
     * error here instead of an unexplained "server refused our key". */
    for (i = 0; i < 32; i++) scratch[i] = seed[i];
    crypto_ed25519_key_pair(s->auth_sk, derived, scratch);

    for (i = 0; i < 32; i++) {
        if (derived[i] != pk[i]) {
            fail(s, "private key does not match its public half");
            return -1;
        }
    }
    for (i = 0; i < 32; i++) s->auth_pk[i] = pk[i];
    s->have_key = 1;
    return 0;
}

int ssh_write(struct ssh *s, const unsigned char *p, unsigned n) {
    unsigned char msg[SSH_OUT_MAX];
    unsigned k = 0;
    if (s->state != SSH_ST_OPEN) { fail(s, "write before the shell is open"); return -1; }
    if (n > s->win_out) return -1;      /* the server will not take it yet */
    if (n > s->max_out) n = s->max_out;
    if (n + 16 > sizeof msg) return -1;
    msg[k++] = SSH_MSG_CHANNEL_DATA;
    put32(msg + k, s->chan_remote); k += 4;
    k += put_string(msg + k, p, n);
    if (send_msg(s, msg, k) < 0) return -1;
    s->win_out -= n;
    return 0;
}

/* Channel data in: hand it to the application and keep the window topped up.
 * The refill is deliberately lazy - one adjust per WIN_REFILL bytes rather
 * than one per packet, because every adjust is a send and every send on the
 * Beeb is a 3.28ms OSWORD call. */
static int handle_channel_data(struct ssh *s, const unsigned char *p, unsigned n) {
    unsigned off = 5;           /* type + recipient channel */
    const unsigned char *d;
    unsigned dlen, i;
    if (get_string(p, n, &off, &d, &dlen) < 0) { fail(s, "bad CHANNEL_DATA"); return -1; }
    if (s->app_len + dlen > SSH_APP_MAX) { fail(s, "application buffer overrun"); return -1; }
    for (i = 0; i < dlen; i++) s->app[s->app_len + i] = d[i];
    s->app_len += dlen;

    s->win_used += dlen;
    if (s->win_used >= WIN_REFILL) {
        if (send_window_adjust(s, s->win_used) < 0) return -1;
        s->win_used = 0;
    }
    return 0;
}

/* ---- the pump ---- */

void ssh_init(struct ssh *s, const unsigned char seed[32], int compress_sc) {
    unsigned i;
    unsigned char *z = (unsigned char *) s;
    for (i = 0; i < sizeof *s; i++) z[i] = 0;
    s->state = SSH_ST_VERSION;
    s->want_compress_sc = compress_sc;
    s->cols = 80;
    s->rows = 64;
    s->chan_local = 0;

    for (i = 0; i < 32; i++) s->rng_key[i] = seed[i];
    s->rng_ctr = 0;
    rng(s, s->cookie, 16);

    xcopy(s->v_c, SSH_VER_MAX, CLIENT_ID, xstrlen(CLIENT_ID));
    emit(s, (const unsigned char *) CLIENT_ID, xstrlen(CLIENT_ID));
    emit(s, (const unsigned char *) "\r\n", 2);
}

int ssh_input(struct ssh *s, const unsigned char *p, unsigned n) {
    if (s->state == SSH_ST_ERROR) return -1;
    if (s->in_len + n > SSH_IN_MAX) {
        fail(s, "input buffer overrun - peer sent more than a packet");
        return -1;
    }
    xmemcpy(s->in + s->in_len, p, n);
    s->in_len += n;

    if (s->state == SSH_ST_VERSION) {
        int r = take_version(s);
        if (r < 0) return -1;
        if (r == 0) return 0;
        if (build_kexinit(s) < 0) return -1;
        s->state = SSH_ST_KEXINIT;
    }

    return drain(s);
}

/* Whatever is already buffered, taken apart a packet at a time. Split out of
 * ssh_input so that ssh_accept_host can resume it: the server's NEWKEYS has
 * usually arrived in the same read as the key exchange reply and is sitting
 * in s->in while the caller decides, and nothing else would ever come to
 * wake it. */
static int drain(struct ssh *s) {
    for (;;) {
        const unsigned char *pay;
        unsigned plen;
        int total;
        if (s->state == SSH_ST_NEEDHOST) return 0;
        total = s->enc_in ? take_packet_enc(s, &pay, &plen)
                          : take_packet(s, &pay, &plen);
        if (total < 0) return -1;
        if (total == 0) return 0;
        if (plen == 0) { fail(s, "empty payload"); return -1; }

        switch (pay[0]) {
        case SSH_MSG_KEXINIT:
            if (handle_kexinit(s, pay, plen) < 0) return -1;
            break;
        case SSH_MSG_KEX_ECDH_REPLY:
            if (s->state != SSH_ST_KEXREPLY) { fail(s, "unexpected ECDH reply"); return -1; }
            if (handle_ecdh_reply(s, pay, plen) < 0) return -1;
            break;
        case SSH_MSG_NEWKEYS:
            if (s->state != SSH_ST_NEWKEYS) { fail(s, "unexpected NEWKEYS"); return -1; }
            s->enc_in = 1;
            if (s->strict_kex) s->seq_in = 0;
            if (send_service_request(s) < 0) return -1;
            s->state = SSH_ST_SERVICE;
            break;
        case SSH_MSG_SERVICE_ACCEPT:
            if (s->state != SSH_ST_SERVICE) { fail(s, "unexpected SERVICE_ACCEPT"); return -1; }
            if (send_userauth(s) < 0) return -1;
            s->state = SSH_ST_AUTH;
            break;
        case SSH_MSG_USERAUTH_SUCCESS:
            /* zlib@openssh.com starts HERE, not at NEWKEYS - that is what
             * the "delayed" in delayed compression means. Until inflate
             * exists, saying so is far better than the alternative, which is
             * a session that negotiates cleanly and then delivers noise. */
            if (s->algs.comp_sc[0] != 'n') {
                s->inflator = &s_inflator;
                tinfl_init((tinfl_decompressor *) s->inflator);
                s->dict_ofs = 0;
                s->comp_in = 1;
            }
            if (send_channel_open(s) < 0) return -1;
            s->state = SSH_ST_CHANNEL;
            break;
        case SSH_MSG_USERAUTH_FAILURE:
            /* A refusal is only final once the password has been tried too.
             * Stopping here lets the caller ask for one - it has the
             * keyboard and this does not. */
            if (!s->tried_pass) {
                s->state = SSH_ST_NEEDPASS;
                break;
            }
            fail(s, "the server refused both the key and the password");
            return -1;
        case SSH_MSG_USERAUTH_PK_OK:
            break;              /* only sent for a query we never make */
        case SSH_MSG_USERAUTH_BANNER:
            break;              /* a message for a human, and there is none */
        case SSH_MSG_CHANNEL_OPEN_CONFIRM:
            if (plen < 17) { fail(s, "short OPEN_CONFIRMATION"); return -1; }
            s->chan_remote = get32(pay + 5);
            s->win_out     = get32(pay + 9);
            s->max_out     = get32(pay + 13);
            if (s->max_out > 4096) s->max_out = 4096;
            if (send_pty_req(s) < 0) return -1;
            s->state = SSH_ST_PTY;
            break;
        case SSH_MSG_CHANNEL_OPEN_FAILURE:
            fail(s, "the server refused the session channel");
            return -1;
        case SSH_MSG_CHANNEL_SUCCESS:
            if (s->state == SSH_ST_PTY) {
                if (send_shell(s) < 0) return -1;
                s->state = SSH_ST_SHELL;
            } else if (s->state == SSH_ST_SHELL) {
                s->state = SSH_ST_OPEN;
            }
            break;
        case SSH_MSG_CHANNEL_FAILURE:
            fail(s, s->state == SSH_ST_PTY ? "the server refused a pty"
                                           : "the server refused a shell");
            return -1;
        case SSH_MSG_CHANNEL_WINDOW_ADJUST:
            if (plen >= 9) s->win_out += get32(pay + 5);
            break;
        case SSH_MSG_CHANNEL_DATA:
            if (handle_channel_data(s, pay, plen) < 0) return -1;
            break;
        case SSH_MSG_CHANNEL_EXTENDED_DATA:
            break;              /* stderr: a pty merges it, so this is spare */
        case SSH_MSG_CHANNEL_EOF:
            break;
        case SSH_MSG_CHANNEL_CLOSE:
            /* TYPING exit AT THE SHELL ARRIVES HERE, and it is not a fault.
             * Treating it as one made the terminal's shutdown a race: this
             * path ended the program through its error handler, skipping the
             * profile and glass-check writes, while the TCP close arriving
             * first took the clean path and wrote them. Same user action,
             * two different outcomes depending on which packet won. */
            s->state = SSH_ST_CLOSED;
            return 0;
        case SSH_MSG_GLOBAL_REQUEST:
            break;              /* we grant nothing, and none wants a reply */
        case SSH_MSG_EXT_INFO:
            break;              /* RFC 8308: advisory, and we ask nothing of it */
        case SSH_MSG_IGNORE:
        case SSH_MSG_DEBUG:
        case SSH_MSG_UNIMPLEMENTED:
            /* Strict KEX makes these fatal during the initial exchange -
             * that is the whole point of the mitigation, since tolerating
             * them is what lets an attacker insert packets to shift the
             * sequence numbers. Afterwards they are ordinary and ignorable. */
            if (s->strict_kex && !s->enc_in) {
                fail(s, "IGNORE/DEBUG during strict KEX - refusing");
                return -1;
            }
            break;
        case SSH_MSG_DISCONNECT:
            fail(s, "server sent DISCONNECT");
            return -1;
        default:
            /* Not an error yet - later messages arrive once the handshake
             * goes further than this build does. */
            break;
        }
        drop_packet(s, (unsigned) total);
        if (s->state == SSH_ST_ERROR) return -1;
    }
}

const char *ssh_strstate(const struct ssh *s) {
    switch (s->state) {
    case SSH_ST_VERSION:    return "waiting for server version";
    case SSH_ST_KEXINIT:    return "waiting for server KEXINIT";
    case SSH_ST_KEXREPLY:   return "waiting for the key exchange reply";
    case SSH_ST_NEWKEYS:    return "keys derived, waiting for NEWKEYS";
    case SSH_ST_NEEDHOST:   return "waiting for the host key to be approved";
    case SSH_ST_SERVICE:    return "encrypted, ssh-userauth requested";
    case SSH_ST_AUTH:       return "waiting for authentication";
    case SSH_ST_CHANNEL:    return "authenticated, opening a session";
    case SSH_ST_PTY:        return "waiting for the pty";
    case SSH_ST_SHELL:      return "waiting for the shell";
    case SSH_ST_OPEN:       return "a shell is running";
    case SSH_ST_CLOSED:     return "the far end closed the session";
    case SSH_ST_NEEDPASS:   return "the key was refused - a password is needed";
    default:                return "error";
    }
}
