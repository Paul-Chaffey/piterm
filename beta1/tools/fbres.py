#!/usr/bin/env python3
"""Read the FBVDU probe result files off the share and analyse them.

    tools/fbres.py                    everything found in share/
    tools/fbres.py share/RESFONT      just that one
    tools/fbres.py --font font.bin    also write the harvested font out

The probes (test/fbpal.bas, test/fbfont.bas, test/fbbench.bas) write
RESPAL, RESFONT and RESBENC to the Samba share the Beeb mounts. This
does the arithmetic and the checking on this side, where it can be
read and re-read, rather than in BASIC print statements on a monitor.

Where a result can be checked rather than described, it is: the six
box glyphs have known bit patterns, so the harvest is verified against
them exactly - which also settles byte order, since a mirrored harvest
turns &1F into &F8.
"""
import sys, os, re

SHARE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "share")

# The VDU 23 definitions in test/fbfont.bas. Harvesting these back is a
# closed loop: known in, known out.
BOX = {
    224: [0, 0, 0, 0x1F, 0x18, 0x18, 0x18, 0x18],
    225: [0, 0, 0, 0xF8, 0x18, 0x18, 0x18, 0x18],
    226: [0x18, 0x18, 0x18, 0x1F, 0, 0, 0, 0],
    227: [0x18, 0x18, 0x18, 0xF8, 0, 0, 0, 0],
    228: [0, 0, 0, 0xFF, 0, 0, 0, 0],
    229: [0x18] * 8,
}


def read(path):
    """Read a result file, and say when it was written.

    OPENOUT truncates - confirmed on hardware 2026-08-20, where a 7,960-byte
    file was replaced by a 156-byte one with nothing left behind. The hazard
    is not a stale tail, it is a stale FILE: if a probe cannot open its
    output it says so on screen and carries on, and the previous run's file
    is then sitting there looking current. So print the age and the nonce,
    and never analyse a file without showing when it was written.
    """
    import datetime
    st = os.stat(path)
    when = datetime.datetime.fromtimestamp(st.st_mtime)
    age = (datetime.datetime.now() - when).total_seconds()
    unit = f"{age/3600:.1f} hours ago" if age > 5400 else f"{age/60:.0f} minutes ago"
    print(f"  written      {when:%Y-%m-%d %H:%M}  ({unit}, {st.st_size} bytes)")
    with open(path, "rb") as f:
        raw = f.read()
    return [l.strip() for l in raw.decode("latin-1").replace("\r\n", "\n")
            .replace("\r", "\n").split("\n") if l.strip()]


def parse(lines):
    """-> (dict of key=value, dict of section name -> list of lines)"""
    kv, sections, cur = {}, {}, None
    for line in lines:
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
            sections.setdefault(cur, [])
        elif "=" in line and not line[0].isdigit():
            k, _, v = line.partition("=")
            kv[k] = v
        elif cur:
            sections[cur].append(line)
    return kv, sections


def incomplete(sections):
    if "end" not in sections:
        print("  !! no [end] marker - the probe did not reach the end of its run,")
        print("     so anything missing below is missing because it never ran.")
        return True
    return False


def bail(kv):
    if "error" in kv:
        print(f"  !! the probe stopped early: {kv['error']}")
        return True
    if "fail" in kv:
        print(f"  !! {kv['fail']}")
        return True
    return False


def art(rows):
    return ["".join("#" if b & (0x80 >> i) else "." for i in range(8)) for b in rows]


