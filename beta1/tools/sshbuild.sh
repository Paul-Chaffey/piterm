#!/bin/bash
# Build the SSH core, for BOTH targets, every time.
#
#   tools/sshbuild.sh          build/sshtry, and prove the core cross-compiles
#
# THE CROSS-COMPILE IS NOT OPTIONAL and that is the point of doing it here
# rather than at the end. The core is meant to be byte-identical on the
# deskbox box and on copro 15, and the way that stops being true is
# gradually: a size_t here, a printf for debugging there, an include that
# pulls in libc. Building for arm-none-eabi with -nostdlib on every run makes
# each of those a build failure the moment it is written, instead of a
# surprise weeks later when the code first meets the Beeb.
#
# -Werror for the same reason. This code will run where there is no debugger
# and no stderr.

set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$here/build"

WARN="-Wall -Wextra -Werror"

# miniz carries deflate and zip as well as inflate; this project wants only
# inflate. NDEBUG removes its assert(), which would otherwise be the one
# libc symbol nolibc.c does not supply.
MINIZ="-DMINIZ_NO_STDIO -DMINIZ_NO_TIME -DMINIZ_NO_MALLOC -DMINIZ_NO_ARCHIVE_APIS \
       -DMINIZ_NO_DEFLATE_APIS -DMINIZ_NO_ZLIB_APIS -DNDEBUG"
INC="-I$here/vendor/miniz"

# The core, as it will be on the parasite: freestanding, no libc, ARM.
# The core, shared by both targets.
SRC="src/ssh/ssh.c src/ssh/sha256.c \
     vendor/monocypher/monocypher.c vendor/monocypher/monocypher-ed25519.c \
     vendor/miniz/miniz_tinfl.c"

# ARM ONLY. nolibc.c must never reach the native link: glibc already has
# these, and gcc at -O2 recognises the loop in its own memcpy and compiles it
# into a call to memcpy - itself. The result is infinite recursion, a stack
# overflow and a SIGSEGV a long way from the cause. -fno-builtin on the ARM
# side is what stops the same thing happening there.
ARM_ONLY="src/ssh/nolibc.c src/ssh/beeb.c"

for f in $SRC $ARM_ONLY; do
    # shellcheck disable=SC2086
    arm-none-eabi-gcc -c -O2 -marm -march=armv7-a $WARN $MINIZ $INC \
        -ffreestanding -nostdlib -fno-builtin -ffunction-sections \
        -o "$here/build/$(basename "$f" .c)-arm.o" "$here/$f"
done

# THE LINK IS THE CHECK. Compiling each file proves it parses; linking them
# together with -nostdlib proves nothing reaches for a libc that is not there.
# An undefined symbol found here is a build failure on Linux; found later it
# is a blob that loads onto the Beeb and branches into nowhere.
# libgcc, not libc. Monocypher divides, and ARM without hardware divide gets
# __aeabi_uidiv and __aeabi_uldivmod from the compiler's own support library -
# which ships with the toolchain and is not a hosted-environment dependency.
LIBGCC=$(arm-none-eabi-gcc -print-libgcc-file-name)
rm -f "$here/build/linkcheck.o"
arm-none-eabi-ld -r -o "$here/build/linkcheck.o" "$here"/build/*-arm.o "$LIBGCC"
# __bss_start__ and __bss_end__ are defined by beeb.ld at the FINAL link, so
# they are legitimately unresolved at this stage and only here.
undef=$(arm-none-eabi-nm -u "$here/build/linkcheck.o" |
        grep -vE "__bss_start__|__bss_end__" || true)
if [ -n "$undef" ]; then
    echo "sshbuild: UNDEFINED SYMBOLS in the ARM core:" >&2
    echo "$undef" >&2
    exit 1
fi

# The same core natively, plus the harness, which DOES use libc - it is the
# half that never leaves Linux.
CORE=""
for f in $SRC; do CORE="$CORE $here/$f"; done

# shellcheck disable=SC2086
gcc -O2 $WARN $MINIZ $INC -o "$here/build/sshtry" "$here/tools/sshtry.c" $CORE
# shellcheck disable=SC2086
gcc -O2 $WARN -o "$here/build/sshtest" "$here/tools/sshtest.c" "$here/src/ssh/sha256.c"

arm=$(arm-none-eabi-size "$here/build/linkcheck.o" | tail -1 | awk '{print $1}')
echo "sshbuild: core $arm bytes of ARM text (before --gc-sections)"
"$here/build/sshtest" >/dev/null || { echo "sshbuild: PRIMITIVE TESTS FAILED" >&2; exit 1; }

# The blob the Beeb actually loads. --gc-sections drops everything nothing
# reaches, which on a library as broad as Monocypher is most of it.
arm-none-eabi-ld -T "$here/src/ssh/beeb.ld" --gc-sections \
    -o "$here/build/sshblob.elf" "$here"/build/*-arm.o "$LIBGCC"

entry=$(arm-none-eabi-readelf -h "$here/build/sshblob.elf" | sed -n 's/.*Entry point address: *//p')
start=$(arm-none-eabi-nm "$here/build/sshblob.elf" | sed -n 's/^0*\([0-9a-f]*\) T _start$/0x\1/p')
[ "$((entry))" -eq "$((0x04100000))" ] || { echo "sshbuild: entry $entry is not the base" >&2; exit 1; }
[ "$((start))" -eq "$((0x04100000))" ] || { echo "sshbuild: _start at $start is not first" >&2; exit 1; }

