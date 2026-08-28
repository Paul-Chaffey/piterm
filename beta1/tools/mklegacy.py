#!/usr/bin/env python3
"""U+1FB3C-1FB8B - the legacy diagonals, triangles and eighth blocks - as DATA.

  tools/mklegacy.py           print the DATA lines
  tools/mklegacy.py --show    draw all 80

NO FONT ON THIS MACHINE HAS THEM. Symbols for Legacy Computing is recent
enough that DejaVu, FreeMono, Noto and even the Nerd Font off archbox all miss
the whole block, so there is nothing to rasterise from. What there IS, and it
turns out to be enough, is Unicode's own names: every one of these 80 says
exactly what it is, and the geometry falls straight out of the words.

  LOWER LEFT BLOCK DIAGONAL UPPER LEFT TO LOWER CENTRE

names a line between two points on the cell boundary and the corner whose side
of that line is filled. The ten point names divide the left and right edges
into thirds - which is the sextant grid this block is built around - so:

  UPPER/LOWER LEFT, UPPER/LOWER RIGHT   the four corners
  UPPER/LOWER CENTRE                    the middles of the top and bottom
  UPPER/LOWER MIDDLE LEFT and RIGHT     the side edges at 1/3 and 2/3

A line between two boundary points cuts the cell in two; fill the half holding
the named corner. That is the whole rule for 44 of them. The 8 triangular
blocks are the same idea with the apex at the centre, and the 28 eighths and
quarters are plain fills whose position and thickness the name states outright.

Rendered at 4x and thresholded at half coverage, because a diagonal quantised
straight to 8x8 loses its slope.
"""
import re, sys, unicodedata

SS = 4                                   # supersample factor
LO, HI = 0x1FB3C, 0x1FB8B

PT = {"UPPER LEFT": (0.0, 0.0), "UPPER CENTRE": (0.5, 0.0), "UPPER RIGHT": (1.0, 0.0),
      "LOWER LEFT": (0.0, 1.0), "LOWER CENTRE": (0.5, 1.0), "LOWER RIGHT": (1.0, 1.0),
      "UPPER MIDDLE LEFT": (0.0, 1/3), "LOWER MIDDLE LEFT": (0.0, 2/3),
      "UPPER MIDDLE RIGHT": (1.0, 1/3), "LOWER MIDDLE RIGHT": (1.0, 2/3)}
CORNER = {"UPPER LEFT": (0.0, 0.0), "UPPER RIGHT": (1.0, 0.0),
          "LOWER LEFT": (0.0, 1.0), "LOWER RIGHT": (1.0, 1.0)}
EIGHTH = {"ONE EIGHTH": 1, "ONE QUARTER": 2, "THREE EIGHTHS": 3, "HALF": 4,
          "FIVE EIGHTHS": 5, "THREE QUARTERS": 6, "SEVEN EIGHTHS": 7}


def side(px, py, a, b):
    return (b[0]-a[0]) * (py-a[1]) - (b[1]-a[1]) * (px-a[0])