# ---------------------------------------------------------------- font
def do_font(path, fontout=None):
    print(f"=== {path} — font harvest ===")
    kv, sec = parse(read(path))
    incomplete(sec)
    for k in ("run", "screen", "size", "pitch", "background", "glyphs", "harvest_cs"):
        if k in kv:
            print(f"  {k:12} {kv[k]}")
    if bail(kv):
        return

    glyphs = {}
    for line in sec.get("font", []):
        code, _, hexs = line.partition(" ")
        hexs = hexs.strip()
        if not code.isdigit() or len(hexs) % 2:
            continue
        glyphs[int(code)] = [int(hexs[i:i + 2], 16) for i in range(0, len(hexs), 2)]
    print(f"  glyphs read  {len(glyphs)}")
    if not glyphs:
        print("  !! no [font] section — nothing was harvested")
        return

    blank = [c for c, r in glyphs.items() if c != 32 and not any(r)]
    show = ", ".join(str(c) for c in blank[:12]) + (" ..." if len(blank) > 12 else "")
    print(f"  blank        {len(blank)}" + (f"  {show}" if blank else "  (only space, as expected)"))
    if len(blank) > len(glyphs) / 2:
        print("  !! most glyphs came back empty — the driver draws somewhere the")
        print("     read-back cannot see. The font must be transported instead.")

    # The closed loop: known bits in through VDU 23, known bits out.
    print("\n  box glyphs against their VDU 23 definitions:")
    mirrored = ok = 0
    for code, want in BOX.items():
        got = glyphs.get(code)
        if got is None:
            print(f"    {code}  MISSING")
            continue
        if got == want:
            ok += 1
            print(f"    {code}  match")
        elif got == [int(f"{b:08b}"[::-1], 2) for b in want]:
            mirrored += 1
            print(f"    {code}  MIRRORED — bit 0 is the leftmost pixel, not bit 7")
        else:
            print(f"    {code}  differs: want {[hex(b) for b in want]}")
            print(f"          got  {[hex(b) for b in got]}")
    if ok == len(BOX):
        print("  => harvest and byte order are both correct")
    elif mirrored:
        print("  => PROCxp must fill the four bytes the other way round")

    print("\n  a sample, as harvested:")
    for code in (65, 70, 87, 103, 224, 229):
        if code in glyphs:
            print(f"    {code} {chr(code) if 32 < code < 127 else ' '}")
            for row in art(glyphs[code]):
                print(f"      {row}")

    if fontout:
        blob = bytearray(256 * 8)
        for c, rows in glyphs.items():
            blob[c * 8:c * 8 + len(rows)] = bytes(rows)
        with open(fontout, "wb") as f:
            f.write(blob)
        print(f"\n  font written to {fontout} ({len(blob)} bytes)")


# ------------------------------------------------------------- palette
def xterm256():
    p = [(0, 0, 0), (170, 0, 0), (0, 170, 0), (170, 85, 0), (0, 0, 170),
         (170, 0, 170), (0, 170, 170), (170, 170, 170), (85, 85, 85),
         (255, 85, 85), (85, 255, 85), (255, 255, 85), (85, 85, 255),
         (255, 85, 255), (85, 255, 255), (255, 255, 255)]
    lv = [0, 95, 135, 175, 215, 255]
    for r in range(6):
        for g in range(6):
            for b in range(6):
                p.append((lv[r], lv[g], lv[b]))
    p += [(8 + i * 10,) * 3 for i in range(24)]
    return p


def pal_section(lines):
    out = {}
    for line in lines:
        parts = line.split()
        if len(parts) < 2 or not parts[0].isdigit():
            continue
        w = int(parts[1].lstrip("&"), 16) & 0xFFFFFFFF
        # RISC OS palette word is &BBGGRR00
        out[int(parts[0])] = ((w >> 8) & 0xFF, (w >> 16) & 0xFF, (w >> 24) & 0xFF)
    return out


