#!/bin/sh
# Build SSH: PTERM with every instrument turned off, tokenised for CHAIN.
#
#   tools/sshterm.sh            writes share/Pi-TERM/SSH
#
# WHY A SEPARATE BUILD RATHER THAN A FLAG. Every measurement this project
# relies on came out of PTERM's own instruments, and they should stay on by
# default in the thing that gets developed. What they cost is not nothing:
# about 131K of buffers DIMmed at startup, a save of up to 88K at exit, and a
# TIME comparison in the innermost loop. A terminal somebody just wants to USE
# should carry none of it.
#
# THE SWITCHES ARE PATCHED, NOT DUPLICATED. src/pterm.bas stays the single
# source; this rewrites five assignments in a copy and fails if any of them
# does not take, which is the same rule tools/sshbuild.sh applies to its
# build stamps. A silently missed patch would produce a build that looks
# right and still writes 88K to the share at exit.
#
# WHAT STAYS ON, deliberately:
#   err$   RESERR is written only when the program has already failed, and
#          costs nothing until then. Turning it off trades a diagnosable
#          crash for a blank screen.
#   ask%   the destination prompt is input, not instrumentation.
#   glass% that is the renderer itself, not a debug aid.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$here/build/SSH.bas}
tmp=$here/build/pterm-quiet.bas
mkdir -p "$here/build"

cp "$here/src/pterm.bas" "$tmp"
patch_one() {   # patch_one <from> <to>
    grep -q -- "$1" "$tmp" || { echo "sshterm: not found: $1" >&2; exit 1; }
    sed -i "s|$1|$2|" "$tmp"
    grep -q -- "$2" "$tmp" || { echo "sshterm: patch did not take: $2" >&2; exit 1; }
    printf "  %-24s -> %s\n" "$1" "$2"
}
echo "sshterm: turning the instruments off"
patch_one 'dump$="RESGLAS"'   'dump$=""'
patch_one 'banner%=TRUE'      'banner%=FALSE'
patch_one 'rlog$="RXL"'       'rlog$=""'
patch_one 'gcheck%=TRUE'      'gcheck%=FALSE'
patch_one 'prof$="RESPROF":profcs%=50' 'prof$="":profcs%=0'

# THE ASSIGNMENTS, not the word. RES* filenames also appear in comments -
# "fastmv% is recorded in RESPROF's header" is a REM - and a check that
# grepped for the bare name would fail on prose while missing a real one that
# had been reworded. What is being asserted is that the variables the SAVEs
# read are empty, and that the guards around those SAVEs are therefore never
# reached.
for bad in 'dump$="RESGLAS"' 'rlog$="RXL"' 'prof$="RESPROF"' 'gcheck%=TRUE' \
           'banner%=TRUE' 'profcs%=50'; do
    ! grep -q -- "$bad" "$tmp" || { echo "sshterm: $bad survived the patch" >&2; exit 1; }
done
for want in 'dump$=""' 'rlog$=""' 'prof$=""' 'gcheck%=FALSE' 'banner%=FALSE' \
            'profcs%=0' 'err$="RESERR"'; do
    grep -q -- "$want" "$tmp" || { echo "sshterm: expected $want" >&2; exit 1; }
done

"$here/tools/fbbuild.sh" "$tmp" > "$out"
echo "sshterm: $(grep -c . "$out") lines merged into $out"
"$here/tools/mirror.sh" --dir Pi-TERM --tok "$out"

# CHECKED IN THE FILE THE MACHINE WILL LOAD, not in the source it came from.
# TRUE and FALSE are TOKENS - &B9 and &A3 - so "gcheck%=FALSE" never appears
# as text in a tokenised build, and a grep for it finds nothing whether the
# patch worked or not. That is exactly the shape of check that passes while
# being wrong.
python3 "$here/tools/quietck.py" "$here/share/Pi-TERM/SSH" "$here/tools/bastok-table.json"
echo "sshterm: CHAIN \"SSH\" on the Beeb"
