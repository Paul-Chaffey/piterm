/* SPIKE1 - does compiled C run on copro 15?
 *
 * docs/ssh.md makes this the gate on options 2, 3 and 4, and on the
 * purpose-built core of specification.md 8 Step 3 as well. It answers one
 * question: can a cross-compiled ARM binary be loaded onto the native ARM
 * co-processor, run, reach the OS, touch memory and return to BASIC.
 *
 * Nothing here is useful work. Every line exists to make a FAILURE tell you
 * where it failed, because a blob that crashes the machine says nothing at
 * all otherwise.
 *
 * FIVE STAGES, each one printing or writing before the next is attempted.
 * The stage counter is written to the parameter block FIRST at every step,
 * so even a hang leaves a number behind that BASIC can read after a BREAK:
 *
 *   1  os_writec  - the simplest SWI there is, no pointer involved
 *   2  os_write0  - a SWI taking a POINTER into our own .rodata, which is
 *                   what proves the blob was loaded where we think it was
 *   3  os_newline - a SWI taking nothing, and tidies the line
 *   4  arithmetic on the parameter block - data memory works both ways
 *   5  return     - the epilogue runs and BASIC gets control back
 *
 * If stage 2 prints garbage rather than SPIKE1, the code is running but the
 * absolute addresses are wrong, which means the load address and the link
 * address disagree. That is the single most likely failure and it is worth
 * being able to recognise on sight.
 *
 * WHY FIXED ADDRESSES rather than position-independent code. -fPIC on ARM
 * wants a GOT, and setting one up is more moving parts than the thing being
 * tested. The co-processor has 200MB of application space (copro-armnative.c
 * sets MEMORY_LIMIT_HANDLER) and BASIC's HIMEM is &4000000, so there is 134MB
 * above BASIC that nothing else claims. The blob links and loads at
 * &4100000, one megabyte above HIMEM, and the parameter block sits at
 * &4108000. Both are arbitrary; both must match test/armspike.bas.
 *
 * WHY NOT *RUN. LANManFS ignores .inf files (tools/ssd-extract.py), so the
 * share cannot carry a load or exec address and *RUN would have nothing to
 * work from. test/armspike.bas uses *LOAD with an explicit address instead,
 * which is also easier to debug because the address is ours.
 */

/* Parameter block. volatile because nothing here reads what it writes and
 * -O2 would otherwise be entitled to drop every store in this file. */
#define PARAM ((volatile unsigned int *) 0x04108000u)

#define P_IN     0      /* in:  a number BASIC poked before calling */
#define P_OUT    1      /* out: 2 * in + 1, so a wrong answer is obvious */
#define P_R0     2      /* out: r0 exactly as received - see below */
#define P_MAGIC  3      /* out: proof this code, and not something else, ran */
#define P_STAGE  4      /* out: how far it got */

#define MAGIC 0x5B1CE001u

/* P_R0 is a MEASUREMENT, not a check. Whether BBC BASIC V's CALL and USR
 * pass A% in r0 is documented inconsistently and this project has been
 * caught before by trusting a wiki over the machine. So the blob records
 * what it was actually handed and BASIC prints it. Whatever comes back is
 * the answer for this BASIC on this core. */

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

/* The entry point, and it MUST be the first byte of the binary - the blob is
 * called at its base address. tools/armbuild.sh checks that rather than
 * assuming it, because gcc is under no obligation to lay it out that way. */
unsigned int _start(unsigned int r0) {
    PARAM[P_STAGE] = 0;
    PARAM[P_R0]    = r0;
    PARAM[P_MAGIC] = MAGIC;

    PARAM[P_STAGE] = 1;
    os_writec('*');

    PARAM[P_STAGE] = 2;
    os_write0("SPIKE1");

    PARAM[P_STAGE] = 3;
    os_newline();

    PARAM[P_STAGE] = 4;
    PARAM[P_OUT] = PARAM[P_IN] * 2u + 1u;

    PARAM[P_STAGE] = 5;
    return PARAM[P_OUT];
}
