#!/bin/sh
# Build the games menu into the share's GAMES directory.
#
#   tools/gamesmenu.sh
#
# CHAIN needs a TOKENISED file, and mirror.sh only writes the share root
# and only as text, so this calls bastok.py directly at the subdirectory.
#
# STRIPPED before tokenising. The menu relocates to &6500 and MODE 7 puts
# HIMEM at &7C00, so 5888 bytes have to hold the program AND its variables
# AND the BASIC stack - and the commented build was 4740 of them. The
# comments carry the reasoning and stay in src/start.bas; the machine gets
# the program. See tools/basstrip.py.
#
# No .inf is written. One must never land on the share: the name goes over
# eight characters, LANManFS truncates, and the .inf arrives as a second
# file sitting on top of the program - see tools/bastok.py.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
out=$here/share/GAMES/START

"$here/tools/baslint.py" --basic4 "$here/src/start.bas"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
"$here/tools/basstrip.py" "$here/src/start.bas" > "$tmp"
"$here/tools/bastok.py" "$tmp" "$out"

size=$(stat -c %s "$out")
free=$(( 5888 - size ))
echo "  $size bytes at &6500, $free free below MODE 7's HIMEM of &7C00"
if [ "$free" -lt 1500 ]; then
    echo "  WARNING: under 1500 bytes left for variables and the stack."
    echo "  Lower max% in src/start.bas, or trim the program."
fi

echo
echo "On the machine:"
echo "    *DIR GAMES"
echo "    CHAIN \"START\""
echo
echo "Host only - Tube off. The menu says so if a co-processor is active."