def do_pal(path):
    print(f"=== {path} — palette depth ===")
    kv, sec = parse(read(path))
    incomplete(sec)
    for k in ("run", "screen", "size", "pitch", "readpalette"):
        if k in kv:
            print(f"  {k:12} {kv[k]}")

    dumps = {n[len("palette "):]: pal_section(v)
             for n, v in sec.items() if n.startswith("palette ")}

    # A SWI that returns without error but writes nothing is a stub, and a
    # stub reads back the same value for every entry no matter what was
    # just programmed. Confirmed on hardware 2026-08-20: every entry, every
    # dump, zero. Not erroring is not the same as being implemented.
    if dumps and all(len(set(d.values())) <= 1 for d in dumps.values()):
        vals = {v for d in dumps.values() for v in d.values()}
        print(f"  !! OS_ReadPalette is a STUB - all {sum(len(d) for d in dumps.values())} reads across")
        print(f"     {len(dumps)} dumps returned {vals.pop() if len(vals)==1 else vals}, including after the palette was")
        print("     reprogrammed. The dumps carry no information; ignore them.")
        dumps = {}

    if not dumps:
        print("  Falling back to what was seen on the screen:")
        for k in ("distinct256", "blue", "xterm", "osword"):
            if k in kv:
                print(f"    {k:12} {kv[k]}")
        # FBPAL2: control first, then the only question that separates the
        # three worlds — did the OTHER block move too?
        if "vdu19" in kv or "control" in kv:
            return do_pal2(kv)

        b, blocks, x = kv.get("blue", "").upper(), kv.get("blocks", "").upper(), kv.get("xterm", "").upper()
        if blocks == "A" or b == "1":
            print("  => entries above 15 ARE programmable — xterm-256color can be exact")
        elif blocks == "B" or b == "0":
            print("  => VDU 19 wrapped mod 16 — only 16 entries. FNx256 stands")
        elif blocks == "N" or b in ("N", "2"):
            print("  => VDU 19 ignored above 15 — only 16 entries. FNx256 stands")
        # FBPAL's A/B/N question was not exclusive: block A was index 200 and
        # block B index 8, and 8 is what 200 becomes if VDU 19 wraps mod 16,
        # so in the wrapped world both blocks change and "A" is true but
        # uninformative. Say so rather than picking the flattering reading.
        if blocks == "A" and b == "N":
            print("     ...but blue=N contradicts it: entries 16-31 asked for blue")
            print("     changed nothing, and under EITHER a deep palette (band 1")
            print("     turns blue) or a mod-16 wrap (the whole screen does)")
            print("     something had to move. The A/B/N question could not")
            print("     express BOTH, so it cannot settle this. Run FBPAL2.")
        elif x == "Y":
            print("  => the xterm chart appearing needs the 6x6x6 cube across entries")
            print("     16-231, so this points at depth — but it is a weaker reading")
            print("     than the block test. Re-run for a direct answer.")
        else:
            print("  => no usable answer recorded. Re-run the probe.")
        bail(kv)
        return

    deep = None
    before, after = dumps.get("before"), dumps.get("after1631")
    if before:
        print(f"  distinct colours in the default palette: {len(set(before.values()))} of {len(before)}")
    if before and after:
        changed = sorted(n for n in after if before.get(n) != after[n])
        print(f"  entries changed by asking 16-31 for blue: {changed or 'none'}")
        deep = bool(changed) and min(changed) >= 16
        if deep:
            print("  => entries above 15 ARE programmable — xterm-256color can be exact")
        elif changed:
            print("  => VDU 19 wrapped mod 16 — only 16 entries exist. FNx256 stands")
        else:
            print("  => VDU 19 is ignored above 15. FNx256 stands")

    x = dumps.get("afterxterm")
    if x:
        want = xterm256()
        bad = [n for n in sorted(x) if n < len(want) and x[n] != want[n]]
        if not bad and deep is False:
            print(f"  all {len(x)} entries read back as the xterm palette, which CONTRADICTS")
            print("  the 16-31 result above. Distrust both and re-run the probe.")
        elif not bad:
            print(f"  the xterm palette took exactly, all {len(x)} entries")
            print("  => TERM=xterm-256color is honest, and no nearest-colour table is needed")
        else:
            print(f"  {len(bad)} of {len(x)} entries did not take, first few:")
            for n in bad[:8]:
                print(f"    {n:3}  asked {want[n]}  got {x[n]}")
    bail(kv)


def do_pal2(kv):
    """FBPAL2: a positive control, then whether the companion block moved."""
    c = kv.get("control", "").upper()
    print(f"    control      {c}   (entry 4, known programmable)")
    if c != "Y":
        print("  !! THE CONTROL FAILED. Reprogramming an entry 2.3 already proved")
        print("     programmable changed nothing on screen, so the method is at")
        print("     fault, not the palette. Nothing else in this run counts.")
        return
    verdicts = {
        "1": ("only the LEFT block moved - 256 real entries",
              "=> xterm-256color can be EXACT. No nearest-colour table needed."),
        "2": ("BOTH moved - one entry wearing two numbers",
              "=> 16 entries addressed by the low nibble, the 64x4 of 2.3.\n"
              "        FNx256's reduction stands."),
        "3": ("neither moved - the call is ignored above entry 15",
              "=> 16 entries only. FNx256's reduction stands."),
    }
    for key, label in (("vdu19", "VDU 19"), ("osword12", "OS_Word 12")):
        v = kv.get(key)
        if not v:
            continue
        head, tail = verdicts.get(v, ("unrecognised answer " + v, ""))
        print(f"    {label:11} {v}   {head}")
        if tail:
            print(f"        {tail}")
    if kv.get("vdu19") == "3" and kv.get("osword12") == "1":
        print("  note: OS_Word 12 reaches entries VDU 19 cannot - use it in FBVDU.")
    if kv.get("osword12call") == "absent":
        print("    OS_Word 12 is not implemented at all.")



