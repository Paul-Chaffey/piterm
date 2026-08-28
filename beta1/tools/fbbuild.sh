#!/bin/sh
# Combine the FBVDU engine with a driver into one listing.
#
#   tools/fbbuild.sh [driver.bas] > combined.bas
#
# src/fbvdu.bas holds lines 1000-9990 and defines procedures only; a
# driver holds 10-990 (configuration and the entry point) and 10000+
# (its own procedures). On the Beeb they are loaded separately -
# *EXEC FBVDU then *EXEC FBVT - and BASIC files them by line number.
#
# The emulator harness and baslint.py each want a single file, so this
# merges them in line-number order, which is the same program.
#
# THE BANDS ARE CHECKED HERE. An engine line at 10000 or above silently
# replaces a driver line of the same number, and vice versa, and the result
# is a program that loads and then behaves as neither. The engine band ran
# out on 2026-08-28 and was reflowed at step 2 the same day (docs/glyphs.md),
# which is why the free count is printed. The step is measured from the file,
# not assumed, so a later reflow does not quietly make this line a lie.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
drv=${1:-$here/test/fbvt.bas}

awk 'BEGIN{bad=0}
     {n=$1+0; if(n==0) next}
     FILENAME==eng && (n<1000 || n>9990) {
        printf "fbbuild: %s:%d is outside the engine band 1000-9990\n", FILENAME, n > "/dev/stderr"; bad=1 }
     FILENAME!=eng && n>=1000 && n<=9990 {
        printf "fbbuild: %s:%d is inside the engine band 1000-9990\n", FILENAME, n > "/dev/stderr"; bad=1 }
     FILENAME==eng {if(prev>0 && n-prev>0) gap[n-prev]++
                    prev=n; if(n>hi) hi=n}
     END{ if(bad) exit 1
          # THE MODAL GAP, not the smallest. One line squeezed into a gap
          # would otherwise make this claim twice the headroom that the
          # convention in the file itself actually allows.
          step=0; best=0
          for(g in gap) if(gap[g]>best || (gap[g]==best && g<step)) {best=gap[g]; step=g}
          if(step<1) step=1
          printf "fbbuild: engine ends at %d, %d line slots left at step %d\n", \
                 hi, int((9990-hi)/step), step > "/dev/stderr" }' \
    eng="$here/src/fbvdu.bas" "$here/src/fbvdu.bas" "$drv"

cat "$here/src/fbvdu.bas" "$drv" | sort -n -k1,1
