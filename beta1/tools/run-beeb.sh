#!/bin/sh
# Launch b-em as a BBC Master 128 for this project.
#
# b-em looks for its data (roms, fonts, discs) under XDG_DATA_HOME/b-em,
# not under its install prefix, so point that at our install tree.
#
# -m10   BBC Master 128        (-m15 = Master 128 w/MOS 3.5)
# -vroot mounts emu/vdfs as a filing system, so files can be moved
#        between host and emulated Beeb without disc images.
#
# Extra arguments are passed straight through, e.g.
#   tools/run-beeb.sh -t3          (with a 65C102 tube co-processor)
#   tools/run-beeb.sh -debug       (start the debugger)

set -e
here=$(cd "$(dirname "$0")/.." && pwd)

export XDG_DATA_HOME="$here/tools/b-em/share"

mkdir -p "$here/emu/vdfs"

exec "$here/tools/b-em/bin/b-em" \
    -m10 \
    -vroot "$here/emu/vdfs" \
    "$@"
