#!/bin/sh
# Run a BBC BASIC program on the emulated Master 128 and capture its output.
#
#   tools/beeb-test.sh test/nettest.bas [seconds]
#
# Three non-obvious things this handles, all learned the hard way:
#
#  1. BBC text files need CR (&0D) line endings, not LF. *EXEC on an
#     LF-terminated file reads the whole thing as one unterminated line
#     and silently does nothing.
#  2. b-em never fflush()ed the printer file and died on SIGTERM, losing any
#     output under the 4096-byte stdio buffer. tools/b-em is a LOCAL BUILD
#     patched to fflush after every character (src/uservia.c). If you rebuild
#     b-em from clean sources you must re-apply that patch or captures will
#     be truncated to 4096-byte boundaries.
#  3. VDFS must be enabled with vdfsenable=true in ~/.config/b-em/b-em.cfg
#     -- -vroot alone only sets the root, it does not turn VDFS on.
#  4. A co-processor is selected with BEEB_TUBE=n, not with b-em's -tx
#     flag, which is accepted and ignored. See below.
#
# Filenames in emu/vdfs must be <= 7 characters or DFS reports "Bad name".

set -e
here=$(cd "$(dirname "$0")/.." && pwd)
prog=${1:?usage: beeb-test.sh <file.bas> [seconds] [extra b-em args...]}
secs=${2:-150}
shift 2 2>/dev/null || shift $#
# Anything further goes straight to b-em.
extra="$@"
out=$here/emu/output.txt

mkdir -p "$here/emu/vdfs"
rm -f "$out"

# Type the program in with printer echo OFF - echoing every character of the
# listing through b-em's parallel printer emulation is ruinously slow and was
# making long programs time out before they finished loading. Enable the
# printer only for the RUN output we actually want to capture.
# Tokenise on this side and CHAIN, rather than typing the program in.
# *EXEC feeds a text file through the input stream one character at a time
# and BASIC tokenises each line as it arrives; for the 60K engine that is
# three to five minutes of every run. CHAIN of the same program is FIVE
# SECONDS. tools/bastok.py's output is verified byte-identical to the
# machine's own SAVE (tools/bastok-diff.py), so this is the same program.
#
# BEEB_EXEC=1 forces the old path - for a source bastok cannot handle, or
# to check that a difference is not the tokeniser's doing.
paste_cmd=$(printf '*VDFS\r*EXEC AUTO\r')
if [ -z "$BEEB_EXEC" ] && python3 "$here/tools/bastok.py" --inf "$prog" \
        "$here/emu/vdfs/T" >/dev/null 2>&1; then
    paste_cmd=$(printf '*VDFS\rVDU2\rCHAIN "T"\rPRINT "###DONE###"\rVDU3\r')
else
    rm -f "$here/emu/vdfs/T" "$here/emu/vdfs/T.inf"
    { cat "$prog"
      echo 'VDU2'
      echo 'RUN'
      echo 'PRINT "###DONE###"'
      echo 'VDU3'
    } | tr '\n' '\r' > "$here/emu/vdfs/AUTO"
fi

# b-em never exits by itself, so $secs is only an upper bound. The program
# prints ###DONE### when finished and we kill the emulator as soon as that
# appears - otherwise every run burned the full timeout doing nothing.
# -sp9 runs the emulation at 500%; speed 4 (the default) is real BBC speed.
export XDG_DATA_HOME="$here/tools/b-em/share"

