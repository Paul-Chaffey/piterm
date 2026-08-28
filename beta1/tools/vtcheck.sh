#!/bin/sh
# Replay every capture through the engine and diff it against pyte.
#
#   tools/vtcheck.sh              the whole corpus
#   tools/vtcheck.sh FEAT         just one
#
# Phase 3's gate. Each capture is replayed under b-em on the ARM
# co-processor by test/fbreplay.bas, which dumps what the cell model
# ended up holding, and tools/vtdiff.py puts the same bytes through pyte
# at the same geometry and compares every cell - the character and the
# attributes.
#
# captures/ALT is skipped on purpose: it exercises the alternate screen,
# pyte has no alternate screen at all, and the engine is the more correct
# of the two there. test/fbparse.bas checks it instead.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
build=${TMPDIR:-/tmp}/vtcheck.bas
cat "$here/src/fbvdu.bas" "$here/test/fbreplay.bas" | sort -n -k1,1 > "$build"

if [ $# -gt 0 ]; then set -- "$@"; else set -- FEAT TOP LS; fi

fail=0
for name in "$@"; do
    cap=$here/captures/$name
    [ -f "$cap" ] || { echo "$name: no such capture" >&2; fail=1; continue; }
    cp "$cap" "$here/emu/vdfs/CAP"
    rm -f "$here/emu/vdfs/GRID"
    BEEB_TUBE=12 "$here/tools/beeb-test.sh" "$build" 400 >/dev/null 2>&1
    [ -f "$here/emu/vdfs/GRID" ] || { echo "$name: the replay produced no grid" >&2; fail=1; continue; }
    cp "$here/emu/vdfs/GRID" "$here/captures/$name.grid"
    echo "=== $name"
    "$here/tools/vtdiff.py" "$cap" "$here/captures/$name.grid" || fail=1
done
exit $fail
