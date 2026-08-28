# The glyphs, and where each one came from

FBVDU blits its own font (`docs/fbvdu.md`), so the set of characters it can
draw is a table we own rather than something the machine dictates. This is
what is in that table, how each family got there, and what is still missing.

## The font table

| slots | what | how |
|---|---|---|
| 0-255 | the Pi VDU driver's own font | harvested off the framebuffer, `test/fbfont.bas` |
| 256-275 | 20 characters btop asked for | drawn by hand, 2026-08-28 |
| 276-302 | 27 Nerd Font icons | rasterised from a real Nerd Font, 2026-08-28 |
| 303 | the neutral mark for an unknown private-use codepoint | drawn |
| 512-767 | the whole braille plane | generated |
| 768-799 | the block elements U+2580-259F | generated |
| 800-828 | double box drawing U+2550-256C | generated off the machine, `tools/mkdbox.py` |
| 832-1087 | octants U+1CD00-1CDE5 | generated |
| 1088-1151 | sextants U+1FB00-1FB3B | generated |
| 1152-1247 | Latin-1 U+00A0-00FF | 55 composed at boot, 32 from `tools/mklatin.py` |
| 1248-1327 | legacy diagonals and eighths U+1FB3C-1FB8B | `tools/mklegacy.py` |
| 1328-1352 | the remaining odds and ends | `tools/mksym.py` |