def do_save(path):
    print(f"=== {path} - SAVE/LOAD round trip ===")
    kv, sec = parse(read(path))
    incomplete(sec)
    for k in ("run", "page", "top"):
        if k in kv:
            print(f"  {k:12} {kv[k]}")
    if bail(kv):
        print("     An error at the SAVE is itself the answer: the filing system")
        print("     will not take a written program, and the engine has to stay")
        print("     small enough to *EXEC.")
        return
    mem, disc = kv.get("memlen"), kv.get("filelen")
    diff = kv.get("diffwords")
    print(f"  in memory    {mem} bytes")
    print(f"  on disc      {disc} bytes" + ("  - matches" if mem == disc else "  - DIFFERS"))
    print(f"  differing    {diff} words")
    for k, label in (("save_cs", "SAVE"), ("load_cs", "LOAD")):
        if k in kv:
            cs = int(kv[k])
            rate = f", {int(mem)*100/cs/1024:.0f} KB/sec" if cs and mem else ""
            print(f"  {label:12} {cs} cs{rate}")
    # The Beeb compared the file against its own memory. This checks the same
    # file from the other end: is what the filing system kept a well-formed
    # tokenised program? Line format is 0D, line-hi, line-lo, length, text,
    # ending 0D FF.
    saved = os.path.join(os.path.dirname(path) or ".", "FBTEMP")
    if os.path.exists(saved):
        d = open(saved, "rb").read()
        i, nums, fault = 0, [], None
        while i < len(d):
            if d[i] != 0x0D:
                fault = f"expected &0D at offset {i}, found &{d[i]:02X}"
                break
            if i + 1 < len(d) and d[i + 1] == 0xFF:
                break
            if d[i + 3] < 4:
                fault = f"impossible line length at offset {i}"
                break
            nums.append((d[i + 1] << 8) | d[i + 2])
            i += d[i + 3]
        if fault:
            print(f"  FBTEMP       NOT a valid tokenised program - {fault}")
        else:
            end = "0D FF" if d[i:i + 2] == b"\x0d\xff" else "MISSING"
            print(f"  FBTEMP       valid tokenised BASIC, {len(nums)} lines, "
                  f"{nums[0]}..{nums[-1]}, terminator {end}")

    if kv.get("verdict") == "pass":
        print("  => the round trip is clean. *EXEC once, SAVE, CHAIN thereafter -")
        print("     so FBVDU can be a thousand lines without the edit-test loop")
        print("     costing minutes a run.")
    else:
        print("  => DO NOT build the edit-test loop on this. A differing length")
        print("     means something was translated, differing words mean something")
        print("     was corrupted. Keep *EXEC and split the engine into parts")
        print("     small enough to type in.")