arm-none-eabi-objcopy -O binary "$here/build/sshblob.elf" "$here/build/SSHBLOB"
blob=$(stat -c%s "$here/build/SSHBLOB")

# THE CHECK THIS COST AN EVENING TO LEARN. The parameter block and the session
# live at fixed addresses that BASIC also knows, and on 2026-08-28 the blob
# grew past one of them: BASIC wrote its arguments 32,768 bytes into the
# blob's own code and the session wedged after "connected". Addresses chosen
# for a 131-byte spike do not survive a 48KB one.
BLOB_BASE=$((0x04100000))
BLOB_PARAM=$((0x04200000))
if [ "$((BLOB_BASE + blob))" -ge "$BLOB_PARAM" ]; then
    echo "sshbuild: BLOB HAS GROWN INTO THE PARAMETER BLOCK" >&2
    printf 'sshbuild:   blob ends at 0x%X, parameters are at 0x%X\n' \
        "$((BLOB_BASE + blob))" "$BLOB_PARAM" >&2
    echo "sshbuild:   move PARAM/SESSION in src/ssh/beeb.c and par% in test/sshbeeb.bas" >&2
    exit 1
fi
bss=$(arm-none-eabi-nm "$here/build/sshblob.elf" | awk '/__bss_start__/{s=strtonum("0x"$1)} /__bss_end__/{e=strtonum("0x"$1)} END{print e-s}')
sum=$(od -An -tu1 -v "$here/build/SSHBLOB" | awk '{for (i = 1; i <= NF; i++) s += $i} END {print s + 0}')

echo "sshbuild: primitives pass, build/sshtry linked"
echo "sshbuild: build/SSHBLOB  $blob bytes  sum $sum  bss $bss  entry $entry"

# Patch the driver's constants rather than leaving three numbers to be copied
# by hand. "Was that the latest code?" is a question this project has paid
# for once already.
bas="$here/test/sshbeeb.bas"
id=$(printf '%04X' $((sum & 0xFFFF)))
if [ -f "$bas" ]; then
    sed -i "s/^\( *[0-9]* *\)len%=[0-9]*\(:REM BUILDSTAMP-LEN\)$/\1len%=$blob\2/" "$bas"
    sed -i "s/^\( *[0-9]* *\)sum%=[0-9]*\(:REM BUILDSTAMP-SUM\)$/\1sum%=$sum\2/" "$bas"
    sed -i "s/^\( *[0-9]* *\)bid\$=\"[^\"]*\"\(:REM BUILDSTAMP-ID\)$/\1bid\$=\"$id\"\2/" "$bas"
    echo "sshbuild: patched $bas  len%=$blob sum%=$sum bid\$=\"$id\""
