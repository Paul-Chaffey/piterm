#!/usr/bin/env python3
"""Generate the double box-drawing set, U+2550-256C, as FBVDU DATA.

  tools/mkdbox.py            print the DATA lines (and self-test first)
  tools/mkdbox.py --show     draw all 29, and a box built out of them

WHY THIS IS A TOOL AND NOT TWENTY LINES OF BASIC. Braille and the block
elements are generated on the Beeb because their rule is one line of
arithmetic. This rule is not: a stroke is sometimes continuous, sometimes
stopped at the near perpendicular stroke, sometimes capping the whole
perpendicular footprint, and sometimes broken in the middle. That is four
cases with three conditions between them, and a mistake in it would show up
as a wrong shape on a monitor in another room. So the RULE lives here, where
--test runs against it, and the machine reads bytes it cannot get wrong.

THE GEOMETRY IS THIS FONT'S, NOT A GUESS. src/fbvdu.bas's own DEC DATA puts a
single horizontal on row 3 and a single vertical on columns 3-4, so the
doubles straddle them: rows 2 and 4, columns 1-2 and 5-6. Straddling is what
makes the two sets align - a double line has the single line's position as
its gap.

THE BREAK RULE WAS MEASURED off DejaVu Sans Mono at 24x24, because reasoning
about it gives the wrong answer. A single line crossing a double passes
straight through (as in U+256B); two doubles crossing do not, and leave the
open centre of U+256C. U+2560 has its left stroke whole and only its right
one interrupted; U+2566 has its top line whole and only its lower one broken.
All four fall out of: a stroke breaks iff a perpendicular arm exists on that
stroke's own inner side, and both structures are double.
"""
import sys

# arms as (up, down, left, right): 0 none, 1 single, 2 double
ARMS = {
 0x2550:(0,0,2,2), 0x2551:(2,2,0,0), 0x2552:(0,1,0,2), 0x2553:(0,2,0,1),
 0x2554:(0,2,0,2), 0x2555:(0,1,2,0), 0x2556:(0,2,1,0), 0x2557:(0,2,2,0),
 0x2558:(1,0,0,2), 0x2559:(2,0,0,1), 0x255A:(2,0,0,2), 0x255B:(1,0,2,0),
 0x255C:(2,0,1,0), 0x255D:(2,0,2,0), 0x255E:(1,1,0,2), 0x255F:(2,2,0,1),
 0x2560:(2,2,0,2), 0x2561:(1,1,2,0), 0x2562:(2,2,1,0), 0x2563:(2,2,2,0),
 0x2564:(0,1,2,2), 0x2565:(0,2,1,1), 0x2566:(0,2,2,2), 0x2567:(1,0,2,2),
 0x2568:(2,0,1,1), 0x2569:(2,0,2,2), 0x256A:(1,1,2,2), 0x256B:(2,2,1,1),
 0x256C:(2,2,2,2),
}
HROWS = {0: [], 1: [3],      2: [2, 4]}
VPAIR = {0: [], 1: [(3, 4)], 2: [(1, 2), (5, 6)]}


def glyph(u):
    up, dn, lf, rt = ARMS[u]
    rows, cols = HROWS[lf or rt], VPAIR[up or dn]
    both = (lf or rt) == 2 and (up or dn) == 2
    px = [[0] * 8 for _ in range(8)]

    def span(side, lo_arm, hi_arm, brk, foot, through):
        """One half-stroke's extent. side 0 runs in from the low edge."""
        if not foot:
            return 0, 7
        near = foot[0] if side == 0 else foot[-1]
        stop = near[1] if side == 0 else near[0]
        if not brk:
            if lo_arm and hi_arm:                 # both sides: one crossing line
                return 0, 7
            if not through:                       # it ends here, so cap it
                stop = foot[-1][1] if side == 0 else foot[0][0]
        return (0, stop) if side == 0 else (stop, 7)

    for i, r in enumerate(rows):
        brk = both and bool(up if i == 0 else dn)
        for side, arm in ((0, lf), (1, rt)):
            if arm:
                a, b = span(side, lf, rt, brk, cols, bool(up and dn))
                for x in range(a, b + 1):
                    px[r][x] = 1

    for j, (c0, c1) in enumerate(cols):
        brk = both and bool(lf if j == 0 else rt)
        for side, arm in ((0, up), (1, dn)):
            if arm:
                a, b = span(side, up, dn, brk, [(r, r) for r in rows], bool(lf and rt))
                for y in range(a, b + 1):
                    px[y][c0] = px[y][c1] = 1

    return [sum(1 << (7 - x) for x in range(8) if px[y][x]) for y in range(8)]


def selftest():
    """Every edge must carry exactly what its arm declares. That is the whole
    proof: if it holds, any two glyphs with matching arms join, and no pair
    needs checking separately."""
    vcols = {0: [], 1: [3, 4], 2: [1, 2, 5, 6]}
    bad = []
    for u, (up, dn, lf, rt) in sorted(ARMS.items()):
        g = glyph(u)
        col = lambda x: {y for y in range(8) if g[y] & (1 << (7 - x))}
        row = lambda y: {x for x in range(8) if g[y] & (1 << (7 - x))}
        for what, got, want in (("left", col(0), set(HROWS[lf])),
                                ("right", col(7), set(HROWS[rt])),
                                ("top", row(0), set(vcols[up])),
                                ("bottom", row(7), set(vcols[dn]))):
            if got != want:
                bad.append(f"U+{u:04X} {chr(u)} {what} edge is {sorted(got)}, "
                           f"arms say {sorted(want)}")
    return bad


def main():
    bad = selftest()
    if bad:
        for b in bad:
            print("mkdbox: " + b, file=sys.stderr)
        sys.exit(1)
    ks = sorted(ARMS)
    if "--show" in sys.argv:
        for i in range(0, len(ks), 6):
            grp = ks[i:i + 6]
            print("  " + "  ".join(f"{chr(u)} {u:04X} " for u in grp))
            for y in range(8):
                print("  " + "  ".join("".join("#" if glyph(u)[y] & (1 << (7 - x)) else "."
                                               for x in range(8)) for u in grp))
            print()
        return
    print(f"REM {len(ks)} glyphs, U+{ks[0]:04X} to U+{ks[-1]:04X}, "
          f"in codepoint order - tools/mkdbox.py")
    for i in range(0, len(ks), 4):
        print("DATA " + ",".join(",".join(str(b) for b in glyph(u)) for u in ks[i:i + 4]))


if __name__ == "__main__":
    main()
