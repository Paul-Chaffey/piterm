/* beeb.ld - where the blob's pieces go.
 *
 * The blob is CALLed at its base address, so the entry point must be the
 * FIRST byte of the file. With -ffunction-sections gcc emits one section per
 * function and the linker is free to order them as it likes, so the entry is
 * put in a section of its own and named first here. tools/sshbuild.sh checks
 * afterwards that _start really did land at the base, rather than trusting
 * this to have worked.
 *
 * .bss is given symbols instead of being dropped. *LOAD writes only what is
 * in the file, so BSS arrives holding whatever the previous program left in
 * that memory - which is a fault that reproduces intermittently and looks
 * like anything but its cause. src/ssh/beeb.c clears it on OP_INIT.
 *
 * The address matches src/ssh/beeb.c and test/sshbeeb.bas. All three must
 * agree, and the BASIC prints what it used so a mismatch is visible rather
 * than mysterious.
 */

ENTRY(_start)

SECTIONS
{
    . = 0x04100000;

    .text : {
        *(.text.entry)
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
    }

    . = ALIGN(4);
    __bss_start__ = .;
    .bss : {
        *(.bss*)
        *(COMMON)
    }
    . = ALIGN(4);
    __bss_end__ = .;

    /DISCARD/ : {
        *(.ARM.exidx*)
        *(.comment)
        *(.note*)
    }
}