fi

# PTERM CARRIES ITS OWN COPY OF THESE THREE CONSTANTS, and on 2026-08-28 it
# went stale while test/sshbeeb.bas was patched automatically: the blob changed
# by one message handler, the LENGTH stayed identical at 48,844, and only the
# checksum caught it. A constant duplicated in two files of which one is
# maintained is the same fault as the parameter block that grew into the blob.
pt="$here/src/pterm.bas"
if [ -f "$pt" ]; then
    grep -q "REM BUILDSTAMP-SSH$" "$pt" ||
        { echo "sshbuild: no REM BUILDSTAMP-SSH line in $pt" >&2; exit 1; }
    sed -i "s/^\\( *[0-9]* *\\)sshlen%=[0-9]*:sshsum%=[0-9]*:\\(sshver%=[^:]*\\)\\(:REM BUILDSTAMP-SSH\\)$/\\1sshlen%=$blob:sshsum%=$sum:\\2\\3/" "$pt"
    grep -q "sshsum%=$sum:" "$pt" ||
        { echo "sshbuild: FAILED to patch $pt - its constants are now stale" >&2; exit 1; }
    echo "sshbuild: patched $pt  sshlen%=$blob sshsum%=$sum"
fi

# THE STATE NUMBERS BASIC HARDCODES, checked against the enum rather than
# trusted. ssh.h says in a comment that renumbering the enum "would silently
# change what test/sshbeeb.bas and PTERM are testing" - this is what makes
# that a build failure instead of a comment. The opcode numbers go the same
# way: A%=12 is a fingerprint request and st%=12 is a password prompt, which
# are one keystroke apart in the source and unrelated in meaning.
cat > "$here/build/enumck.c" <<'CEOF'
#include <stdio.h>
#include "ssh.h"
int main(void) {
    printf("%d %d %d %d %d\n", SSH_ST_OPEN, SSH_ST_ERROR, SSH_ST_CLOSED,
           SSH_ST_NEEDPASS, SSH_ST_NEEDHOST);
    return 0;
}
CEOF
${HOSTCC:-cc} -I"$here/src/ssh" -o "$here/build/enumck" "$here/build/enumck.c"
set -- $("$here/build/enumck")
pt="$here/src/pterm.bas"
for pair in "$1:st%=9 OR" "$2:OR st%=$2" "$4:IF st%=$4 THEN PROCaskpass" \
            "$5:IF st%=$5 THEN PROCaskhost"; do
    num=${pair%%:*}; want=${pair#*:}
    grep -q -- "$want" "$pt" || {
        echo "sshbuild: the enum says $num but $pt has no \"$want\"" >&2
        echo "sshbuild:   the state numbers moved; PTERM is testing the wrong ones" >&2
        exit 1; }
done
echo "sshbuild: state numbers agree with $pt  (OPEN=$1 ERROR=$2 CLOSED=$3 NEEDPASS=$4 NEEDHOST=$5)"

# The blob is BINARY and must not go through mirror.sh, which does
# tr '\n' '\r' on everything it writes (specification.md 9.0).
# MAKE THE DIRECTORY, DO NOT SKIP. This used to be a plain -d test, so on a
# fresh clone - where share/Pi-TERM does not exist yet - the blob was
# silently not copied and the build reported success. The Beeb then loaded
# a terminal with no SSH core and failed somewhere unrelated.
mkdir -p "$here/share/Pi-TERM"
if [ -d "$here/share/Pi-TERM" ]; then
    cp "$here/build/SSHBLOB" "$here/share/Pi-TERM/SSHBLOB"
    cmp -s "$here/build/SSHBLOB" "$here/share/Pi-TERM/SSHBLOB" ||
        { echo "sshbuild: share copy differs" >&2; exit 1; }
    echo "sshbuild: share/Pi-TERM/SSHBLOB written and byte-compared"
    echo "sshbuild:   tools/mirror.sh --dir Pi-TERM --tok test/sshbeeb.bas"
fi