The cell's glyph field is 12 bits, so the table can hold 4,096. `DIM font%
800*ch%-1` is what is actually allocated.

Three functions map a codepoint to a slot, in a chain: `FNv_uni` (the DEC
special-graphics set, which the harvested font already contains), `FNv_uni2`
(the hand-drawn singles), `FNv_uni3` (the generated families and the icon
lookup). The chain exists because line numbers ran out, not because the split
means anything - see the last section.

## The Nerd Font icons, and why they are different

**Found by measuring, not by reading.** The report was that `fastfetch` over
SSH to `archbox` drew boxes instead of a colour palette. The Arch logo turned out
not to be the problem at all - it is drawn in ASCII. `archbox`'s fastfetch config
is written round Nerd Font icons, and **21 of them are the colour palette row
by itself**: one `U+F192` per colour.

A Nerd Font icon is a **private-use** codepoint. U+F192 is not "a dotted
circle" in Unicode; it is nothing in Unicode. It means whatever the font in
front of you says it means. So there is only one correct source for these
shapes: **the font the far machine actually renders them with**. These were
rasterised from `MesloLGS Nerd Font Mono` - the font on `archbox` - and scaled
into 8x8 by `tools/mkicons.py`. Point that tool at a different Nerd Font and
the icons change to match that machine.

That also settles what to do with the ones not in the table. An unmapped
**private** codepoint gets a neutral mark rather than `?`, because there is
nothing it ought to have been. An unmapped **real** codepoint still gets `?`,
which is an honest report of a gap. The two cases are not the same kind of
missing.

The four powerline dividers are stretched to fill the cell rather than fitted
to their aspect ratio: powerline draws them edge to edge, and a divider with a
gap either side is not a divider.

### The 27, as the Beeb draws them

      U+0E0B0     U+0E0B1     U+0E0B2     U+0E0B3   
      ##......    ##......    ......##    ......##  
      ###.....    ..##....    .....###    ....##..  
      #####...    ....##..    ...#####    ..##....  
      #######.    ......#.    .#######    .#......  
      #######.    ......#.    .#######    .#......  
      #####...    ....#...    ...#####    ..##....  
      ###.....    ..##....    .....###    ....##..  
      ##......    ##......    ......##    ......##  
      pl-left_ha  pl-left_so  pl-right_h  pl-right_s

      U+0E623     U+0E795     U+0EBC6     U+0EF70   
      ........    ########    ...##...    ##..##..  
      ...##...    ########    ..###...    ###.#...  
      ...##...    ##.#####    ..#.#...    .#######  
      ########    ##.#####    ....##..    ...#####  
      .######.    ########    .#...#..    ..####..  
      ..####..    ########    .#...#..    .######.  
      ..####..    ########    #.#.....    ###..###  
      ..#..#..    ........    ..#.#...    ##....#.  
      seti-favic  dev-termin  cod-termin  fa-screwdr

      U+0F013     U+0F028     U+0F031     U+0F192   
      ...##...    ........    ...##...    ..####..  
      .######.    ...#..#.    ...##...    .#....#.  
      ########    ..##..##    ...##...    #......#  
      .##..##.    ####.###    ..####..    #..##..#  
      .##..##.    ####.###    ..#..#..    #..##..#  
      ########    ..##..##    ..####..    #......#  
      .######.    ...#..#.    .##..##.    .#....#.  
      ...##...    ........    ###..###    ..####..  
      fa-gear     fa-volume_  fa-font     fa-dot_cir

      U+0F488     U+0F489     U+F003B     U+F0150   
      ########    ########    ##.##.##    ..####..  
      #####..#    #......#    ##.##.##    .#....#.  
      ########    #.#....#    ........    #......#  
      #......#    #.##...#    ##.##.##    #..#...#  
      #......#    #.#.##.#    ##.##.##    #...#..#  
      #......#    #......#    ........    #......#  
      ########    ########    ##.##.##    .#....#.  
      ........    ........    ##.##.##    ..####..  
      oct-browse  oct-termin  md-apps     md-clock_o

      U+F027C     U+F0322     U+F0379     U+F03D6   
      ######..    ........    ########    ...##...  
      #######.    .######.    #......#    .###.##.  
      ......#.    .......#    #......#    ####..##  
      ..#####.    .......#    #......#    #.######  
      ..##....    .#....#.    #......#    #..####.  
      ..##....    ########    ########    ##..#.##  
      ..##....    ........    ...##...    .######.  
      ..##....    ........    ........    ...##...  
      md-format_  md-laptop   md-monitor  md-package

      U+F0443     U+F04E1     U+F075A     U+F0960   
      ........    ........    .....###    ...####.  
      ........    ........    ..######    ..######  
      .#......    ...#####    ..#....#    ..##..##  
      ########    ......#.    ..#....#    ..######  
      ##......    .#......    ..#..###    ...####.  
      ........    #####...    ###..###    ########  
      ........    .#......    ###..###    ########  
      ........    ........    ###.....    ########  
      md-ray_sta  md-swap_ho  md-music    md-disc_pl

      U+F0ED1     U+F0EE0     U+F0F86   
      ........    ..####..    ..####..  
      ######..    .######.    .#....#.  
      ##.#.###    ########    ..##...#  
      ##.#####    ##.#..##    #.###..#  
      ##.#.###    ##..#.##    #..##..#  
      ######..    #######.    #......#  
      ........    .######.    .#....#.  
      ........    ..###...    ........  
      md-video_3  md-cpu_64_  md-speedom

## The block elements: the one family that is free

All 32 of U+2580-259F are **exact** at 8x8. The eighths land on pixel
boundaries in both directions, so `▁▂▃▄▅▆▇█` are the real characters and not
an approximation of them, and the quadrants are literal 4x4 corners. Nothing
is drawn or stored: 22 lines of arithmetic produce the lot.

They were checked against shapes computed independently from the Unicode
definitions - 29 of the 32, the other three being the shades, which
`FNv_uni2` and the DEC set catch first and draw better than a rule would.

## Double box drawing, and one rule that produces all 29

598 occurrences across fastfetch's builtin logos, the largest gap left after
the icons. **The geometry is this font's own, not a convention imported from
somewhere else.** `src/fbvdu.bas`'s DEC `DATA` puts a single horizontal on row
3 and a single vertical on columns 3-4, so the doubles straddle them: rows 2
and 4, columns 1-2 and 5-6. Straddling is the whole point — the single line's
position is the double's gap, so the two sets align wherever they meet.

**The break rule was measured, because reasoning about it gives the wrong
answer.** Rendered at 24x24 from DejaVu Sans Mono:

- `╫` — a single horizontal crosses a double vertical *unbroken*.
- `╬` — two doubles crossing do **not**; the centre is open.
- `╠` — the left stroke runs whole; only the right one is interrupted.
- `╦` — the top line is whole; only the lower one breaks.

All four fall out of one sentence: **a stroke breaks iff a perpendicular arm
exists on that stroke's own inner side, and both structures are double.** An
arm otherwise runs clear across, or caps the perpendicular where it ends.

My first two attempts at this were wrong in ways the picture caught at once:
`╢`'s horizontal crossed both strokes when it should stop at the near one, and
a broken stroke stopped at the near edge of its neighbour rather than the far
edge. Neither was visible in the rule as stated; both were obvious on screen.

### Stored, not generated — a judgement, not a habit

Braille and the block elements are built on the Beeb because their rule is one
line of arithmetic. This one is four cases with three conditions between them,
and a mistake would surface as a wrong shape on a monitor in another room. So
the rule lives in `tools/mkdbox.py`, where a test runs against it, and the
machine reads 232 bytes it cannot get wrong.

**Confirmed on the hardware**, `results/RESGLAS_0828_dbox`: `tools/glyphtest.sh`
over SSH to `archbox`, 68,887 bytes, 41,928 cells painted through 202 flushes and
495 scrolls, `stale_cells=0` and `short=0`. Every one of the 29, and the 32
block elements beside them, matched the model.

**The test is what makes this safe.** Every glyph's four edges must carry
exactly what its arm types declare — a single arm leaves row 3 at the edge, a
double leaves rows 2 and 4. If that holds for all 29, then *any* two glyphs
with matching arms join, and no pair has to be checked separately. It holds,
checked both in the tool and re-read from the `DATA` now in the source.

```
  ═ 2550   ║ 2551   ╒ 2552   ╓ 2553   ╔ 2554   ╕ 2555 
  ........  .##..##.  ........  ........  ........  ........
  ........  .##..##.  ........  ........  ........  ........
  ########  .##..##.  ...#####  ........  .#######  #####...
  ........  .##..##.  ...##...  .#######  .##.....  ...##...
  ########  .##..##.  ...#####  .##..##.  .##..###  #####...
  ........  .##..##.  ...##...  .##..##.  .##..##.  ...##...
  ........  .##..##.  ...##...  .##..##.  .##..##.  ...##...
  ........  .##..##.  ...##...  .##..##.  .##..##.  ...##...

  ╖ 2556   ╗ 2557   ╘ 2558   ╙ 2559   ╚ 255A   ╛ 255B 
  ........  ........  ...##...  .##..##.  .##..##.  ...##...
  ........  ........  ...##...  .##..##.  .##..##.  ...##...
  ........  #######.  ...#####  .##..##.  .##..###  #####...
  #######.  .....##.  ...##...  .#######  .##.....  ...##...
  .##..##.  ###..##.  ...#####  ........  .#######  #####...
  .##..##.  .##..##.  ........  ........  ........  ........
  .##..##.  .##..##.  ........  ........  ........  ........
  .##..##.  .##..##.  ........  ........  ........  ........

  ╜ 255C   ╝ 255D   ╞ 255E   ╟ 255F   ╠ 2560   ╡ 2561 
  .##..##.  .##..##.  ...##...  .##..##.  .##..##.  ...##...
  .##..##.  .##..##.  ...##...  .##..##.  .##..##.  ...##...
  .##..##.  ###..##.  ...#####  .##..##.  .##..###  #####...
  #######.  .....##.  ...##...  .##..###  .##.....  ...##...
  ........  #######.  ...#####  .##..##.  .##..###  #####...
  ........  ........  ...##...  .##..##.  .##..##.  ...##...
  ........  ........  ...##...  .##..##.  .##..##.  ...##...
  ........  ........  ...##...  .##..##.  .##..##.  ...##...

  ╢ 2562   ╣ 2563   ╤ 2564   ╥ 2565   ╦ 2566   ╧ 2567 
  .##..##.  .##..##.  ........  ........  ........  ...##...
  .##..##.  .##..##.  ........  ........  ........  ...##...
  .##..##.  ###..##.  ########  ........  ########  ########
  ###..##.  .....##.  ........  ########  ........  ........
  .##..##.  ###..##.  ########  .##..##.  ###..###  ########
  .##..##.  .##..##.  ...##...  .##..##.  .##..##.  ........
  .##..##.  .##..##.  ...##...  .##..##.  .##..##.  ........
  .##..##.  .##..##.  ...##...  .##..##.  .##..##.  ........

  ╨ 2568   ╩ 2569   ╪ 256A   ╫ 256B   ╬ 256C 
  .##..##.  .##..##.  ...##...  .##..##.  .##..##.
  .##..##.  .##..##.  ...##...  .##..##.  .##..##.
  .##..##.  ###..###  ########  .##..##.  ###..###
  ########  ........  ...##...  ########  ........
  ........  ########  ########  .##..##.  ###..###
  ........  ........  ...##...  .##..##.  .##..##.
  ........  ........  ...##...  .##..##.  .##..##.
  ........  ........  ...##...  .##..##.  .##..##.
