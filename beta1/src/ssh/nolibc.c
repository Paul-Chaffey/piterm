/* nolibc.c - the four functions a freestanding build still needs.
 *
 * -ffreestanding does NOT mean the compiler stops emitting calls to memcpy,
 * memset, memmove and memcmp. It emits them for structure assignment, for
 * array initialisation, and wherever it decides a loop is better written as
 * one - and gcc is entitled to do that even in code that never names them.
 * miniz's inflate calls two of them outright.
 *
 * On Linux the libc versions are linked and this file is not used. On copro
 * 15 there is no libc at all, so these are what the blob gets. They are
 * deliberately the obvious implementations: this is not where performance
 * lives, and a clever memcpy is a good way to spend an evening.
 *
 * The point of building them into the ARM link in tools/sshbuild.sh is that
 * an undefined symbol becomes a build failure here, on Linux, rather than a
 * blob that loads onto the Beeb and jumps to address zero.
 */

typedef unsigned long size_t_;

void *memcpy(void *d, const void *s, size_t_ n);
void *memset(void *d, int c, size_t_ n);
void *memmove(void *d, const void *s, size_t_ n);
int memcmp(const void *a, const void *b, size_t_ n);

void *memcpy(void *d, const void *s, size_t_ n) {
    unsigned char *a = (unsigned char *) d;
    const unsigned char *b = (const unsigned char *) s;
    while (n--) *a++ = *b++;
    return d;
}

void *memset(void *d, int c, size_t_ n) {
    unsigned char *a = (unsigned char *) d;
    while (n--) *a++ = (unsigned char) c;
    return d;
}

/* Overlap-safe, which memcpy is not. inflate copies overlapping runs out of
 * its own window, so this one is not decoration. */
void *memmove(void *d, const void *s, size_t_ n) {
    unsigned char *a = (unsigned char *) d;
    const unsigned char *b = (const unsigned char *) s;
    if (a == b || n == 0) return d;
    if (a < b) {
        while (n--) *a++ = *b++;
    } else {
        a += n;
        b += n;
        while (n--) *--a = *--b;
    }
    return d;
}

int memcmp(const void *a, const void *b, size_t_ n) {
    const unsigned char *x = (const unsigned char *) a;
    const unsigned char *y = (const unsigned char *) b;
    while (n--) {
        if (*x != *y) return (int) *x - (int) *y;
        x++; y++;
    }
    return 0;
}