def do_vdu(path):
    print(f"=== {path} - FBVDU renderer ===")
    kv, sec = parse(read(path))
    incomplete(sec)
    for k in ("run", "geometry", "screen"):
        if k in kv:
            print(f"  {k:12} {kv[k]}")
    if bail(kv):
        return

    def pair(v):
        cs = int(v.split()[0])
        rest = " ".join(v.split()[1:])
        return cs, rest

    cells = None
    if "geometry" in kv:
        try:
            w, h = kv["geometry"].split()[0].split("x")
            cells = int(w) * int(h)
        except ValueError:
            cells = None
    percell = None
    for key, label in (("full_flush_cs", "full flush"), ("small_flush_cs", "one cell changed"),
                       ("attr_flush_cs", "attribute page"), ("scroll10_cs", "ten scrolls")):
        if key in kv:
            cs, rest = pair(kv[key])
            print(f"  {label:18} {cs:5} cs" + (f"  {rest}" if rest else ""))
            n = None
            for part in kv[key].split():
                if part.startswith("painted="):
                    n = int(part[len("painted="):])
            if n and cs and key == "full_flush_cs":
                percell = cs / n

    # A flush costs the walk over every cell plus a blit for each one that
    # changed, so a flush time on its own says nothing about the worst case.
    # Quoting 1/flush_time as "repaints a second" flatters a page that was
    # mostly blank - it did not repaint a screen, it repainted 848 cells.
    if percell and cells:
        worst = percell * cells
        print(f"\n  {1/percell*100:.0f} cells/sec painted")
        print(f"  a full {cells}-cell repaint would be {worst:.0f} cs, "
              f"{100/worst:.1f} a second")
        print(f"  => {'clears' if 100/worst >= 2 else 'BELOW'} the 2-3 a second the decoupled flush needs")
        print("     (worst case only: the flush paints what changed, and a top")
        print("      refresh is a few hundred cells, not five thousand)")

    # A screen that looks right is not a measurement - but a measurement is
    # not a screen that looks right, either. These are the things only an eye
    # can check, recorded so the checking survives the session.
    checks = [("p1_palette", "256 patches all different"),
              ("p1_ansi", "16 ANSI lines, 16 colours"),
              ("p1_box", "box pieces close into a rectangle"),
              ("p1_cursor", "cursor block visible"),
              ("p2_attr", "bold, reverse, underline, strike"),
              ("p2_ink", "coloured pairs legible"),
              # Phase 2 and 3, and these are the ones that could not be
              # checked any other way. The DEC set is written into font%
              # by PROCv_glyphs and pyte cannot judge pixels; the bar is
              # phase 3's two bugs made visible.
              ("p3_dec", "DEC line drawing draws one unbroken box"),
              ("p3_utf8", "the UTF-8 box is identical to it"),
              ("p3_bar", "the reverse bar reaches the right edge"),
              ("p3_notch", "and has no gap at its right end")]
    seen_checks = [(k, label) for k, label in checks if k in kv]
    if seen_checks:
        print("\n  looked at:")
        failed = []
        for k, label in seen_checks:
            v = kv[k].upper()
            print(f"    {'ok  ' if v == 'Y' else 'FAIL'}  {label}")
            if v != "Y":
                failed.append(label)
        if not failed:
            print("  => the renderer is visually correct as well as fast enough")
        else:
            print(f"  !! {len(failed)} visual check(s) failed: " + "; ".join(failed))

    # The scroll's whole justification is that it leaves the moved region
    # already correct on the glass. Damage above the exposed row means the
    # pixels, the model and the shadow came out of step.
    if "scroll10_above" in kv and "scroll10_exposed" in kv:
        above = kv["scroll10_above"]
        exposed = kv["scroll10_exposed"]
        painted = kv.get("scroll10_repainted", "?")
        print()
        print(f"  scroll invariant: {above} cells damaged above the exposed row,")
        print(f"                    {exposed} exposed and {painted} repainted")
        if above == "0" and exposed == painted:
            print("  => the glass, the model and the shadow stayed in step:")
            print("     the pixels moved and only the exposed row was redrawn")
        else:
            print("  !! the three are NOT in step - a scroll left the shadow")
            print("     disagreeing with the glass, and the flush will skip")
            print("     exactly the cells that need painting")
    if "scroll1" in kv:
        v = kv["scroll1"]
        print(f"  scroll invariant   {v}")
        if not v.startswith("pass"):
            print("  !! the scroll moved pixels, model and shadow out of step. Anything")
            print("     scrolled is now wrong on screen and the flush will not fix it,")
            print("     because the shadow says it is already painted.")



