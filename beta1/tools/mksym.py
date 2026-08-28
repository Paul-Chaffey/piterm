#!/usr/bin/env python3
"""The last 24 odds and ends, as FBVDU DATA.

  tools/mksym.py            print the DATA
  tools/mksym.py --show     draw them

Everything left over once the families were done: what fastfetch's builtin
logos still asked for and nothing else covered, plus the two arrows that
complete the set already half present. There is no rule behind these - they
are a list - so they are rasterised from DejaVu Sans Mono and the seven a
downscale ruins are drawn by hand instead.

WHICH SEVEN, AND WHY. Anything whose meaning lives in a thin line at this size
comes out as a grey smear when 96 pixels are averaged down to 8: the scan
lines and the heavy rules are one pixel of a rule that must land on an exact
row, the box-drawing halves have to meet their neighbours on row 3, and the
identical-to and almost-equal signs need three separated strokes that a
downscale merges into a block.
"""
import sys

RASTER = [0x25BA, 0x25C4, 0x207F, 0x221A, 0x2310, 0x0384, 0x2302, 0x25CF,
          0x2229, 0x0393, 0x221E, 0x03C6, 0x0192, 0x2320, 0x27E8, 0x27E9,
          0x2261, 0x2248]
HAND = {
 0x2501: [0, 0, 0, 0xFF, 0xFF, 0, 0, 0],            # heavy horizontal, two rows
 0x257C: [0, 0, 0, 0xF8, 0x0F, 0, 0, 0],            # light left, heavy right
 0x257E: [0, 0, 0, 0xF0, 0x1F, 0, 0, 0],            # heavy left, light right
 0x23BA: [0xFF, 0, 0, 0, 0, 0, 0, 0],               # scan line 1
 0x23BB: [0, 0xFF, 0, 0, 0, 0, 0, 0],               # scan line 3
 0x23BC: [0, 0, 0, 0, 0, 0xFF, 0, 0],               # scan line 7
 0x23BD: [0, 0, 0, 0, 0, 0, 0, 0xFF],               # scan line 9
}
# 257C and 257E share row 3 with the single set so they join it; the heavy
# half is doubled onto row 4, which is where the double set puts its lower
# rail, so a heavy rule lines up with a double one too.


def rasterise():
    from PIL import Image, ImageDraw, ImageFont
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 96)
    out = {}
    for u in RASTER:
        img = Image.new("L", (240, 240), 0)
        ImageDraw.Draw(img).text((60, 40), chr(u), font=f, fill=255)
        bb = img.getbbox()
        if bb is None:
            out[u] = [0]*8
            continue
        g = img.crop(bb); w, h = g.size; s = 8 / max(w, h)
        nw, nh = max(1, round(w*s)), max(1, round(h*s))
        c = Image.new("L", (8, 8), 0)
        c.paste(g.resize((nw, nh), Image.LANCZOS), ((8-nw)//2, (8-nh)//2))
        px = c.load()
        out[u] = [sum(1 << (7-x) for x in range(8) if px[x, y] > 100) for y in range(8)]
    return out


def main():
    cells = dict(HAND)
    cells.update(rasterise())
    ks = sorted(cells)
    if "--show" in sys.argv:
        import unicodedata
        for i in range(0, len(ks), 8):
            grp = ks[i:i+8]
            print("  " + "  ".join(f"{chr(u)} {u:04X}  " for u in grp))
            for y in range(8):
                print("  " + "  ".join("".join("#" if cells[u][y] & (1 << (7-x)) else "."
                      for x in range(8)) + "  " for u in grp))
            print()
        return
    print(f"DATA {len(ks)}")
    for i in range(0, len(ks), 4):
        print("DATA " + ",".join(f"&{u:X}," + ",".join(map(str, cells[u])) for u in ks[i:i+4]))


if __name__ == "__main__":
    main()
