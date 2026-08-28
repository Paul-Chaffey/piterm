#!/bin/sh
# Is what the Beeb will load older than what is in git?
#
#   tools/mirrorck.sh          check the Pi-TERM share against src/ and test/
#
# WHY THIS EXISTS. On 2026-08-28 a glyph fix was committed, verified offline
# and then reported as "nothing changed" from the machine - because nobody had
# run tools/mirror.sh. The Beeb had loaded the previous build, and a stale
# build fails in the most expensive way there is: it looks exactly like a
# change that did not work, so the next hour goes on the code that was right.
#
# The two tokenised CHAIN builds are checked against the WHOLE engine as well
# as their own driver, because fbbuild.sh merges the two and only the driver's
# name survives into the share.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
share=$here/share/Pi-TERM
stale=0

check() {           # check <share file> <source>...
    dst=$share/$1; shift
    if [ ! -f "$dst" ]; then
        echo "mirrorck: $(basename "$dst") is not on the share at all" >&2
        stale=1
        return
    fi
    for src in "$@"; do
        if [ "$src" -nt "$dst" ]; then
            echo "mirrorck: $(basename "$dst") is older than $(basename "$src")" >&2
            stale=1
        fi
    done
}

eng=$here/src/fbvdu.bas
check FBVDU    "$eng"
check PTERM    "$here/src/pterm.bas"
check FBVT     "$here/test/fbvt.bas"
check PTERMRUN "$eng" "$here/src/pterm.bas"
check FBRUN    "$eng" "$here/test/fbvt.bas"
check SSH      "$eng" "$here/src/pterm.bas"

if [ "$stale" = 1 ]; then
    echo >&2
    echo "The Beeb would load an old build. See specification.md 9 for the" >&2
    echo "mirror sequence, or run:" >&2
    echo >&2
    echo "  tools/mirror.sh --dir Pi-TERM src/fbvdu.bas src/pterm.bas test/fbvt.bas" >&2
    echo "  tools/fbbuild.sh src/pterm.bas > /tmp/PTERMRUN.bas" >&2
    echo "  tools/fbbuild.sh test/fbvt.bas > /tmp/FBRUN.bas" >&2
    echo "  tools/mirror.sh --dir Pi-TERM --tok /tmp/PTERMRUN.bas /tmp/FBRUN.bas" >&2
    echo "  tools/sshterm.sh                 (the quiet build, SSH)" >&2
    exit 1
fi
echo "mirrorck: the share is current with src/ and test/"
