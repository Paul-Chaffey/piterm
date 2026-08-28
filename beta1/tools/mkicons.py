#!/usr/bin/env python3
"""Rasterise Nerd Font icons into the DATA statements FBVDU reads.

  tools/mkicons.py "$HOME/.local/share/fonts/.../MesloLGSNerdFontMono-Regular.ttf"
  tools/mkicons.py <font.ttf> --from ~/.config/fastfetch/config.jsonc captures/FFARCH

WHY THIS IS NOT GUESSWORK. A private-use codepoint has no meaning in
Unicode - U+F192 is whatever the font in front of you says it is - so the
only correct source for these glyphs is the font the far machine actually
renders with. This scales that font's own outlines into 8x8 rather than
inventing a shape and hoping it matches. Point it at a different Nerd Font
and the icons change to match that machine.

The two hard divider separators are stretched to fill the cell instead of
being fitted to their aspect: powerline draws them edge to edge, and a
divider with a gap either side is not a divider.

Output goes to stdout as BBC BASIC DATA lines, four icons to a line, in
codepoint order so FNv_icon can bisect. Paste them at the end of
src/fbvdu.bas and check the band with tools/fbbuild.sh.
"""
import sys, re
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

# What archbox's fastfetch config and its output between them ask for, plus the
# four powerline dividers, which no fetch tool draws but most prompts do.
DEFAULT = [0xE0B0, 0xE0B1, 0xE0B2, 0xE0B3, 0xE623, 0xE795, 0xEBC6, 0xEF70,
           0xF013, 0xF028, 0xF031, 0xF192, 0xF488, 0xF489, 0xF003B, 0xF0150,
           0xF027C, 0xF0322, 0xF0379, 0xF03D6, 0xF0443, 0xF04E1, 0xF075A,
           0xF0960, 0xF0ED1, 0xF0EE0, 0xF0F86]
STRETCH = {0xE0B0, 0xE0B1, 0xE0B2, 0xE0B3}
THRESH = 110                    # ink coverage above which a pixel is set

def private(u):
    return 0xE000 <= u <= 0xF8FF or 0xF0000 <= u <= 0xFFFFD

def raster(font, u):
    img = Image.new("L", (300, 300), 0)
    ImageDraw.Draw(img).text((60, 60), chr(u), font=font, fill=255)
    box = img.getbbox()
    if box is None:
        return [0] * 8
    ink = img.crop(box)
    if u in STRETCH:
        cell = ink.resize((8, 8), Image.LANCZOS)
    else:
        w, h = ink.size
        s = 8 / max(w, h)
        nw, nh = max(1, round(w * s)), max(1, round(h * s))
        cell = Image.new("L", (8, 8), 0)
        cell.paste(ink.resize((nw, nh), Image.LANCZOS), ((8 - nw) // 2, (8 - nh) // 2))
    px = cell.load()
    return [sum(1 << (7 - x) for x in range(8) if px[x, y] > THRESH) for y in range(8)]

def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    path, want = argv[1], list(DEFAULT)
    if "--from" in argv:
        want = set()
        for src in argv[argv.index("--from") + 1:]:
            for ch in open(src, encoding="utf-8", errors="replace").read():
                if private(ord(ch)):
                    want.add(ord(ch))
        want = sorted(want)
    cmap = TTFont(path).getBestCmap()
    face = ImageFont.truetype(path, 128)
    missing = [u for u in want if u not in cmap]
    if missing:
        sys.exit("mkicons: not in this font: " + ", ".join(f"U+{u:05X}" for u in missing))

    rows = [(u, cmap[u], raster(face, u)) for u in sorted(want)]
    for u, name, bits in rows:
        print(f"REM  U+{u:05X} {name}", file=sys.stderr)
        for y in range(8):
            print("REM    " + "".join("#" if bits[y] & (1 << (7 - x)) else "."
                                      for x in range(8)), file=sys.stderr)
    print(f"DATA {len(rows)}")
    for i in range(0, len(rows), 4):
        print("DATA " + ",".join(f"&{u:X}," + ",".join(map(str, b))
                                 for u, _, b in rows[i:i + 4]))

if __name__ == "__main__":
    main(sys.argv)
