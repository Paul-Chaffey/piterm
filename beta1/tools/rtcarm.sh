#!/bin/sh
# Stamp the current time into test/fbrtcw.bas and mirror both slow-bus
# programs to the share.
#
#   tools/rtcarm.sh
#
# FBRTC reads the 146818's own registers, FBRTCW writes the clock and the
# control registers. Neither goes through the MOS - it cannot see
# registers 0-13 at all. See specification.md 5.5b-nonies.
#
# Day of week is 1=Sunday, which is the 146818's convention and one more
# than date's %w.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
src=$here/test/fbrtcw.bas

set -- $(LC_ALL=C date "+%y %m %d %w %H %M %S")
dw=$(( $4 + 1 ))
# Leading zeros are harmless in BASIC and $((10#n)) is a bashism, so
# the fields go in as date prints them.
line="  350 yr%=$1:mo%=$2:dm%=$3:dw%=$dw:hr%=$5:mi%=$6:se%=$7"
sed -i "s/^ *350 yr%=.*$/$line/" "$src"
grep -n "^ *350 " "$src"

"$here/tools/baslint.py" --basic4 "$here/test/fbrtc.bas" "$src"
"$here/tools/mirror.sh" test/fbrtc.bas
"$here/tools/mirror.sh" test/fbrtcw.bas
echo
echo "Co-processor OFF. Read first, and KEEP the result:"
echo "    NEW ; *EXEC FBRTC  ; RUN      -> RESRTC"
echo "then, only if you want to write:"
echo "    NEW ; *EXEC FBRTCW ; RUN      -> RESRTCW"