# --------------------------------------------------------------- bench
def do_bench(path):
    print(f"=== {path} — blit rate ===")
    kv, sec = parse(read(path))
    incomplete(sec)
    for k in ("run", "screen", "size", "pitch"):
        if k in kv:
            print(f"  {k:12} {kv[k]}")
    if bail(kv):
        return

    def num(v, key):
        for part in v.split():
            if part.startswith(key + "="):
                return int(part[len(key) + 1:])
            if key == "cs" and part.isdigit():
                return int(part)
        return None

    reps = int(kv.get("reps", 1))
    rows = [("Z  empty loop", "z_emptyloop_cs"),
            ("A  8x8  PROC/cell", "a_proc_8x8_cs"), ("B  8x8  inline", "b_inline_8x8_cs"),
            ("C  8x8  unrolled", "c_unrolled_8x8_cs"), ("D  8x16 inline", "d_inline_8x16_cs")]
    best8 = None
    seen = []
    if reps > 1:
        print(f"\n  ({reps} repeats of each; per-run figures below)")
    else:
        print()
    for label, key in rows:
        if key not in kv:
            continue
        cs, cells = num(kv[key], "cs"), num(kv[key], "cells")
        if not cs:
            print(f"  {label:20} {kv[key]}  (too fast to time)")
            continue
        per = cs / reps
        if key.startswith("z_"):
            print(f"  {label:20} {per:7.1f} cs   the interpreter walking the loop, no pixels")
            continue
        seen.append(cs)
        rate, screens = cells * reps * 100 / cs, 100 / per
        print(f"  {label:20} {per:7.1f} cs  {rate:8.0f} cells/sec  {screens:5.1f} screens/sec")
        if "8x8" in label and (best8 is None or per < best8):
            best8 = per
    # Four structurally different loops cannot cost the same. If they do, the
    # timer is the thing being measured. Seen on hardware 2026-08-20 at one
    # repeat: 9 cs for all four.
    if len(seen) > 2 and len(set(seen)) == 1 and reps < 5:
        print(f"\n  !! all {len(seen)} variants returned exactly {seen[0]} cs. A PROC call per")
        print("     cell cannot cost the same as an unrolled loop, so this is timer")
        print("     resolution, not a result. Re-run with rep% raised.")
    d = num(kv.get("d_inline_8x16_cs", ""), "cs")
    d = d / reps if d else d
    if best8 and d:
        print(f"\n  80x64 at best {100/best8:.1f} repaints/sec, 80x32 at {100/d:.1f}")
        print(f"  same pixels, half the cells: {'80x32 is cheaper — per-cell overhead dominates' if d < best8 * 0.85 else 'no real difference — per-cell overhead is not the cost'}")
    for key, label in (("e_shadow_cs", "shadow compare"), ("f_scrollmove_cs", "scroll as a screen move"),
                       ("g_words_cs", "8K by words"), ("g_bytes_cs", "8K by bytes")):
        if key in kv:
            cs = num(kv[key], "cs")
            per = f"{cs/reps:.1f} cs" if cs is not None else kv[key]
            print(f"  {label:24} {per}")
    # A scroll that costs less than a repaint is worth knowing about: the
    # engine can move pixels and repaint one row instead of redrawing 5120.
    fcs, ccs = num(kv.get("f_scrollmove_cs", ""), "cs"), num(kv.get("c_unrolled_8x8_cs", ""), "cs")
    if fcs and ccs and fcs < ccs:
        print(f"  => scrolling by moving the screen ({fcs/reps:.1f} cs) beats repainting it")
        print(f"     ({ccs/reps:.1f} cs). Worth a special case in the flush.")
    if best8:
        print("\n  The network delivers 3082 bytes/sec and a flush happens once per")
        print("  drain, not once per line, so 2-3 repaints/sec is a working terminal.")
        print(f"  => {'clears it' if 100/best8 >= 2 else 'DOES NOT clear it — the renderer needs native code'}")


