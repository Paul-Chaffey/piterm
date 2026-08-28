#!/bin/bash
# Build SPIKE1 - the cross-compiled ARM blob for copro 15.
#
#   tools/armbuild.sh              build spike1, write build/ARMBLOB
#   tools/armbuild.sh --share      also put it on the share, ready to load
#   tools/armbuild.sh rng --share  build the entropy spike instead
#
# One script per blob would duplicate four checks that are worth having on
# every one of them, so the target is an argument and the naming lives in the
# case below. Every blob links at the same address and only one is loaded at
# a time.
#
# WHAT THIS REFUSES TO DO, and why it is a script rather than three commands:
#
#  1. It will not hand over a blob whose entry point is not at offset 0.
#     The blob is CALLed at its base address, and gcc is under no obligation
#     to lay _start out first. Getting this wrong executes whatever function
#     did land there, which on a co-processor is a crash with no message.
#
#  2. It will not let the blob reach the share through mirror.sh. mirror.sh
#     does tr '\n' '\r' on everything it writes (specification.md 9.0), which
#     silently corrupts a binary. TUBEDATA is generated straight into the
#     share for exactly this reason and so is this.
#
#  3. It writes no .inf. LANManFS ignores them (tools/ssd-extract.py) so one
#     would buy nothing, and gamesmenu.sh records what it costs: the name
#     goes over eight characters, LANManFS truncates, and the .inf arrives as
#     a second file colliding with the first.
#
#  4. It patches the length, the byte sum and a build id into
#     test/armspike.bas, rather than leaving three constants to be copied by
#     hand. "Was that the latest code?" is a question this project has
#     already paid for once.
#
# NAMES. The blob is ARMBLOB and the BASIC is ARMSPIKE. They must differ:
# mirror.sh uppercases and truncates to 8 characters, so armspike.bas would
# also land on ARMSPIKE and whichever ran last would win (specification.md
# 9.0). ARMBLOB is 7 characters and collides with nothing.

set -eu

# Must match src/spike1.c and test/armspike.bas. Changing it means changing
# all three, and armspike.bas prints what it used so a mismatch is visible.
BASE=0x04100000

here="$(cd "$(dirname "$0")/.." && pwd)"
share="$here/share/Pi-TERM"
toshare=0
stem=""

for a in "$@"; do
    case "$a" in
        --share) toshare=1 ;;
        -*)      echo "armbuild: unknown option $a" >&2; exit 1 ;;
        *)       stem="$a" ;;
    esac
done
[ -n "$stem" ] || stem=spike1

case "$stem" in
    spike1) name=ARMBLOB; bas="$here/test/armspike.bas" ;;
    rng)    name=RNGBLOB; bas="$here/test/rngspike.bas" ;;
    *)      echo "armbuild: no such blob: $stem" >&2; exit 1 ;;
esac
src="$here/src/$stem.c"
out="$here/build/$name"
[ -f "$src" ] || { echo "armbuild: $src not found" >&2; exit 1; }

die() { echo "armbuild: $*" >&2; exit 1; }

command -v arm-none-eabi-gcc >/dev/null || die "no arm-none-eabi-gcc (apt install gcc-arm-none-eabi)"

mkdir -p "$here/build"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# -marm because the co-processor is entered in ARM state and a Thumb blob
# would be executed as ARM. -ffreestanding -nostdlib because there is no libc
# on the parasite; every service comes from a SWI.
arm-none-eabi-gcc -c -O2 -marm -march=armv7-a \
    -ffreestanding -nostdlib -fno-builtin -Wall -Wextra \
    -o "$tmp/spike1.o" "$src"

arm-none-eabi-ld -Ttext="$BASE" -e _start -nostdlib \
    -o "$tmp/spike1.elf" "$tmp/spike1.o"

# Check 1: the entry point is the base address, so offset 0 of the binary is
# where execution starts.
entry=$(arm-none-eabi-readelf -h "$tmp/spike1.elf" | sed -n 's/.*Entry point address: *//p')
start=$(arm-none-eabi-nm "$tmp/spike1.elf" | sed -n 's/^0*\([0-9a-f]*\) T _start$/0x\1/p')
[ "$((entry))" -eq "$((BASE))" ] \
    || die "entry $entry is not $BASE - the link address did not take"
[ "$((start))" -eq "$((BASE))" ] \
    || die "_start is at $start, not $BASE - it is not the first thing in the blob"

arm-none-eabi-objcopy -O binary "$tmp/spike1.elf" "$out"

len=$(stat -c%s "$out")
[ "$len" -gt 0 ] || die "empty blob"

# Check 2: no Thumb. A BX to an odd address anywhere means gcc emitted
# interworking and the entry could land in Thumb state.
if arm-none-eabi-readelf -A "$tmp/spike1.elf" | grep -qi "THUMB.*yes"; then
    die "blob contains Thumb code - rebuild with -marm"
fi

# The byte sum is what armspike.bas checks before it dares CALL anything.
# The Tube has dropped one byte in 874,000 before now (specification.md
# 5.5g) and a blob with a byte missing is not a program, it is a crash.
sum=$(od -An -tu1 -v "$out" | awk '{for (i = 1; i <= NF; i++) s += $i} END {print s + 0}')
id=$(printf '%04X' $((sum & 0xFFFF)))

# Patch the three constants into the BASIC. The markers are exact and the
# sed fails loudly if a line has been renamed.
patch() {
    local marker="$1" value="$2"
    grep -q "REM BUILDSTAMP-$marker\$" "$bas" \
        || die "no line marked REM BUILDSTAMP-$marker in $bas"
    sed -i "s/^\( *[0-9]* *\)[a-z]*%=[-0-9]*\(:REM BUILDSTAMP-$marker\)\$/\1$value\2/" "$bas"
}
if [ -f "$bas" ]; then
    patch LEN "len%=$len"
    patch SUM "sum%=$sum"
    grep -q "REM BUILDSTAMP-ID\$" "$bas" \
        && sed -i "s/^\( *[0-9]* *\)bid\$=\"[^\"]*\"\(:REM BUILDSTAMP-ID\)\$/\1bid\$=\"$id\"\2/" "$bas"
    echo "armbuild: patched $bas  len%=$len sum%=$sum bid\$=\"$id\""
else
    echo "armbuild: WARNING - $bas not found, constants not patched" >&2
fi

echo "armbuild: $out  $len bytes  sum $sum  id $id  base $BASE"

if [ "$toshare" -eq 1 ]; then
    [ -d "$share" ] || die "$share does not exist - is the share built?"
    # cp, NOT mirror.sh. See the header.
    cp "$out" "$share/$name"
    cmp -s "$out" "$share/$name" \
        || die "copy to the share does not compare equal"
    echo "armbuild: $share/$name written and byte-compared"
    # --tok, because armspike.bas's own header says CHAIN "ARMSPIKE" and a
    # text-mirrored file answers "Bad program" to CHAIN. Same trap TUBECRC
    # walked into on 2026-08-23 (specification.md 9.0).
    echo "armbuild: now mirror the BASIC:"
    echo "armbuild:   tools/mirror.sh --dir Pi-TERM --tok ${bas#$here/}"
fi
