#!/bin/sh
# Stamp the current time into test/fbbatt.bas and mirror both halves of
# the battery-backup test to the share.
#
#   tools/battarm.sh
#
# The time FBBATT writes has to be a literal in the source - the Beeb has
# no clock to ask, that being the point - so it goes stale the moment this
# file is written. Run this immediately before typing *EXEC FBBATT on the
# machine and the clock it sets is right to the minute, which matters
# twice: the machine is left with a correct clock, and phase 2's advance
# can be compared against real elapsed time rather than a guess.
#
# See test/fbbatt.bas, test/fbbatt2.bas and tools/battcheck.py.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
src=$here/test/fbbatt.bas

now=$(LC_ALL=C date "+%a,%d %b %Y.%H:%M:%S")
sed -i "s/^\( *[0-9]* t\$=\)\".*\"$/\1\"$now\"/" "$src"
grep -n 't\$="' "$src" | head -1

# Phase 2 needs the same year, and only TWO digits of it: this MOS prints
# every year as 19xx whatever the chip holds (spec 5.5b-decies).
yy=$(LC_ALL=C date "+%y")
sed -i "s/^\( *[0-9]* yy\$=\)\"..\"/\1\"$yy\"/" "$here/test/fbbatt2.bas"
grep -n 'yy\$="' "$here/test/fbbatt2.bas" | head -1

"$here/tools/baslint.py" --basic4 "$src" "$here/test/fbbatt2.bas"
"$here/tools/mirror.sh" test/fbbatt.bas
"$here/tools/mirror.sh" test/fbbatt2.bas
echo
echo "On the machine, co-processor off:"
echo "    NEW"
echo "    *EXEC FBBATT"
echo "    RUN"
echo "then power OFF AT THE MAINS for five minutes or more, power on:"
echo "    NEW"
echo "    *EXEC FBBATT2"
echo "    RUN"
echo "then here:  tools/battcheck.py"
