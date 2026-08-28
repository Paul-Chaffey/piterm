#!/usr/bin/env python3
"""Latin-1 for FBVDU: what can be composed, and the DATA for what cannot.

  tools/mklatin.py            print the DATA lines
  tools/mklatin.py --show     draw the whole block using results/RESFONT

MOST OF U+00A0-00FF IS NOT DRAWN HERE AT ALL. Fifty-five of the ninety-six are
a letter the harvested driver font already has, plus a mark: the machine
composes them at boot from its OWN font, so an accented letter matches the
unaccented one beside it exactly. Importing them from a desktop font would put
two different typefaces in the same word.

The composition is possible because of where this font sits in the cell,
measured from results/RESFONT rather than assumed: lowercase occupies rows
2-6, leaving rows 0 and 1 free for a two-row accent; capitals occupy rows 0-6,
so they drop one row and take a one-row accent; 'i' gives up its dot, which is
what the accent replaces; and row 7 is free on both, which is where a cedilla
goes. Nothing is scaled or redrawn.

The rest - the ligatures, the fractions, the currency and punctuation - have no
base to build on and are rasterised from DejaVu Sans Mono, except five that
come out wrong at this size and are drawn by hand: the combining marks
standing alone, and multiplication, whose diagonals a downscale turns to mush.
"""
import sys

# codepoint: (base character, accent) - 0 grave 1 acute 2 circumflex 3 tilde
# 4 diaeresis 5 ring 6 cedilla (below, no shift) 7 slash (overlay, no shift)
COMPOSE = {}
for cps, base, accs in (("ÀÁÂÃÄÅ", "A", [0,1,2,3,4,5]), ("Ç", "C", [6]),
                        ("ÈÉÊË", "E", [0,1,2,4]),       ("ÌÍÎÏ", "I", [0,1,2,4]),
                        ("Ñ", "N", [3]),                ("ÒÓÔÕÖ", "O", [0,1,2,3,4]),
                        ("Ø", "O", [7]),                ("ÙÚÛÜ", "U", [0,1,2,4]),
                        ("Ý", "Y", [1]),
                        ("àáâãäå", "a", [0,1,2,3,4,5]), ("ç", "c", [6]),
                        ("èéêë", "e", [0,1,2,4]),       ("ìíîï", "i", [0,1,2,4]),
                        ("ñ", "n", [3]),                ("òóôõö", "o", [0,1,2,3,4]),
                        ("ø", "o", [7]),                ("ùúûü", "u", [0,1,2,4]),
                        ("ýÿ", "y", [1,4])):
    for ch, a in zip(cps, accs):
        COMPOSE[ord(ch)] = (base, a)

# accent id -> (one row for a shifted capital, then the two rows for lowercase)
ACCENT = {0: (0x60, 0x60, 0x30), 1: (0x0C, 0x0C, 0x18), 2: (0x18, 0x18, 0x24),
          3: (0x6C, 0x32, 0x4C), 4: (0x66, 0x66, 0x00), 5: (0x24, 0x38, 0x28),
          6: (0, 0, 0), 7: (0, 0, 0)}

# the five a downscale gets wrong, drawn instead
HAND = {
 0xA8: [0, 0x66, 0, 0, 0, 0, 0, 0],                    # diaeresis alone
 0xAF: [0, 0x7E, 0, 0, 0, 0, 0, 0],                    # macron
 0xB4: [0x0C, 0x18, 0, 0, 0, 0, 0, 0],                 # acute alone
 0xB8: [0, 0, 0, 0, 0, 0x18, 0x30, 0],                 # cedilla alone
 0xD7: [0, 0, 0x42, 0x24, 0x18, 0x24, 0x42, 0],        # multiplication
}
RASTER = [0xA1,0xA2,0xA4,0xA5,0xA6,0xA7,0xA9,0xAA,0xAB,0xAC,0xAE,0xB5,0xB6,
          0xBA,0xBB,0xBC,0xBD,0xBE,0xBF,0xC6,0xD0,0xDE,0xDF,0xE6,0xF0,0xF7,0xFE]


def rasterise():
    from PIL import Image, ImageDraw, ImageFont
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 96)
    out = {}
    for u in RASTER:
        img = Image.new("L", (240, 240), 0)
        ImageDraw.Draw(img).text((60, 40), chr(u), font=f, fill=255)
        bb = img.getbbox()
        g = img.crop(bb); w, h = g.size; s = 8 / max(w, h)
        nw, nh = max(1, round(w*s)), max(1, round(h*s))
        c = Image.new("L", (8, 8), 0)
        c.paste(g.resize((nw, nh), Image.LANCZOS), ((8-nw)//2, (8-nh)//2))
        px = c.load()
        out[u] = [sum(1 << (7-x) for x in range(8) if px[x, y] > 100) for y in range(8)]
    return out


def compose(u, font):
    """Exactly what PROCv_acc does, so --show is a preview of the machine."""
    base, a = COMPOSE[u]
    g = list(font[ord(base)])
    if base == "i":
        g[0] = 0
    if a == 6:
        g[7] |= 0x18
        return g
    if a == 7:
        for y in range(1, 7):
            g[y] |= 1 << y
        return g
    up, top, bot = ACCENT[a]
    if base.isupper():
        g = [0] + g[:7]
        g[0] = up
    else:
        g[0], g[1] = top, bot
    return g


def main():
    drawn = dict(HAND)
    drawn.update(rasterise())
    if "--show" in sys.argv:
        import re
        font = {}
        for line in open("results/RESFONT"):
            m = re.match(r"^(\d+) ([0-9A-Fa-f]{16})$", line.strip())
            if m:
                font[int(m.group(1))] = [int(m.group(2)[i:i+2], 16) for i in range(0, 16, 2)]
        cells = {u: compose(u, font) for u in COMPOSE}
        cells.update(drawn)
        ks = sorted(cells)
        for i in range(0, len(ks), 8):
            grp = ks[i:i+8]
            print("  " + "  ".join(f"{chr(u)} {u:02X}   " for u in grp))
            for y in range(8):
                print("  " + "  ".join("".join("#" if cells[u][y] & (1 << (7-x)) else "."
                      for x in range(8)) + "  " for u in grp))
            print()
        return
    ks = sorted(drawn)
    print(f"DATA {len(ks)}")
    for i in range(0, len(ks), 4):
        print("DATA " + ",".join(f"&{u:X}," + ",".join(map(str, drawn[u])) for u in ks[i:i+4]))
    cs = sorted(COMPOSE)
    print(f"DATA {len(cs)}")
    for i in range(0, len(cs), 8):
        print("DATA " + ",".join(f"&{u:X},{ord(COMPOSE[u][0])},{COMPOSE[u][1]}" for u in cs[i:i+8]))
    print("DATA " + ",".join(f"{ACCENT[a][0]},{ACCENT[a][1]},{ACCENT[a][2]}" for a in range(8)))


if __name__ == "__main__":
    main()