```

## What this covers

`fastfetch --print-logos` prints every builtin distro logo, which is as good a
sample of what a fetch tool will ever send as exists. Across all of them,
14,041 non-ASCII characters:

| | unmapped occurrences |
|---|---|
| at the start of 2026-08-28 | 2,027 |
| after the icons and block elements | 1,122 |
| after double box drawing | 524 |
| after sextants and octants | 401 |
| after Latin-1 | 185 |
| after the diagonals and the odds and ends | **0** |

**14,041 of 14,041.** Every non-ASCII character in every one of the 539
builtin logos now has a glyph.

And on the machine the report came from, `captures/FFARCH`, **every character
archbox's fastfetch sends now has a glyph** - 22 distinct, 87 occurrences, none
left over.

**Confirmed on the hardware, 2026-08-28**, `results/RESGLAS_0828_icons` and
`results/RESPROF_0828_icons`: 256,555 bytes over SSH to `archbox`, 30,531 cells
painted through 146 flushes, `stale_cells=0` and `short=0`. The glass check
compares every cell against what the model says should be there, so the icons
are not merely present - they are the right pixels in the right places under
load. 62,592 bytes/sec to the screen at a compression floor of 22.1x.

## The four families that finished it

**Sextants and octants** are braille with a different grid, 2x3 and 2x4, and
the same trick: the shape is the codepoint. What differs is that Unicode does
not encode combinations that already have a character of their own, so the
codepoints run over the masks with 26 of 256 and 4 of 64 missing. Walking the
masks and skipping those reproduces the codepoint order exactly - derived from
unicodedata's own names for all 290, then every generated cell checked back
against the dots its name asks for. The excluded masks turn out to be exactly
what this table already draws elsewhere, which is the sign the derivation is
right rather than merely the right size.

**Latin-1 is mostly not drawn at all.** Fifty-five of the ninety-six are a
letter the harvested font already has plus a mark, so the machine composes them
at boot from its own font and an accented letter matches the unaccented one
beside it. The cell metrics make it possible, and they were measured off
`results/RESFONT`: lowercase sits on rows 2-6 leaving two rows for the accent,
capitals fill 0-6 so they drop a row and take a one-row mark, `i` gives up its
dot to the accent, and row 7 is free on both for the cedilla.

**The legacy diagonals had no source to copy.** No font on the build machine
carries U+1FB3C-1FB8B - not DejaVu, FreeMono, Noto, nor the Nerd Font off archbox.
Unicode's names were enough: each of the 80 states its own geometry, and

    LOWER LEFT BLOCK DIAGONAL UPPER LEFT TO LOWER CENTRE

names a line between two boundary points and the corner whose side is filled.
The ten point names divide the side edges into thirds - the sextant grid again.
A line between two boundary points cuts the cell in two; fill the half holding
the named corner. That is 44 of them; the triangles and the eighths state their
shape just as plainly.

**The last two dozen are a list, not a family**, and are rasterised, except
seven whose meaning lives in a single row that a downscale smears: the scan
lines, the heavy rules, and the two heavy-to-light box halves, which have to
land on row 3 to meet the single set.

## What is still missing

Nothing that anything measured has asked for. The next gap will be found the
way all of these were - by capturing what a real machine actually sends.

## The engine ran out of line numbers, and was reflowed

`src/fbvdu.bas` holds 1000-9990 and a driver holds 10-990 and 10000 up,
because on the Beeb they are `*EXEC`d separately and BASIC files them by
number. At **step 5** that band holds 1,799 lines, and adding the icons took
the engine to exactly 9990 with none left.

It was reflowed the same day at **step 2**:

```
tools/basrenum.py src/fbvdu.bas --bands 1000:1000:2
```

| | before | after |
|---|---|---|
| engine ends at | 9990 | 4686 |
| capacity in the band | 1,799 lines | 4,496 |
| spare | **0** | **2,652** |

**It costs nothing.** A tokenised line stores its number in two bytes whatever
the number is, so `PTERMRUN` is 121,578 bytes before and after - the same file
size, the same load time, the same Tube exposure. Only the source changed.

**Confirmed on the hardware**, `results/RESGLAS_0828_reflow`: every line number
in the engine moved, and the machine did not notice. 241,530 bytes, 20,058
cells, `stale_cells=0`, `short=0`, 67,009 bytes/sec to the screen at a
compression floor of 25.6x.

The renumber was checked rather than trusted: 1,844 lines in, 1,844 out, the
text of every line identical except the five `RESTORE`s, and each of those
still resolving to the same line of code it named before. The five line numbers
that appear in **prose** - `REM` comments naming another line - are not
references the tool can see, and were rewritten by hand against the same map.

`tools/fbbuild.sh` prints the free count on every build, and **measures the
step from the file** rather than assuming 5, so the next reflow does not
quietly turn that line into a lie.

### The hazard the reflow left for its own commit

`PROCv_glyphs` did `RESTORE` at a line **238 lines above** the `DATA` it wanted,
and `PROCv_pal` at one 22 lines above its own. Both worked, and both worked *by
accident*: BASIC reads from the first `DATA` at or after the line named, so
each depended on nothing else defining `DATA` in the gap. The glyph work added
three `DATA` blocks to this file and got away with it only because they landed
after the font table rather than before it.

Both now name their `DATA` line, which is the same behaviour with the accident
removed. `baslint.py` gained the check that finds it:

```
src/fbvdu.bas:908: RESTORE 3594 does not name a DATA line - it reads from
the next DATA in the file, wherever that ends up
```

It found exactly these two across every listing in the repository, and nothing
else. It was kept out of the renumber commit because a renumber has to be
provably behaviour-preserving, and this is a behaviour change - a very small
one, but the point of the proof is that it covers everything.