def do_ptr(path):
    """test/ptrtest.bas - do OSWORD &C0 buffer pointers cross the Tube on
    copro 15? specification.md 2.4 has had this open since copro 15 was
    chosen; 5.5c proved it on a 6502 core, where the pointer is a 16-bit
    address the host already understands.

    The two directions are separate results and only one of them was ever
    in doubt:

      ptr_out  the module READ ARM memory - a 16-byte sockaddr it could
               not have connected without
      ptr_in   the module WROTE ARM memory - the direction that failed
               offline against SOCKSTUB

    A claimed read that delivers nothing is the trap here, so the probe
    poisons its receive buffer with &55 first and counts how many of the
    first sixteen bytes changed. "recv reported bytes" and "the buffer
    changed" are different facts and this keeps them apart.
    """
    print(f"=== {path}")
    lines = read(path)
    kv, sections = parse(lines)
    if bail(kv):
        return
    inc = incomplete(sections)

    for k, label in (("page", "PAGE"), ("himem", "HIMEM"),
                     ("block", "control block"), ("sockaddr", "sockaddr"),
                     ("recvbuf", "receive buffer")):
        if k in kv:
            print(f"  {label:14} {kv[k]}")
    if "warn" in kv:
        print(f"  !! {kv['warn']}")

    buf = kv.get("recvbuf", "")
    if "&" in buf:
        try:
            addr = int(buf.split("&")[1].split()[0], 16)
            if addr >= 0x10000:
                print(f"  the receive buffer is above 64K, so a 16-bit truncated")
                print(f"  host write could not reach it by accident")
        except ValueError:
            pass

    for k in ("presence", "creat", "connect", "send", "recv"):
        if k in kv:
            print(f"  {k:14} {kv[k]}")
    for k in ("buf", "txt"):
        if k in kv:
            print(f"  {k:14} {kv[k]}")
    if "changed" in kv:
        print(f"  {'poison':14} {kv['changed']} bytes differ from &55")

    print()
    out = kv.get("ptr_out")
    inn = kv.get("ptr_in")
    if out == "YES":
        print("  OUTWARD: the module read a 32-bit ARM pointer. Connect")
        print("           succeeded, and it could not have without the")
        print("           sockaddr at that address.")
    elif out == "NO":
        print("  OUTWARD: FAILED. Connect was refused, so the sockaddr was")
        print("           not read from ARM memory.")

    if inn == "YES":
        print("  INWARD:  the module wrote ARM memory. POINTERS CROSS THE")
        print("           TUBE ON COPRO 15 - 2.4's open question is closed")
        print("           the good way and PTERM can call OSWORD C0 direct.")
    elif inn == "NO":
        print("  INWARD:  FAILED, and this is the one that matters. recv")
        print("           reported bytes while the ARM buffer stayed at &55,")
        print("           so the module wrote somewhere else - almost")
        print("           certainly the host at the truncated address.")
        print("           A host-side BEEBNET is back on the table for the")
        print("           receive path, and 8 Step 1 has to be un-cancelled.")
    elif inn == "NODATA":
        print("  INWARD:  UNDECIDED - no bytes arrived at all, so the")
        print("           direction was never exercised. Is the listener up?")
        print("           It must SEND something on connect, not just accept.")

    if inc:
        print("  (no [end] marker, so treat all of this as partial)")