# BEEB_TUBE=n runs the program on a co-processor instead of the host.
# Measured 2026-08-20, PAGE to HIMEM:
#
#   host              &0F00-&7C00     27.6K   BASIC IV
#   BEEB_TUBE=0       &0800-&8000     30.0K   BASIC IV, 6502 Internal
#   BEEB_TUBE=6       &0800-&8000     30.0K   BASIC IV, 6502 External
#   BEEB_TUBE=4       &0800-&B800     46.0K   BASIC IV, 65816
#   BEEB_TUBE=12      &8F00-&4000000  65500K  BASIC V on ARM  <-- use this
#
# BEEB_TUBE=12 is the Sprow ARM, which boots ARM Tube OS 0.45 straight into
# BBC BASIC V - the same lineage as PiTubeDirect's copro 15, which is what
# FBVDU actually ships on. It is the right answer for anything ARM: the real
# language, 64MB, and no need to strip the comments out to make it fit.
# What it does NOT have is the framebuffer: OS_ReadVduVariables is "SWI &31
# not known", so run with sim%=TRUE or glass%=FALSE.
#
# BEEB_TUBE=1 is the Acorn ARM Evaluation System's ARM, and is NOT a BASIC.
# It boots Supervisor 1.00 / Executive 1.00, a monitor with Go, Memory and
# BreakSet, and ARM BASIC was a separate thing loaded from the disc that
# came with it. -m14 selects the matching whole model. Neither gives a
# language to type into.
#
# It has to go through a generated config file. b-em documents a -tx flag
# and accepts it without complaint, but it has no effect - a run with -t3
# is a run on the host, silently, and -t3 is an 80186 in any case. That
# cost most of an afternoon: a test that had been "running on a 65C102 with
# 64K" since the start had always been running on the host with 27K, and
# the first thing to outgrow it looked like a leak in the program.
#
# The base config is emu/bem-base.cfg, a snapshot in the repository, and
# NOT ~/.config/b-em/b-em.cfg. b-em REWRITES its own config on exit, so
# the live one carries whatever the last run happened to leave there. A
# "tube=1" edit written as a substitution for "tube=-1" therefore matched
# nothing and the run silently used the previous tube - an 80186, which
# tries to boot DOS off a disc that is not there and fills the log with
# wd1770 "not found". The fault looked like a disc problem and was a
# config problem.
if [ -n "$BEEB_TUBE" ]; then
    cfg=$here/emu/tube.cfg
    # ONLY line 2. The per-model tube= fields further down take a NAME
    # ("ARM", "6502 Internal"), not an index, and setting them to a number
    # makes b-em warn "invalid tube name" and quietly use no tube at all.
    sed "2s/^tube=.*/tube=$BEEB_TUBE/" "$here/emu/bem-base.cfg" > "$cfg"
    # BEEB_OS swaps the Master's OS image - mos320p is stock 3.20 with the
    # ONE byte of the Y2K century patch (&9881 in the Terminal bank, &19 to
    # &20), so the two can be compared without burning anything. See
    # specification.md 5.5b-duodecies.
    if [ -n "$BEEB_OS" ]; then
        sed -i "/^\[model_10\]/,/^\[/ s/^os=.*/os=$BEEB_OS/" "$cfg"
        grep -q "^os=$BEEB_OS" "$cfg" || { echo "beeb-test: could not set os=$BEEB_OS" >&2; exit 1; }
    fi
    set -- -cfg "$cfg" "$@"
    extra="$@"
    [ "$(sed -n 2p "$cfg")" = "tube=$BEEB_TUBE" ] || { echo "beeb-test: could not set tube=$BEEB_TUBE" >&2; exit 1; }
fi

# shellcheck disable=SC2086
"$here/tools/b-em/bin/b-em" -m10 -vroot "$here/emu/vdfs" -sp9 $extra \
    -printfile "$out" \
    -paste "$paste_cmd" >/dev/null 2>&1 &
bem=$!

waited=0
while [ "$waited" -lt "$((secs * 4))" ]; do
    sleep 0.25
    waited=$((waited + 1))
    grep -q '###DONE###' "$out" 2>/dev/null && break
    kill -0 "$bem" 2>/dev/null || break
done
kill "$bem" 2>/dev/null || true
wait "$bem" 2>/dev/null || true

if [ ! -f "$out" ]; then
    echo "No output captured. Program may have errored before printing 4KB." >&2
    exit 1
fi

echo "=== RUN output ==="
# >RUN on the *EXEC path, >CHAIN "T" on the tokenised one.
sed -n '/^>RUN/,$p;/^>CHAIN/,$p' "$out" | grep -v '^[[:space:]]*$'