def cover(u):
    """Return a function saying whether a point in the unit cell is inked."""
    n = unicodedata.name(chr(u))

    m = re.match(r"(UPPER LEFT|UPPER RIGHT|LOWER LEFT|LOWER RIGHT) BLOCK DIAGONAL "
                 r"(.+) TO (.+)$", n)
    if m:
        c, a, b = CORNER[m.group(1)], PT[m.group(2)], PT[m.group(3)]
        want = side(c[0], c[1], a, b)
        return lambda x, y: side(x, y, a, b) * want > 0

    m = re.match(r"(LEFT|RIGHT|UPPER|LOWER) TRIANGULAR (ONE QUARTER|THREE QUARTERS) BLOCK$", n)
    if m:
        d, q = m.group(1), m.group(2)
        # the quarter is the triangle from one edge to the centre; the three
        # quarters version is everything else
        tri = {"LEFT":  lambda x, y: x <= 0.5 and abs(y-0.5) >= x,
               "RIGHT": lambda x, y: x >= 0.5 and abs(y-0.5) >= 1-x,
               "UPPER": lambda x, y: y <= 0.5 and abs(x-0.5) <= 0.5-y,
               "LOWER": lambda x, y: y >= 0.5 and abs(x-0.5) <= y-0.5}[d]
        return tri if q == "ONE QUARTER" else (lambda x, y: not tri(x, y))

    m = re.match(r"(LEFT|UPPER|RIGHT|LOWER)( AND (LEFT|UPPER|RIGHT|LOWER))* "
                 r"TRIANGULAR THREE QUARTERS BLOCK$", n)
    if m:
        parts = set(n.split(" TRIANGULAR")[0].split(" AND "))
        tris = {"LEFT":  lambda x, y: x <= 0.5 and abs(y-0.5) >= x,
                "RIGHT": lambda x, y: x >= 0.5 and abs(y-0.5) >= 1-x,
                "UPPER": lambda x, y: y <= 0.5 and abs(x-0.5) <= 0.5-y,
                "LOWER": lambda x, y: y >= 0.5 and abs(x-0.5) <= y-0.5}
        return lambda x, y: not any(tris[p](x, y) for p in parts)

    m = re.match(r"VERTICAL ONE EIGHTH BLOCK-(\d)$", n)
    if m:
        k = int(m.group(1)) - 1
        return lambda x, y: k/8 <= x < (k+1)/8

    m = re.match(r"HORIZONTAL ONE EIGHTH BLOCK-(\d)$", n)
    if m:
        k = int(m.group(1)) - 1
        return lambda x, y: k/8 <= y < (k+1)/8

    m = re.match(r"(UPPER|LOWER|LEFT|RIGHT) (" + "|".join(EIGHTH) + r") BLOCK$", n)
    if m:
        d, f = m.group(1), EIGHTH[m.group(2)] / 8
        return {"UPPER": lambda x, y: y < f, "LOWER": lambda x, y: y >= 1-f,
                "LEFT":  lambda x, y: x < f, "RIGHT": lambda x, y: x >= 1-f}[d]

    m = re.match(r"(RIGHT|LEFT|UPPER|LOWER) AND (LOWER|UPPER|LEFT|RIGHT) "
                 r"ONE EIGHTH BLOCK$", n)
    if m:
        edge = {"RIGHT": lambda x, y: x >= 7/8, "LEFT":  lambda x, y: x < 1/8,
                "LOWER": lambda x, y: y >= 7/8, "UPPER": lambda x, y: y < 1/8}
        a, b = edge[m.group(1)], edge[m.group(2)]
        return lambda x, y: a(x, y) or b(x, y)

    # HORIZONTAL ONE EIGHTH BLOCK-1358: the rows named, counted from 1
    m = re.match(r"HORIZONTAL ONE EIGHTH BLOCK-(\d+)$", n)
    if m:
        want = {int(d) - 1 for d in m.group(1)}
        return lambda x, y: int(y * 8) in want

    raise SystemExit(f"mklegacy: no rule for U+{u:05X} {n}")


def glyph(u):
    f = cover(u)
    rows = []
    for gy in range(8):
        b = 0
        for gx in range(8):
            hits = sum(1 for sy in range(SS) for sx in range(SS)
                       if f((gx + (sx+0.5)/SS) / 8, (gy + (sy+0.5)/SS) / 8))
            if hits * 2 >= SS*SS:
                b |= 1 << (7-gx)
        rows.append(b)
    return rows


def main():
    ks = list(range(LO, HI+1))
    if "--show" in sys.argv:
        for i in range(0, len(ks), 8):
            grp = ks[i:i+8]
            print("  " + "  ".join(f"{u:05X}   " for u in grp))
            for y in range(8):
                print("  " + "  ".join("".join("#" if glyph(u)[y] & (1 << (7-x)) else "."
                      for x in range(8)) + "  " for u in grp))
            print()
        return
    print(f"REM {len(ks)} glyphs, U+{LO:05X} to U+{HI:05X} - tools/mklegacy.py")
    for i in range(0, len(ks), 4):
        print("DATA " + ",".join(",".join(str(b) for b in glyph(u)) for u in ks[i:i+4]))


if __name__ == "__main__":
    main()