def do_ptr2(path):
    """test/ptrtest2.bas - the same call at a low and a high address.

    PTRTEST changed two things at once: it moved every buffer above 64K
    AND asked whether pointers cross. This holds the call fixed and varies
    only the address, so "lo works, hi does not" means truncation and
    "neither works" means the address was never the issue.
    """
    print(f"=== {path}")
    lines = read(path)
    kv, sections = parse(lines)
    if bail(kv):
        return
    inc = incomplete(sections)

    def field(key):
        """PROCsay writes "lo_creat +2=0 +3=0", so parse() splits at the
        first = and the key becomes "lo_creat +2". Read those off the raw
        lines by prefix instead, and still accept the key=value form."""
        if key in kv:
            return kv[key]
        for line in lines:
            if line.startswith(key + " "):
                return line[len(key) + 1:]
        return None

    for k, label in (("page", "PAGE"), ("block", "control block"),
                     ("lo_sa", "low  addresses"), ("hi_sa", "high addresses")):
        if k in kv:
            print(f"  {label:16} {kv[k]}")
    print()
    res = {}
    for w, name in (("lo", "below 64K"), ("hi", "above 64K")):
        print(f"  --- pointer {name}")
        for k in ("creat", "connect", "recv"):
            v = field(f"{w}_{k}")
            if v is not None:
                print(f"      {k:9} {v}")
        for k in ("buf", "txt"):
            key = f"{w}_{k}"
            if key in kv:
                print(f"      {k:9} {kv[key]}")
        # changed=1 of 16 is not a near miss if the probe passed the same
        # address on every call - all sixteen reads land on byte 0. What
        # decides it is the VALUE: &34 is "4", the sixteenth character of
        # PTRTEST-MARKER-42, so the byte that arrived is the byte that was
        # predicted, at an address the ARM chose.
        buf = kv.get(f"{w}_buf", "").split()
        if buf:
            MARKER = "PTRTEST-MARKER-42\n"
            n = field(f"{w}_recv") or ""
            m = re.search(r"reported=(\d+)", n)
            if m and 0 < int(m.group(1)) <= len(MARKER):
                want = MARKER[int(m.group(1)) - 1]
                try:
                    got = chr(int(buf[0], 16))
                except ValueError:
                    got = None
                if got == want:
                    print(f"      byte 0 is {got!r}, which is character "
                          f"{m.group(1)} of the marker - predicted, not a fluke")
                elif got is not None:
                    print(f"      byte 0 is {got!r}, expected {want!r}")
        res[w] = (field(f"{w}_out"), field(f"{w}_in"))
        print(f"      out={res[w][0]}  in={res[w][1]}")
        print()

    lo, hi = res.get("lo", (None, None)), res.get("hi", (None, None))
    print("  VERDICT")
    if lo[0] == "YES" and hi[0] == "NO":
        print("    The pointer is TRUNCATED. The same sockaddr connects from")
        print("    below 64K and does not from above it, so the module or the")
        print("    tube glue is taking 16 bits of a 32-bit ARM address.")
        print("    5.5c holds on copro 15 as long as every buffer stays under")
        print("    64K - which BASIC's own PAGE at &8F00 gives for free until")
        print("    something DIMs past it. That is a constraint to write down,")
        print("    not a BEEBNET.")
    elif lo[0] == "YES" and hi[0] == "YES":
        print("    Full 32-bit pointers are honoured, and PTRTEST's ptr_out=NO")
        print("    was something else entirely - re-read the listener.")
    elif lo[0] == "NO" and hi[0] == "NO":
        print("    Neither address connected, so the ADDRESS IS NOT THE ISSUE.")
        print("    PTRTEST's ptr_out=NO cannot be read as a pointer result at")
        print("    all. Check the listener is up on the port the test uses and")
        print("    that the module has a link.")
    elif lo[0] is None and hi[0] is None:
        print("    Neither half ran. Look at the creat lines above.")
    else:
        print(f"    lo out={lo[0]} in={lo[1]}, hi out={hi[0]} in={hi[1]}")

    if lo[1] == "YES":
        print()
        print("    INWARD works below 64K: the module wrote ARM memory, so")
        print("    PTERM can call OSWORD C0 direct and 8 Step 1 stays cancelled.")
    elif lo[1] == "NO":
        print()
        print("    INWARD failed below 64K even though connect worked. recv")
        print("    reported bytes and the buffer stayed at &55, so reads do not")
        print("    reach ARM memory and 8 Step 1 has to be un-cancelled for the")
        print("    receive path.")
    if inc:
        print("  (no [end] marker - partial)")

def main():
    args = [a for a in sys.argv[1:]]
    fontout = None
    if "--font" in args:
        i = args.index("--font")
        fontout = args[i + 1]
        del args[i:i + 2]
    paths = args or [os.path.join(SHARE, n)
                     for n in ("RESPAL", "RESPAL2", "RESFONT", "RESBENC", "RESSAVE",
                               "RESVDU", "RESPTR", "RESPTR2")]
    found = False
    for p in paths:
        if not os.path.exists(p):
            print(f"=== {p} — not found (has the probe been run?)")
            continue
        found = True
        base = os.path.basename(p).upper()
        if "PAL" in base:
            do_pal(p)
        elif "FONT" in base:
            do_font(p, fontout)
        elif "BENC" in base:
            do_bench(p)
        elif "SAVE" in base:
            do_save(p)
        elif "PTR2" in base:
            do_ptr2(p)
        elif "PTR" in base:
            do_ptr(p)
        elif "VDU" in base:
            do_vdu(p)
        else:
            print(f"=== {p} — unrecognised name, expected RESPAL/RESFONT/RESBENC")
        print()
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
