#!/usr/bin/env python3
"""Diff the engine's screen against pyte's, for the same capture.

    tools/vtdiff.py captures/FEAT captures/FEAT.grid

Phase 3. The engine replays a captured stream with test/fbreplay.bas and
dumps what its cell model ended up holding; this puts the SAME bytes
through pyte at the SAME geometry and compares. It is the first time this
project can check a screen against a reference rather than against a
photograph of a monitor - so a divergence is a located bug rather than a
feeling that something looks wrong.

pyte was rejected in specification.md 6 as a RUNTIME component - it cannot
run on a BBC - but as a test oracle it is exactly right.

The glyph map is read out of src/fbvdu.bas rather than repeated here, so
the oracle and the engine cannot drift apart: the engine stores font slots
and pyte stores Unicode, and FNv_uni is the only thing that knows how they
correspond.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.join(HERE, "..", "src", "fbvdu.bas")


def glyph_map():
    """Unicode codepoint -> font slot, lifted from FNv_uni in the engine."""
    m = {}
    for line in open(ENGINE, encoding="latin-1"):
        g = re.search(r"IF u%=&([0-9A-F]+) THEN =&80\+&([0-9A-F]+)", line)
        if g:
            m[int(g.group(1), 16)] = 0x80 + int(g.group(2), 16)
    if not m:
        raise SystemExit("no FNv_uni mappings found in src/fbvdu.bas")
    return m


def read_dump(path):
    """-> (header dict, [row strings], {(y,x): slot}, {(y,x): (fg,bg,fl)})"""
    head, grid, odd, attr = {}, [], {}, {}
    section = None
    for raw in open(path, encoding="latin-1"):
        line = raw.rstrip("\r\n")
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section not in ("grid", "odd", "runs"):
            # Any leading marker - [fbreplay1] from the emulator,
            # [fbhw1] from the hardware - and the key=value lines under it.
            if "=" in line:
                k, _, v = line.partition("=")
                head[k] = v
            continue
        if section == "grid":
            grid.append(line)
        elif section == "odd":
            y, x, slot = (int(v) for v in line.split())
            odd[(y, x)] = slot
        elif section == "runs":
            y, x, n, f, b, fl = (int(v) for v in line.split())
            for i in range(n):
                attr[(y, x + i)] = (f, b, fl)
    return head, grid, odd, attr


# pyte names the basic sixteen and renders anything else as an RGB hex
# string - 38;5;196 comes back as "ff0000", not as 196. Both are right;
# they are different representations of the same colour, so the two sides
# are normalised to RGB before being compared.
ANSI = ["black", "red", "green", "brown", "blue", "magenta", "cyan", "white"]
BRIGHT = {"bright" + n: i + 8 for i, n in enumerate(ANSI)}

# The engine's palette, built exactly as PROCv_pal builds it: the ANSI
# sixteen from DATA, then the 6x6x6 cube, then the greys. FBPAL2 proved on
# hardware that all 256 entries are individually programmable, so these are
# the colours actually on the glass and not an approximation of them.
ANSI16 = [(0, 0, 0), (170, 0, 0), (0, 170, 0), (170, 85, 0),
          (0, 0, 170), (170, 0, 170), (0, 170, 170), (170, 170, 170),
          (85, 85, 85), (255, 85, 85), (85, 255, 85), (255, 255, 85),
          (85, 85, 255), (255, 85, 255), (85, 255, 255), (255, 255, 255)]


def _cube(v):
    return 0 if v == 0 else 55 + 40 * v


def index_rgb(n):
    """Font-slot colour index -> (r, g, b), mirroring PROCv_pal."""
    if n < 16:
        return ANSI16[n]
    if n < 232:
        i = n - 16
        return (_cube(i // 36), _cube((i // 6) % 6), _cube(i % 6))
    g = 8 + (n - 232) * 10
    return (g, g, g)


def pyte_colour(name, default):
    """-> ("index", n) or ("rgb", (r, g, b)) or None if pyte said something
    this does not understand, in which case no difference is reported: an
    invented mismatch is worse than a missed one."""
    if name == "default":
        return ("index", default)
    if name in ANSI:
        return ("index", ANSI.index(name))
    if name in BRIGHT:
        return ("index", BRIGHT[name])
    if re.fullmatch(r"[0-9a-fA-F]{6}", name):
        v = int(name, 16)
        return ("rgb", (v >> 16, (v >> 8) & 0xFF, v & 0xFF))
    return None


def colour_differs(ours, theirs):
    if theirs is None:
        return False
    kind, v = theirs
    if kind == "index":
        return v != ours
    return v != index_rgb(ours)


def colour_show(theirs):
    if theirs is None:
        return "?"
    kind, v = theirs
    return str(v) if kind == "index" else "#%02x%02x%02x" % v


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    cap, dump = sys.argv[1], sys.argv[2]
    try:
        import pyte
    except ImportError:
        raise SystemExit(
            "pyte is not installed, and it is the oracle this whole phase\n"
            "rests on. It is blocked by PEP 668 on this machine, so:\n"
            "    sudo apt install python3-pyte\n"
            "or  pip install --break-system-packages pyte")

    raw = open(cap, "rb").read()
    # pyte has NO alternate screen - no 1049, 1047 or 47 anywhere in it, and
    # ?1049h is a silent no-op, so the text meant for the alternate buffer
    # lands on the main screen and stays there. The engine keeps a real
    # second buffer, which is the thing 9.3 could not do and is one of the
    # reasons this project owns its own VDU. So a difference here is the
    # ORACLE's gap, and the engine must not be changed to match it: the
    # alternate screen is checked by test/fbparse.bas instead.
    if re.search(rb"\x1b\[\?(?:1049|1047|47)[hl]", raw):
        print("  !! this capture switches to the alternate screen, which pyte")
        print("     does not implement at all. Any difference below may be the")
        print("     oracle's, not the engine's - see captures/ALT.")
        print()

    head, grid, odd, attr = read_dump(dump)
    cols, rows = (int(v) for v in head["geometry"].split("x"))
    gmap = glyph_map()

    screen = pyte.Screen(cols, rows)
    stream = pyte.Stream(screen)
    # pyte DELIBERATELY ignores ESC ( 0 while use_utf8 is set, on the
    # argument that a UTF-8 terminal should be sent real box-drawing
    # characters instead. That is a documented deviation from xterm, and
    # xterm is what we target: xterm-256color's smacs IS \E(0, so ncurses
    # sends it for every box it draws and a terminal that ignored it would
    # render mc and dialog as strings of lqqk.
    #
    # So the flag is cleared - which in pyte gates the ESC ( dispatch and
    # nothing else - and the UTF-8 decoding is done here instead. This is
    # the ONLY place the oracle is adjusted, and it is adjusted towards
    # real terminal behaviour rather than towards agreeing with us.
    stream.use_utf8 = False
    stream.feed(raw.decode("utf-8", "replace"))

    bad, shown = 0, 0
    for y in range(rows):
        want = screen.display[y]
        for x in range(cols):
            wc = want[x]
            # What the engine should be holding: a font slot.
            if ord(wc) < 128:
                wslot = ord(wc)
            else:
                wslot = gmap.get(ord(wc), 63)     # 63 is the replacement glyph
            got = odd.get((y, x))
            if got is None:
                got = ord(grid[y][x]) if x < len(grid[y]) else 32
            if got != wslot:
                bad += 1
                if shown < 20:
                    shown += 1
                    print(f"  {y:3},{x:3}  engine {got:4} {_show(got)}"
                          f"   pyte {wslot:4} {_show(wslot)}  {wc!r}")
    print()
    if bad:
        print(f"  {bad} cells differ out of {rows * cols}")
    else:
        print(f"  all {rows * cols} cells match pyte")

    # Attributes second, and only if the text agrees - a shifted screen
    # would otherwise report every cell twice.
    if not bad:
        abad = 0
        for y in range(rows):
            for x in range(cols):
                c = screen.buffer[y][x]
                f, b, fl = attr.get((y, x), (7, 0, 0))
                wf = pyte_colour(c.fg, 7)
                wb = pyte_colour(c.bg, 0)
                wfl = (1 if c.reverse else 0) | (2 if c.underscore else 0) \
                    | (4 if c.bold else 0) | (8 if getattr(c, "strikethrough", False) else 0)
                if colour_differs(f, wf) or colour_differs(b, wb) or wfl != fl:
                    abad += 1
                    if abad <= 12:
                        print(f"  {y:3},{x:3}  engine fg={f} bg={b} fl={fl}"
                              f"   pyte fg={colour_show(wf)} bg={colour_show(wb)}"
                              f" fl={wfl}")
        if abad:
            print(f"  {abad} cells differ in attributes")
        else:
            print(f"  and all {rows * cols} attribute cells match")
    return 1 if bad else 0


def _show(slot):
    if 32 <= slot <= 126:
        return repr(chr(slot))
    return f"(slot {slot})"


if __name__ == "__main__":
    sys.exit(main())
