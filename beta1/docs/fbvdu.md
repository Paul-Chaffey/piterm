# FBVDU — a terminal VDU that owns the Pi framebuffer

**Subproject.** Separate from `BEEBTERM`, which stays working and untouched
until Phase 5. The parent document is `specification.md`; this file is
authoritative for the display engine only.

## 1. Why

`BEEBTERM` renders through the VDU driver, and **every rendering defect found on
2026-08-19 came from that driver's semantics, not from the terminal's logic**
(§2.3a). The driver has no pending wrap, no second screen buffer, no insert or
delete line, ignores `VDU 23,16`, and scrolls the screen if the bottom-right
cell is written. The client's workarounds — a sacrificed bottom-right cell, one
swallowed `LF` after a wrap, `VDU 28` windows standing in for scrolling regions,
an alternate screen that clears instead of restoring — are all compensation for
a driver that was never meant to be a VT.

§2.3a removed the reason to live with it: `OS_ReadVduVariables` 148/150 expose
the framebuffer address, copro 15 runs bare metal **on the Pi**, and `fbtest`
confirmed on hardware that a poked byte becomes a pixel — ~4300 writes in under
10 ms.

So FBVDU takes the byte stream and produces the pixels. VT semantics are correct
**by construction** rather than emulated on top of a driver that disagrees.

## 2. Decisions

| | |
|---|---|
| Scope | Bytes in, pixels out: UTF-8 decode, VT parser, cell model, blitter. Replies come back out for the client to send. |
| Target | Copro 15, ARM native, BBC BASIC V, MODE 21. Reached with `*ARMBASIC`, routed with `*PIVDU 2` **before** `MODE`. |
| Geometry | **80×64 on an 8×8 cell**, settled 2026-08-20. `FBBENCH` measured 80×64 and 80×32 identical, so it was a legibility call, taken on the glass. Cell size stays parameterised. |
| Colour | **Settled 2026-08-20 by `FBPAL2`: exact `xterm-256color`.** All 256 palette entries are individually programmable, so no nearest-colour reduction is written. |
| Font | **Confirmed 2026-08-20:** harvested off the driver at startup — 101 glyphs in 1 cs. Never transported. |
| Portability | No 6502 backend and no abstraction for one. A 6502 co-processor cannot reach the framebuffer at all — 64K of address space, and the framebuffer is on the Pi behind the OSWRCH redirector. The port path is a **purpose-built co-processor core**, which is why §4 below is written as a contract rather than left implicit in the BASIC. |
| Language | BASIC IV safe except the `SYS` and framebuffer procedures, which are guarded by `fb%<>0` and never entered under b-em. BBC BASIC raises syntax errors on **execution**, not on entry, so an untaken `SYS` line is harmless — this is what keeps the offline test loop alive. |

## 3. Shape

```
socket bytes ─▶ PROCv_write(c%) ─▶ UTF-8 ─▶ VT state machine ─▶ cell model
                                                                    │
                            PROCv_flush ◀── damage ◀────────────────┘
                                 │
                                 └─▶ blitter ─▶ framebuffer
```

**Model updates and rendering are decoupled, and everything else rests on it.**
A scroll in the model is an index change, not pixels. The client applies a whole
drain's worth of bytes and calls `PROCv_flush` **once**: twenty scrolled lines in
one drain cost one repaint, not twenty. Without the split, line-at-a-time output
at §5.5c's 3082 bytes/sec would demand ~38 full repaints a second and BASIC could
never keep up. With it, the render rate is bounded by drain frequency — a few a
second — and `FBBENCH` only has to clear that bar.

## 4. Contract

The state a native implementation must carry, and the entry points it must
offer. Flat memory blocks throughout, so the layout transliterates to C arrays
with no reinterpretation.

### 4.1 Blocks

| Block | Size | Contents |
|---|---|---|
| `font%` | 256 × cellh | one byte per glyph row, **bit 7 is the leftmost pixel** (confirmed §6.2) |
| `scr%` | cols × rows × 4 | one word per cell — see the layout below |
| `alt%` | as `scr%` | the alternate screen — a **real** second buffer, so `?1049l` restores, which is impossible today (§9.3) |
| `shd%` | cols × rows × 4 | shadow: what was last blitted. Flush blits only cells that differ |
| `xp%` | 16 words | nibble → four pixel bytes, for the current fg/bg pair |

**The cell word**, revised in Phase 1 from the first sketch above:

```
byte 0   glyph, low 8 bits
byte 1   bits 0-3 glyph high nibble; bits 4-7 flags
byte 2   foreground, an xterm-256 index
byte 3   background, an xterm-256 index

flags    1 reverse   2 underline   4 bold   8 strike
```

The separate `flg%` array is gone. 4096 glyphs is far more than the terminal
will ever map, and folding the flags in buys a **single-word damage compare** in
the flush — which runs over every cell whether anything changed or not, so its
cost is paid on every frame.

Writing a cell is four byte stores, never a packed word: shifting a background
above 127 into the top of a word overflows BASIC's signed integer and raises
*Number too big*.

### 4.2 Scalars

Cursor `cx% cy%`; pending-wrap flag; scroll region `top% bot%` (**zero-based and
inclusive**); saved cursor (DECSC); the current SGR attribute `sf% sb% sfl%`;
tab stops; and the mode flags DECAWM, DECCKM, DECOM, insert, cursor visible,
bracketed paste, alternate-screen-active.

`sf% sb%` are not only what new text is written in — **every erase in the engine
paints them**. That is background colour erase, what xterm advertises as `bce`,
and it is why clearing to end of line inside a coloured panel leaves the colour
behind instead of a black gap.

### 4.2a The three modes

The engine runs in one of three, chosen by the driver before `PROCv_boot`:

| `sim%` | `glass%` | |
|---|---|---|
| FALSE | TRUE | **hardware.** `OS_ReadVduVariables` for the framebuffer, font harvested off the driver, palette programmed |
| TRUE | TRUE | **simulated glass.** A DIMmed block stands in for the framebuffer and the font is loaded from `PIFONT`. Every line between — blit, damage compare, flush, scroll, cursor — is the same code on the same path |
| TRUE | FALSE | **model only.** No framebuffer, no font, no blitter. The flush still tracks and reports damage, so it counts exactly what a rendering run would have painted |

Model-only is not an economy, it is what makes phase 3 possible at all: an 80×24
model is 15K, and an 80×24 framebuffer at 8×8 would be 120K with nowhere to put
it.

### 4.3 Entry points

| | |
|---|---|
| `PROCv_init` | mode, VDU variables, font harvest, palette, buffers |
| `PROCv_write(c%)` | one byte of the stream in |
| `FNv_flush` | render everything damaged since the last flush; **returns the number of cells painted**, which is what makes the tests measurable |
| `FNv_damage(t%,b%)` | how many cells in rows `t%`–`b%` differ from the glass. Lets a test assert *where* damage is, not just how much |
| `PROCv_sync` | declare that the glass already shows the model, without painting. Correct **only** straight after a wipe |
| `PROCv_scroll(t%,b%,n%,f%,b%)` | move rows up, moving pixels, model and shadow together. `t%=b%` is legal and clears the one row |
| `PROCv_sdown(t%,b%,n%,f%,b%)` | the same, downwards |
| `PROCv_region(t%,b%)` | DECSTBM. An empty or inverted region resets to the whole screen, which is what a reset sequence relies on |
| `PROCv_ich(n%) PROCv_dch(n%) PROCv_ech(n%)` | insert, delete and erase characters on the cursor row |
| `PROCv_il(n%) PROCv_dl(n%)` | insert and delete lines, from the cursor row to the **foot of the region**, and nothing at all with the cursor outside it |
| `PROCv_su(n%) PROCv_sd(n%)` | scroll the region, leaving the cursor alone |
| `PROCv_ed(m%) PROCv_el(m%)` | erase display and line, 0/1/2 (and 3 as 2) |
| `PROCv_ind PROCv_ri` | index and reverse index: move a row, scrolling only when already against the edge of the region |
| `FNv_reply` | bytes the far end must be sent — DSR, DA — and cleared by reading |
| `FNv_mode(n%)` | current mode flags, so the keyboard layer encodes cursor keys per DECCKM and brackets pastes |
| `FNv_cell(x%,y%)` | read the screen back, one cell word. Free here, impossible through the driver |

### 4.4 The blitter

`xp%` holds one word per nibble: the four pixel bytes that nibble expands to for
the current foreground and background. A glyph row is then **two lookups and two
word stores**:

```
!a%    = xp%!((b% DIV 16)*4)
a%!4   = xp%!((b% AND 15)*4)
```

A colour change rebuilds `xp%` — sixteen word writes — so colour stays as free
as §5.5d measured it under the driver, with no per-attribute cache.

Byte order within the word is **settled by `FBFONT`, not assumed**: mirrored
glyphs on screen mean the leftmost pixel is the high byte and `PROCxp` fills the
four bytes the other way round.

## 4.5 Phase 1 — the renderer, built

`src/fbvdu.bas`. Model in memory, pixels on the glass, nothing in between: no VDU
driver, no OSWRCH, no GCOL. Init reads the VDU variables and **checks the
geometry** rather than assuming it — a pitch too narrow for the cell grid would
write off the end of every row, and the first symptom would be a diagonal smear
rather than an error. Then it harvests the font, sets all 256 palette entries,
wipes the glass and syncs the shadow.

Attributes are **drawn, not stored in the font**: a terminal applies underline
and strike to any glyph, and since nibble 15 expands to four bytes of foreground,
each is two word stores after the glyph. Bold is the bright half of the ANSI 16.

The **cursor is never in the model**. It is drawn by re-blitting its cell with
the colours swapped and erased by blitting it normally, so it cannot be scrolled,
saved, or read back by mistake — it is a property of the display, which is what a
cursor is.

### Simulation mode — the engine runs under b-em

`sim%=TRUE` points the renderer at a `DIM`med block instead of the framebuffer,
loads a harvested `PIFONT` file instead of harvesting, and dumps the result as
characters. **Everything between — the cell blit, the damage compare, the flush,
the scroll, the cursor, the attributes — is the same code on the same path.**

So the engine is exercised on a 6502 under the emulator in seconds. §2.3a said
the edit-test loop was the thing worth protecting, and this is what protects it
for Phase 2, where the VT semantics arrive and the bugs will be in logic rather
than in pixels. It needs a co-processor (`tools/beeb-test.sh <file> 200 -t3`)
because the simulated framebuffer is `cols × cw × rows × ch` bytes.

Verified there, 2026-08-20, at 9×3:

- glyphs render correctly from the harvested font, including the box pieces
- bold turns foreground 7 into 15; reverse, underline and strike all land on the
  right rows
- the cursor draws as a solid inverted block and erases cleanly
- a page of text costs **8 cells painted, not 64** — damage tracking skips every
  blank
- **the scroll invariant holds**: after a scroll, damage above the exposed row is
  **zero**

That last check was wrong on its first writing, and the harness caught it in
seconds rather than on the hardware. It asserted that the exposed row costs
`cols%` cells; the run reported 11 of 16. The old bottom row was
`row 3 abcdefg`, which contains two spaces — and a space in the same colours is
byte-identical to a blank cell, so two of those cells rightly needed no repaint.
Counting damage **by row** says what was meant; counting it in total does not.

### Phase 1 on hardware, 2026-08-20

Copro 15, MODE 21, the full 80×64 grid:

```
full flush        6 cs    848 cells painted
one cell changed  1 cs     31 cells painted
attribute page    4 cs    938 cells painted
ten scrolls      59 cs    0 repainted afterwards
```

**It works, and the scroll invariant holds on the real framebuffer.** The
one-cell figure is exact rather than approximate: the line written was
`one cell changed, then flushed again` — 36 characters containing 5 spaces, and a
space in the same colours is byte-identical to a blank, so 31 cells is precisely
right.

**But the renderer is four times slower per cell than the bare blit.** 14,133
cells/sec here against `FBBENCH`'s 56,889 (§6.3). A flush time on its own hides
that — 848 cells in 6 cs looks like 17 repaints a second, but it repainted 848
cells, not a screen. Extrapolated honestly, a full 5120-cell repaint is **36 cs,
2.8 a second**: still above the 2–3 the decoupled flush needs, but the margin is
thin where §6.3 suggested it was fivefold. `fbres.py` now reports cells/sec and
the extrapolated worst case rather than the flattering figure.

Where the difference goes is **BBC BASIC's procedure call**: `PROCv_cell` declared
nine `LOCAL` variables, pushed and popped for every cell on the screen. Two
changes in response, both measured against the simulation for identical output:

- **The nine locals became module-level scratch** (`va%`–`vr%`), documented as
  belonging to `PROCv_cell` alone. Safe because it is not recursive and is their
  only user, and because `PROCv_ink` — the one thing it calls — declares its own
  `LOCAL`s, which BASIC restores on exit.
- **A fast path for blanks.** An unadorned space needs no font lookup at all:
  nibble 0 expands to four bytes of background, so the cell is sixteen stores of
  one value. It is the commonest cell on any terminal screen — every erase and
  every scroll makes rows of them.

**Re-measured on hardware 2026-08-20: 16,960 cells/sec**, up from 14,133 — a
fifth faster, and the worst-case full repaint drops from 36 cs to **30 cs, 3.3 a
second**. Modest rather than dramatic, but free, and it confirms where the cost
lies.

```
full flush        5 cs    848 cells painted
one cell changed  1 cs     31 cells painted
attribute page    3 cs    988 cells painted
ten scrolls      59 cs
```

**All six visual checks passed.** The palette strip shows 256 different patches,
the 16 ANSI lines are 16 colours, the box pieces close into a rectangle, the
cursor block is there, bold/reverse/underline/strike are all right, and the
coloured pairs are legible. **Phase 1 is complete.**

### Why `repaint_after` went from 0 to 610

It looked like a regression and is the renderer behaving correctly. The visual
prompts are written on the bottom row, and **nothing clears the exposed rows as
the screen moves**: each scroll copies row 63 up to row 62 and leaves row 63
alone, so ten successive scrolls replicate the prompt down the whole exposed
band. The shadow moved identically, so it still matches the glass; the model says
blank; the flush repaints exactly that band. Previously those rows were empty,
hence zero.

That was reasoned out rather than measured, so the hardware test now checks the
invariant itself rather than only the simulation doing so — `scroll10_above` must
be **0**, and `scroll10_exposed` is expected to be large.

### The visual checks

A screen that looks right is not a measurement — but a measurement is not a
screen that looks right either, and the first hardware run produced timings with
no record of whether anything was legible. The self test now asks six questions
and writes the answers to `RESVDU`, the way `FBFONT` records `shapes=`:

| | |
|---|---|
| `p1_palette` | are all 256 patches different |
| `p1_ansi` | are the 16 ANSI text lines 16 different colours |
| `p1_box` | do the box pieces close into a rectangle |
| `p1_cursor` | is the cursor block visible |
| `p2_attr` | bold, reverse, underline and strike all correct |
| `p2_ink` | are the coloured pairs legible |

They are asked **through the engine**, not with `PRINT`. Output is routed to the
Pi framebuffer, so a `PRINT` lands on cells the model believes are blank — and
the shadow then agrees they need no painting, so the prompt would sit there
through the following page and the flush would never take it away. Anything that
appears on this screen has to arrive through the model, or it cannot be removed.
That constraint applies to every future part of this subproject, which is why it
is written down here rather than just worked around.

`tools/basstrip.py` strips whole `REM` lines for memory-bound targets. The
comments here are heavy on purpose — they carry the reasoning, which is the
expensive part to reconstruct — but they are also tokenised bytes on a machine
with 30K of BASIC space, and the engine stopped fitting on an emulated 6502
co-processor while it was still being written. The repository keeps the
commented source; the emulator runs a stripped build, **50% smaller**: 26,724
bytes down to 13,472. Line numbers of surviving lines are never changed, so
nothing that refers to a line number can break.

`tools/baslint.py` checks the sources for what BBC BASIC will not report until
the offending line executes: a `PROC` called but never defined, `FOR`/`NEXT`
unbalanced inside a procedure, a `DEF PROC` with no way out, lines over the
238-byte input buffer, and BASIC V keywords in a file meant to stay BASIC IV
safe.

## 4.6 Phase 2a — the model, built

**31 of 31 checks pass under b-em, 2026-08-20**, model-only, in a few seconds
and without touching the hardware.

The editing operations a TUI uses on every frame and the BBC VDU driver has none
of — IL, DL, ICH, DCH, ECH, ED, EL, SU, SD, the scrolling region, index and
reverse index — are index arithmetic over `scr%`. That is the whole argument for
owning the cell model rather than driving a driver, and `test/fbmodel.bas` is
where the corners get checked: insertions longer than the line, a region scrolled
by its own height, IL with the cursor on the last row of the region, IL with the
cursor outside it, `bce` on both an erase and the row a scroll exposes.

Each check reads column 0 of every row back as one string, so an assertion says
*where the rows ended up* rather than how many cells changed.

### The engine and its driver are now two files

`src/fbvdu.bas` holds lines 1000–9990 and **defines procedures only**. A driver
supplies 10–990 — the geometry and the entry point — and 10000+ for its own
procedures. On the Beeb they are loaded separately and BASIC files them by line
number:

```
*EXEC FBVDU
*EXEC FBMODEL
RUN
```

`tools/fbbuild.sh` merges them in line-number order for `baslint.py` and for the
emulator, which each want one file. It also **checks both bands on every build**
and prints how many line numbers the engine has left — it ran out once, on
2026-08-28, and was reflowed from step 5 to step 2 (`docs/glyphs.md`). `tools/basrenum.py` renumbers after an
insertion and rewrites the line references that renumbering would break.

Three things the seam forced, each a latent bug:

- The engine no longer calls `PROCstop`, which lived in the test code. It sets
  **`vfail$`** and returns; the driver decides what a failure looks like. A
  native core returns the same thing as a status.
- **`RESTORE` names its line.** Bare `RESTORE` finds the *first* `DATA` in the
  program, so a driver carrying `DATA` of its own would have silently repainted
  the palette from the wrong numbers.
- The simulated grid moved to the driver. Geometry is the driver's decision and
  the engine had been overriding it.

### One real bug, found by writing the test rather than by running it

`PROCv_scroll` computed the number of rows to move and looped over them
directly. **A BBC `FOR` always runs its body once**, so scrolling a region by its
own full height — a zero-length move — copied one row in from *outside* the
region: somebody else's text appearing in a screen that had just been cleared,
once, and never reproducibly. The move now lives in `PROCv_up`/`PROCv_down` and
the **call** is guarded, which is the only way to express "do this no times" in
BASIC.

## 4.7 Phase 2b — the VT engine, built

**80 of 80 checks pass under b-em, 2026-08-20**, model-only, in one run and
without touching the hardware. `test/fbparse.bas` feeds bytes through
`PROCv_write` exactly as they will arrive from the socket and asserts on the
cell model afterwards.

What is in it: the UTF-8 decoder, the state machine (ground, ESC, CSI, OSC,
string, charset, `ESC #`), C0 with **real tab stops**, the ESC set including
DECSC/DECRC, IND, NEL, RI, RIS and `ESC ( 0`, the CSI dispatch onto the phase 2a
operations, SGR in full, DECSET/DECRST, the reply channel and the alternate
screen.

### Three things this makes true that were not before

**The pending wrap is the real rule, in three lines.** A glyph written into the
last column does not move the cursor — it sets `pw%` — and the wrap happens when
the *next* glyph arrives. So a line that exactly fills the screen leaves the
cursor visible on it, `CR` or any cursor move cancels the wrap, and **nothing
has to swallow a following LF**. §9.3's two hacks — the sacrificed bottom-right
cell and the swallowed newline — are both retired, and the checks name them:
`cr cancels the pending wrap`, `lf after a full line moves one row`.

**The alternate screen restores.** `alt%` is a real second buffer, so `?1049l`
brings back what was behind a full-screen program instead of a cleared screen.
It is `DIM`med the first time something asks for it, so a replay that never
switches screens does not pay 20K for it.

**The terminal can answer.** `FNv_reply` hands back the bytes the far end must be
sent — `ESC[r;cR` for DSR 6, `ESC[0n` for DSR 5, `ESC[?6c` for DA — and clears
them by being read. Nothing on the BBC side could answer a cursor position report
at all.

### The DEC line drawing set is ours

Slots 128–159 of the font hold the DEC special graphics set, written straight
into `font%` from `DATA`. No `VDU 23`, no harvest, and identical in simulation
and on the glass — **we own the table**, which is the whole point of §4.1.

The stroke convention is the one `FBFONT` already proved legible on hardware: a
horizontal on row 3, a vertical two pixels wide as `&18`. The six glyphs
`PROCv_box` defines are the same shapes, so a box drawn through `ESC ( 0` and one
drawn through the harvested pieces line up pixel for pixel.

`FNv_uni` maps the UTF-8 box-drawing, block and symbol codepoints onto the same
slots, so `─` and `ESC ( 0 q` are the same pixels. Everything else is the
replacement glyph, and the set is ours to extend.

### What is not in it

- SGR 2 faint and 3 italic are parsed and dropped. An 8×8 cell has nowhere to
  put them and a wrong rendering is worse than none.
- Mouse reporting is parsed and ignored, as planned.
- `38;2;r;g;b` is reduced — but to the **same 6×6×6 cube the palette was built
  from**, not to sixteen colours. `38;5;n` is exact, because `FBPAL2` proved all
  256 entries are programmable.

### The offline harness is now near its limit

Engine plus parser test is **38K of stripped source**, which needs
`BEEB_TUBE=4` — the 65816's 46K — and will not fit the 6502's 30K. Phase 3
replays at 80×24 add a 15K model on top of that. Expect to run the phase 3
drivers separately rather than as one program, or to trim the engine for the
offline build.

## 4.8 Phase 3 — replay against an oracle

`tools/ptycap.py` captures a real pty session, `test/fbreplay.bas` puts the bytes
through `PROCv_write` exactly as they will arrive from the socket and dumps what
the cell model ends up holding, and `tools/vtdiff.py` puts the **same** bytes
through `pyte` at the same geometry and diffs. The first time this project can
check a screen against a reference instead of against a photograph of a monitor.

**80×64, not the plan's 80×24.** The reduction was to fit two buffers in the
Master's BASIC space; `BEEB_TUBE=12` gives 64MB and it is dead. `ptycap`'s own
docstring says why it matters: capture at the size the Beeb runs, or the wrapping
under test is not the wrapping that happens — and at the wrong height the
scrolling is wrong too.

The dump is three sections, because three different things can be wrong and a
grid of characters hides two of them: `[grid]` the text, `[odd]` the cells whose
glyph is not printable ASCII (the DEC line-drawing set lives at 128–159 and would
otherwise all look like one placeholder), and `[runs]` the attribute runs, so a
colour or reverse-video fault shows up where the text is identical.

`vtdiff.py` reads the Unicode→slot map **out of `FNv_uni` in the engine source**
rather than repeating it, so the oracle and the engine cannot drift apart.

### What the replay measured, and it is not what I guessed twice

The 582-byte feature capture took **33 seconds**. The first guess was `BGET#` per
byte — a Tube round trip and a host filing-system call each — and bulk-loading
the capture changed nothing. The second was `PROCv_fill`, and inlining its stores
halved it but no more. Measuring each operation through the real path found it:

```
1000 plain glyphs        643 cs      0.64ms each
100 RIS                35322 cs      353ms each
```

and then, per cell of a full-screen clear:

| | per cell |
|---|---|
| `PROCv_fill` | 0.67 ms |
| the identical loop written inline | 0.67 ms — the "optimisation" bought nothing |
| one word store instead of four byte stores | 0.27 ms |
| an empty `FOR` iteration | 0.021 ms |

**Memory writes on b-em's emulated ARM cost about thirty times a loop
iteration.** That is the emulator, not the engine: §4.5 measured 16,960 cells/sec
on the real copro 15, roughly ten times faster. Emulated centiseconds also run at
five times wall clock at `-sp9`, so divide the figures above by five for real
seconds.

One thing was worth fixing for the hardware too. `PROCv_glyph` called
`PROCv_put`, and **a BBC BASIC procedure call with six arguments costs seven
times a bare one** — 0.55ms against 0.08ms measured. That call ran once per
character of the stream and was essentially the entire cost of plain text. The
cell is now written inline.

### PASSED 2026-08-20: every cell of every capture matches pyte

```
=== FEAT     all 5120 cells match pyte     and all 5120 attribute cells match
=== TOP      all 5120 cells match pyte     and all 5120 attribute cells match
=== LS       all 5120 cells match pyte     and all 5120 attribute cells match
```

`tools/vtcheck.sh` is the gate and re-runs the whole corpus.

**It found two real bugs, which is the entire point of having an oracle.** Both
were invisible on a monitor and both would have shown as "the colours look a bit
off".

**An erase carries the current rendition, not just the current colours.**
`PROCv_erow` and `PROCv_fill` wrote zero into the flags byte. `top` draws its
column header as a full-width reverse-video bar and clears to end of line, so the
bar stopped where the text stopped instead of running to the right margin.

**With a wrap pending, an operation that acts from the cursor acts from past the
last column, and therefore does nothing.** `top` writes an 80-character
reverse-video header, resets the colour and sends `EL`; this engine erased the
last cell, leaving a one-cell notch in the right-hand end of every full-width
bar. `ICH`, `DCH` and `ECH` behave the same way.

That second one was checked against **tmux** as a third opinion before the engine
was changed, because pyte disagreeing with us is not by itself evidence that pyte
is right. tmux left all 80 cells reversed for all four operations. Two
independent implementations agreeing against us is evidence; one is a hypothesis.

### Where the oracle is not the authority

`vtdiff.py` adjusts pyte in exactly one place and it is documented in the source:
pyte **deliberately ignores `ESC ( 0`** while `use_utf8` is set, on the argument
that a UTF-8 terminal should be sent real box-drawing characters. That is a
documented deviation from xterm, and xterm is what we target —
`xterm-256color`'s `smacs` *is* `\E(0`, so ncurses sends it for every box it
draws and a terminal ignoring it renders `mc` as strings of `lqqk`. The flag is
cleared, which in pyte gates that dispatch and nothing else, and the UTF-8
decoding is done in `vtdiff` instead.

And pyte has **no alternate screen whatsoever** — no `1049`, `1047` or `47`
anywhere in it, and `?1049h` is a silent no-op, so text meant for the alternate
buffer lands on the main screen and stays. The engine keeps a real second buffer,
which is one of the reasons this project owns its VDU at all. `captures/ALT` is
kept as an engine-only fixture, `vtcheck.sh` skips it, `vtdiff` warns loudly if a
capture contains those sequences, and `test/fbparse.bas` checks the behaviour
instead. **The engine is not changed to match the oracle where the oracle is the
weaker of the two.**

### The open performance item, for phase 4

`ls --color -la /etc` replays in 165 seconds against `top`'s 21, although it is
the *smaller* capture. The difference is scrolling: `ls` scrolls on almost every
line, and `PROCv_scroll` moves 63 rows × 80 cells across **two** arrays, model
and shadow. §6.3 measured the *pixel* half of a scroll at 4 cs on hardware; this
half is around seven times that.

The fix is the one a native core would use anyway and the one §3 gestured at when
it said a scroll is an index change: hold a **row-pointer array** and rotate the
pointers, so a scroll moves 64 pointers instead of 5,040 cells. It touches every
`scr%+(y*cols%+x)*4` in the engine, so it is phase 4 work with the suites in
place to catch it, not something to slip in beside a verification phase.

## 4.9 On the hardware, 2026-08-20 — phase 2 and 3 confirmed on the glass

**All ten visual checks pass, and the renderer is exactly as fast as it was in
phase 1.** `CHAIN "FBRUN"` on copro 15 — the first hardware run of the engine
since phase 1, and the first ever of the tokenised load.

```
screen=&1F8B0000 pitch=640      geometry 80x64 cell 8x8
full flush        5 cs  848 cells      16,960 cells/sec
one cell changed  1 cs   31 cells
attribute page    3 cs  988 cells
page 3                  497 cells
ten scrolls      59 cs   0 damaged above, 530 exposed, 530 repainted
```

| | |
|---|---|
| 256 patches all different | ok |
| 16 ANSI lines, 16 colours | ok |
| box pieces close into a rectangle | ok |
| cursor block visible | ok |
| bold, reverse, underline, strike | ok |
| coloured pairs legible | ok |
| **DEC line drawing draws one unbroken box** | **ok** |
| **the UTF-8 box is identical to it** | **ok** |
| **the reverse bar reaches the right edge** | **ok** |
| **and has no gap at its right end** | **ok** |

The last four are the ones nothing else could answer. `pyte` cannot judge pixels,
so §4.8's fixes were correct against a reference but unverified as *pictures*
until now:

- **`p3_dec`** — the DEC set at font slots 128–159, written by `PROCv_glyphs`,
  rendered on hardware for the first time. §4.7 claimed a box drawn through
  `ESC ( 0` and one drawn from the harvested pieces would line up pixel for
  pixel; they do.
- **`p3_utf8`** — the same box reached through UTF-8 and `FNv_uni`, and it is
  indistinguishable, so the two routes really do land on the same glyph.
- **`p3_bar` and `p3_notch`** — phase 3's two bugs, made visible. The bar reaches
  the right edge, so the rendition survives the erase; and there is no one-cell
  gap at its end, so the pending wrap no longer erases the last cell. Both were
  found against pyte, one was arbitrated by tmux, and both are now confirmed as
  pixels.

**The scroll invariant holds on hardware**: nothing above the exposed row was
damaged, and exposed equals repainted, so the glass, the model and the shadow
stayed in step. The pixels moved and only the newly exposed row was redrawn.

**Nothing today cost any speed.** 848 cells in 5 cs is 16,960 cells/sec, the same
figure §4.5 measured before the model, the parser, the glyph set and four fixes
existed.

### What this leaves for phase 4

The renderer, the init path and the glyph set are all confirmed. What has still
never run on hardware is the **parser driving the renderer from a live stream** —
`test/fbreplay.bas` is model-only, and `PROCpage3` writes through `PROCv_write`
but only a few hundred bytes. That, the row-pointer scroll, and `PTERM` are what
is left.

## 4.10 Phase 4 — the parser driving the renderer, on hardware

**2026-08-20. `top`, 23,725 bytes off a real pty, replayed on copro 15 with the
renderer live.** The first time the parser has driven the blitter from a stream
rather than from pictures the engine was handed.

```
bytes                 23725
parse                    19 cs        124,868 bytes/sec
flush                    11 cs        2616 cells
drained, 512 at a time   75 cs        47 flushes, 4941 cells, 105 per flush
```

| | |
|---|---|
| Does that look like a real terminal screen? | **Y** |
| Any torn rows, wrong colours or stray glyphs? | **N** |
| Did it redraw cleanly, without flicker or tearing? | **Y** |

**And the screen matches pyte cell for cell** — every character and every
attribute — so the hardware model, the emulator model and the oracle all agree.
The dump goes through the same `tools/vtdiff.py` as phase 3.

### The prediction was wrong by a factor of fifty

§4.8 measured the emulator and scaled it by the eleven times the two machines
differ by on cell writes, predicting **~2,500 bytes/sec** and warning that the
parser, not the socket, would be the bottleneck. The real figure is **124,868
bytes/sec — forty times §5.5c's 3,082 bytes/sec socket rate.** The parser is
nowhere near the bottleneck.

The lesson is about the emulator, not the engine: b-em's ARM tube is
pathologically slow at *memory writes* specifically, so a ratio measured on
`PROCv_fill` does not transfer to a path dominated by interpretation. **Do not
extrapolate hardware performance from b-em.** Measure it.

Treat the parse figure as the right order of magnitude rather than three
significant figures — 19 cs is a short interval to divide by. Even an error of
ten times leaves four times the headroom the socket needs.

### What it settles about the design

**105 cells per flush.** §3 decoupled the model from the renderer on the argument
that a drain's worth of bytes should cost one repaint, not one per line, and that
a real refresh touches a few hundred cells rather than five thousand. A `top`
frame paints 105. The whole 23,725-byte capture, drained 512 bytes at a time
through 47 flushes, renders in **0.75 seconds**.

That also softens the phase 4 scroll item: the row-pointer rotation is still the
right shape for a native core, but it is an optimisation now, not a fix.

### One bug, in the harness

Row 63 of the first hardware dump was the question prompt. `PROCask` paints it
through the engine on purpose — so that what is read is the screen under test —
but it therefore lands in the model, and it was the only row of sixty-four that
differed from the emulator. The dump now happens before the question.

## 4.11 Phase 5 — PTERM on hardware, and what a live session found

**2026-08-20. A real shell on the Beeb.** `ll` renders correctly, `top` runs, the
keyboard works and CTRL-] quits cleanly. Socket, parser, renderer and keyboard
all confirmed together on copro 15.

Three faults, none of which any offline test could have found, because all three
needed either a live far end or a real keyboard:

**`ESC` was unusable.** `*FX229,1` was missing — BEEBTERM sets it alongside
`*FX4,1` so that ESCAPE returns 27 instead of raising a BASIC *Escape*. Without
it the key kills the client, taking `vi`, `less` and every ncurses menu with it.
The tell was `PROCtidy` restoring 229 to 0 having never set it.

**The connection banner bypassed the model.** It was a plain `PRINT`, which
reaches the framebuffer through the Pi VDU driver, onto cells the model believes
are blank — and the shadow then agrees they need no painting, so the flush could
never remove them. §2.3a's rule is that nothing reaches the glass except through
the model, and it is easy to break by accident.

**A CSI parameter overflowed a 32-bit integer.** `PROCv_param` accumulated digits
with `v%*10+d` and a long enough run raised *Number too big* — error 20 — which
took the whole terminal down. A parameter is an arbitrary run of digits from the
far end and nothing bounds it: shell integration sends things like
`pid=00000000000000126317`. It saturates at 65535 now, which is far past the
largest parameter the engine can use (a mode number like 2004) and far past the
largest that addresses the screen (80). **Saturating rather than wrapping
matters**: a wrapped value is a *plausible* small number, and a cursor move to a
plausible wrong place is much harder to see than one clamped to the edge.

`captures/SHELL` holds the real shell-integration OSC that provoked it, long
digits and all, plus `ESC[999999;999999H`. It replays byte-identical to pyte.

### What a live session is for

Phases 3 and 4 checked the engine against an oracle and got every cell right,
twice, on two machines. None of that could find any of the three above, because
an oracle only sees the bytes you give it: it cannot know that ESCAPE never
reaches the parser, that a `PRINT` went round the outside of the model, or that
the far end will one day send a twenty-digit parameter. **Correct against a
reference is not the same as working.**

## 4.12 Phase 5 — PTERM works

**2026-08-20. A real shell on the Beeb, byte-lossless, and the screen verified
against pyte.**

```
received=5760  reads=4115  short=0  e1e=4011  rmax=64
discarded d1=0 d2=0 d3=0  rmax_now=64
```

Nothing discarded, no short reads, the read ceiling never had to come down — and
**rows 1–63 of the hardware screen match pyte exactly, all 5040 cells** (row 0 is
PTERM's own banner). The user's word for it was "everything solid".

### The transport was the hard part, and none of it was the engine

Phases 3 and 4 verified the engine against an oracle and got every cell right,
four times, on two machines. Every fault in phase 5 was below it:

| | |
|---|---|
| `ESC` unusable | `*FX229,1` missing, so the key raised a BASIC *Escape* |
| The banner smeared permanently | a plain `PRINT` reached the glass without going through the model |
| *Number too big* | a CSI parameter overflowed 32 bits — shell integration sends `pid=00000000000000146421` |
| Stale blocks down the screen | the cursor was erased where it had *moved to*, not where it was drawn |
| **250 bytes lost mid-stream** | **`Socket_Recv` refuses a read above ~64 bytes and consumes it anyway** |
| Ran, then stopped silently | a peek succeeding with zero bytes is EOF, and was read as "nothing yet" |

The fifth is the one that mattered and the one nothing offline could have found.
§5.5c's 3082 bytes/sec had been measured with a read that was quietly dropping
data: throughput was counted, loss was not.

### How it was actually found

Not by looking at photographs — three sessions were diagnosed that way and the
mechanism was guessed wrong twice. What settled it was making the machine report:

1. `RXLOG`/`RXL` records every byte the transport delivered, so the received
   stream can be diffed against what the server logged sending.
2. Feeding that log to `pyte` **reproduced the corrupted screen exactly**, which
   proved the engine was rendering broken input correctly rather than breaking
   good input.
3. Counting each of the three paths in `FNnet_recv` that can discard a completed
   read named the line in one run: `d2=21, lasta=88`.
4. `FBSIZE` turned that into a number — a hundred peek-then-read cycles at each
   size, clean to 64, two refusals at 128.

The doubled letter in `user@woorkshop` on a photograph was what first showed it
was a boundary fault rather than random corruption. Photographs were good at
saying *something is wrong*; only the machine could say *what*.

### 4.13 The cursor must be recorded in the shadow

A live session left about 130 cells on the glass showing characters the
model had long since replaced, in vertical stripes at a few columns. The
identical session with `cvis%=FALSE` left none.

The shadow buffer exists to answer one question per cell: *does the glass
already show what the model says?* The flush repaints only where the answer
is no. Drawing the cursor writes the glass — the model's own glyph with the
colours swapped — **without changing the shadow**, so for as long as the
cursor is drawn the shadow's answer is wrong. Taking it down again depended
on `PROCv_uncur` being reached before anything else touched that cell, and
on hardware that is not always so.

What made this hard to see is that a cursor does not leave a solid block
behind. It leaves *the character it was sitting on*, so the residue decodes
to a real letter and reads as a cell that was never painted rather than as
a cursor that was never erased. Reading the pixels back off the glass and
decoding them against the cell's own background is what settled it: `t` at
column 59 on fifty-four rows, `a` at column 32 on forty-one, and the model
blank at every one of them. The same character down a column is one cell's
content stranded, not many cells each going wrong.

So `PROCv_cur` writes the cursor cell's shadow entry to the complement of
the model word. The next flush then repaints that cell whatever happens in
between, and the cursor is self-correcting rather than order-dependent.

**A native core inherits this rule.** Anything that writes the glass without
going through the flush must either update the shadow to match what it drew,
or invalidate it. There is no third option, and the cursor is the only thing
in the engine that was allowed one.

### 4.14 Phase 5 closed: PTERM is clean, and the peek was dead weight

Final hardware run (2026-08-21, `top` then `ll` through the socat shim):

```
received=46052 reads=13888 short=0 e1e=13088 rmax=64
peeks=0 fellback=0 lasterr=0 peeknow=0
throughput=2416 bytes/sec
stale_cells=0
```

`top` renders correctly at 80x64 — columns aligned, names truncated with `+`,
`^C` back to the prompt — with **no stale cells and no lost bytes**.

**The read is one OSWORD call, not two.** `FNnet_recv` used to peek to learn the
byte count and then read exactly that many, which made every productive read
cost two Tube round trips. `RESSIZE` had already shown a 64 byte ask refused
nothing in 46 tries and that short returns are normal; refusal tracks the
*absolute* request size, not over-asking, since at 128 only 2 of 35 failed.
Dropping the peek took productive reads from 29/sec to 53 and throughput from
1611 to 2434 bytes/sec.

**It bought less than the doubling the call count suggested**, because the
average read also fell from 56.1 bytes to 46.0: without the peek we take
whatever has arrived instead of waiting to learn the count. That is the trade,
and it is still strongly worth making. Under `top`, which bursts, the average
came back up to 57.6.

The fallback stays in. If a bare read ever answers with anything but the
module's own would-block, `PROCnopeek` reverts to peeking for the rest of the
session and the dump reports `fellback` and `lasterr` — that one call may
already have consumed bytes, and silent loss is far worse than being slow.

**What now bounds throughput is the OSWORD call itself at 64 bytes a time**, not
the parser and not the renderer. Parsing all 46,052 bytes costs about 0.4s of
the 19s busy time at the 124,868 bytes/sec of §4.9. Further speed has to come
from the module or the Tube, not from the BASIC.

**A drawn cursor is a cell the glass and the model are entitled to differ
about.** `PROCglasscheck` has to erase it before snapshotting or it reports its
own cursor as stale forever — one solid block at the column where the cursor
rests after the prompt.

## 5. What "meets the requirements of the Linux terminal" means

Implemented, not approximated. **Everything in this list is built and checked as
of phase 2b**, except where the note says otherwise:

- **Deferred wrap** as a pending-wrap flag — the real VT rule. Retires both
  hacks: the sacrificed bottom-right cell and the swallowed `LF`.
- **Scrolling regions** (DECSTBM) in the model. No `VDU 28` window, no origin
  arithmetic to get wrong.
- **An alternate screen that restores** — `?1049`, `?47`, `?1047/1048`.
- **The editing sequences the driver simply lacks**: IL, DL, ICH, DCH, ECH, SU,
  SD. TUIs use these constantly and they are unimplementable today.
- C0: BEL, BS, HT with real tab stops, LF/VT/FF, CR, SO/SI.
- ESC: DECSC/DECRC, IND, NEL, RI, RIS, charset select including the **DEC
  line-drawing set** (`ESC ( 0`), `ESC # 8`.
- CSI: CUU/CUD/CUF/CUB, CNL/CPL, CHA/HPA/VPA, CUP/HVP, ED 0/1/2/3, EL 0/1/2,
  DECSTBM, SM/RM 4, DSR 5/6 and DA (**both reply**), DECSET/DECRST for ?1 ?7 ?12
  ?25 ?1049 ?2004 with mouse modes parsed and ignored, tab set/clear, DECSCUSR.
- SGR in full, including `38;5;n` / `48;5;n` and `38;2;r;g;b`.
- **UTF-8 decoding** to glyph indices, with box drawing, block elements and
  arrows in the glyph map. We own the font table, so the set is ours to extend —
  `VDU 23` is no longer the mechanism.
- **A reply channel.** Nothing on the BBC side could answer a cursor position
  report before.

## 6. Probe results

**PHASE 0 IS COMPLETE, 2026-08-20.** All four questions are answered on hardware,
and every one came back the favourable way:

| Question | Answer |
|---|---|
| Palette depth | **256 real, individually programmable entries** — `xterm-256color` is exact, no nearest-colour table |
| Font | **Harvested off the driver**, 101 glyphs in 1 cs, box pieces byte-exact, byte order confirmed |
| Blit rate | **9 cs for a full 80×64 repaint — 11 a second**, against the 2–3 needed |
| Geometry | **Free choice** — 80×64 and 80×32 cost the same. Chosen: 80×64 |
| Edit-test loop | **`SAVE`/`LOAD` round trip is clean** over LANManFS at 14 KB/sec |

Nothing in Phase 0 came back requiring a fallback, and two of the fallbacks
planned for in §8 — the transported font and the 256-byte nearest-colour table —
are now dead work that will never be written.

Phase 1 is unblocked.

### 6.1 `FBPAL` — palette depth

**RUN 2026-08-20, INCONCLUSIVE — re-run needed.** Two things were learned, one
of them the hard way.

**`OS_ReadPalette` is a stub.** It returns without error and writes nothing:
1024 reads across four dumps, every one zero, including dumps taken immediately
after the palette had been reprogrammed. The probe recorded `readpalette=present`
because the call did not error — **not erroring is not the same as being
implemented**, and the check was too weak. `PROCtrypal` now reads sixteen entries
and treats sixteen identical values as a stub, and `fbres.py` refuses to draw
any conclusion from a dump whose entries are all alike.

So the machine cannot answer this one for itself. The eye is the instrument, and
the probe's job is to ask a question the eye cannot get wrong — which the first
version failed at. It asked which of sixteen 27-pixel bands had changed; the
answer came back as "line 2", which could be the second band (entries 16–31,
programmable) or the band numbered 2 (entries 32–47, which would make no sense).
The recorded answer was `blue=?`, because `PROCask` accepted any key and wrote
anything under 32 as a question mark.

**What the run does suggest:** `xterm=Y` — after all 256 entries were defined,
the grid looked like an xterm colour chart. That appearance needs the 6×6×6 cube
across entries 16–231, so it points at the entries above 15 being programmable.
It is corroboration, not proof.

**The re-run was NOT decisive, because the question was not exclusive.** Two blocks are drawn in entries 200
and 100, two more in entries 8 and 4 — what 200 and 100 become if `VDU 19` wraps
mod 16 — each labelled on screen. Then 200 and 100 are reprogrammed. Whichever
pair changes is the answer, in one keypress, with nothing to count:

| Answer | Meaning |
|---|---|
| **A** | entries above 15 are programmable — `xterm-256color` can be exact |
| **B** | `VDU 19` wraps mod 16 — only 16 entries, `FNx256` stands |
| **N** | `VDU 19` is ignored above 15 — only 16 entries, `FNx256` stands |

`PROCask` now takes only the offered keys, and the grid's bands are numbered on
the grid itself.

**Second run, 2026-08-20 — still contradictory, and the fault is the test's.**
`blocks=A`, `distinct256=Y`, `xterm=Y`, `osword=Y`, but `blue=N`.

Block A was index 200 and block B index 8 — and **8 is what 200 becomes if
`VDU 19` wraps mod 16**, so in the wrapped world *both* blocks change and "A
changed" is a true answer that carries no information. The question offered A, B
or N as though they were exclusive. They are not. Meanwhile `blue=N` says that
asking entries 16–31 for blue changed nothing, and under *either* surviving
hypothesis something had to move: a deep palette turns band 1 blue, a mod-16
wrap turns most of the screen blue.

`distinct256=Y` is also weaker than it looks: §2.3 already established 64
colours × 4 tints = 256 distinct shades, so 256 distinct patches is expected
whether or not there are 256 *entries*.

### 6.1a `FBPAL2` — the discriminator, properly posed

**PASSED ON HARDWARE 2026-08-20. The palette has 256 real entries.**

```
control      Y   entry 4, known programmable — the method works
VDU 19       1   only the LEFT block moved
OS_Word 12   1   only the LEFT block moved
```

Index 200 changed while index 8 sat still, by both routes independently. 200 is
its own palette entry, not entry 8 wearing a different number. The control
passed first, so a null result would have been visible as a broken method rather
than mistaken for a shallow palette.

**What this buys `FBVDU`:**

- `TERM=xterm-256color` is **exact**, not approximate. The 240 non-ANSI colours
  are set to their true RGB values at startup rather than mapped to a nearest
  neighbour.
- **`FNx256` and `FNgrey` are not ported.** §2.3's "compute a 256-byte
  nearest-colour table on the Linux side and bake it in" is superseded for the
  framebuffer path — that table is never written.
- `38;2;r;g;b` truecolour still has to land somewhere, since 24 bits do not fit
  in 8. But with every entry programmable the reduction is now a *choice* —
  nearest of 256, or a handful of entries reallocated on demand — rather than a
  constraint.

**What it does NOT establish.** This tested the framebuffer path: a byte poked
into screen memory selecting a palette entry. Whether the *driver's* own colour
selection (`GCOL`, `VDU 17`) can reach entries above 15 is untested and
unrelated — §2.3's 64 colours × 4 tints was measured through `GCOL` and stands
untouched. `BEEBTERM` renders through that path and gains nothing from this.

The question the probe had to answer was never *which* block changed. It is
whether the **companion** changed too:

| Answer | Meaning |
|---|---|
| only LEFT moved | 256 real entries — `xterm-256color` can be exact |
| BOTH moved | one entry wearing two numbers: 16 entries by low nibble, the 64×4 of §2.3 |
| neither moved | ignored above entry 15 |

A **positive control runs first**: entry 4 is one §2.3 already proved
programmable, so if reprogramming it changes nothing then the method is broken
and the rest of the run is void. A test that cannot fail its own control is not
a test. `OS_Word 12` is then asked the same question independently — `FBPAL`
recorded `osword12=accepted`, but *accepted* only means the SWI returned, and
`OS_ReadPalette` returned too.

### 6.2 `FBFONT` — font harvest

**PASSED ON HARDWARE 2026-08-20. The font question is closed.**

```
glyphs       95 printable, plus the 6 box pieces
harvest_cs   1        101 glyphs in one centisecond
blank        0        every printable glyph came back with ink
shapes       Y        the re-blit matched the driver's own rendering
```

**All six box glyphs match their `VDU 23` definitions exactly**, which closes
three questions at once: the read-back works, `VDU 23` redefinition survives it,
and **bit 7 is the leftmost pixel** — a mirrored harvest would have turned `&1F`
into `&F8`. `PROCxp` fills the word the right way round.

Rendered here, the glyphs are a correct 8×8 BBC font — proper descenders on `g`
and `j`, the classic broken bar on `|`:

```
  A         F         g         W
..####..  .######.  ........  .##...##
.##..##.  .##.....  ........  .##...##
.##..##.  .##.....  ..#####.  .##.#.##
.######.  .#####..  .##..##.  .##.#.##
.##..##.  .##.....  .##..##.  .#######
.##..##.  .##.....  ..#####.  .###.###
.##..##.  .##.....  .....##.  .##...##
........  ........  ..####..  ........
```

**Consequences:** no font is transported — no `DATA` statements, no binary with a
hand-supplied load address. At **1 cs for 101 glyphs** the harvest is free at
startup, so `FBVDU` harvests every time rather than caching. The font is kept
by `fbres.py --font` (2048 bytes), because it lets the offline tests render
exactly what the Beeb renders.

**That file is not distributed with this repository.** The glyphs are the Pi
VDU driver's, not ours. Run `test/fbfont.bas` on your own machine to make it;
the engine harvests the same font at run time regardless, so only the offline
`sim%` path needs a copy on disc.

### 6.3 `FBBENCH` — can BASIC carry the blitter, at which cell size

**RUN 2026-08-20. The headline answer is solid; the variant comparison is not.**

```
A  80x64 8x8  PROC/cell    9 cs    56889 cells/sec   11.1 screens/sec
B  80x64 8x8  inline       9 cs    56889 cells/sec   11.1 screens/sec
C  80x64 8x8  unrolled     9 cs    56889 cells/sec   11.1 screens/sec
D  80x32 8x16 inline       9 cs    28444 cells/sec   11.1 screens/sec
shadow compare             1 cs
scroll as a screen move    4 cs
```

**BASIC carries the renderer, with room to spare.** A full 80×64 repaint is
**9 cs — 11 repaints a second** against the 2–3 §3's decoupled flush needs.
§2.3a's arithmetic is confirmed and Phase 1 is unblocked.

Three results worth building on:

- **Geometry is a legibility choice, not a performance one.** 80×64 and 80×32
  measured identical, which follows: both write exactly 81,920 words. Per-cell
  overhead is not what costs. **Settled 2026-08-20: 80×64 on an 8×8 cell** —
  chosen on the glass, since the benchmark had nothing to say. It is also the
  geometry the harvested font is drawn for, so nothing has to be synthesised,
  and the one `BEEBTERM` already reports through `stty rows 64 cols 80`.
- **Scrolling by moving the screen (4 cs) beats repainting it (9 cs)**, so a
  scroll with no content change deserves a special case in the flush — move the
  pixels, repaint the one exposed row.
- The shadow compare over 5120 cells costs **1 cs**, so damage tracking is free.

**What is NOT trustworthy: the A/B/C/D comparison.** Four structurally different
loops cannot cost the same to a centisecond — a `PROC` call per cell, 5120 times
over, is not free. Those differences are inside the timer's resolution, so the
run says nothing about whether to write the blitter unrolled. `FBBENCH` now
repeats each measurement ten times and adds an **empty-loop floor** that measures
the interpreter walking the nest with the pixels taken out, and `fbres.py` flags
identical variant timings rather than reporting them as a finding.

That re-run is **not** a gate on Phase 1 — the headline is five times what is
needed either way. It settles a code-style question, not a feasibility one.

### 6.4 `SAVE`/`LOAD` over the share — `test/fbsave.bas`

**PASSED ON HARDWARE 2026-08-20, over LANManFS.**

```
in memory    5765 bytes        PAGE &8F00 to TOP &A585
on disc      5765 bytes        matches
differing    0 words
SAVE         35 cs             16 KB/sec
LOAD         41 cs             14 KB/sec
```

Confirmed three independent ways: the Beeb compared the file against its own
memory word by word and found nothing different; the lengths agree; and the
stored file, read back **from the Linux side**, is a well-formed tokenised BBC
BASIC program — 166 lines numbered 10 to 1660, `0D FF` terminator, line numbering
identical to `test/fbsave.bas`. `fbres.py` performs that last check
automatically whenever `FBTEMP` is on the share.

**So the edit-test loop is safe.** At 14 KB/sec a thousand-line engine loads in
around two seconds, against `*EXEC` typing it in character by character. `*EXEC`
once, `SAVE`, `CHAIN` thereafter — which is what §2.3a said had to be protected.

A thousand-line engine typed in by `*EXEC` on every run is not an edit-test loop,
and §2.3a says protecting that loop is the whole reason the engine is BASIC
first. What the workflow needs is `*EXEC` once, `SAVE`, then `CHAIN`. Reading
from the share is proven daily — every probe arrives by `*EXEC` — so the risk is
concentrated in **writing** a tokenised program.

The probe saves the running program, reads the file back with `*LOAD`, and
compares it **word by word against the program still in memory between `PAGE` and
`TOP`**. Byte-identical is the whole round trip: `SAVE` wrote it, `LOAD` read it,
nothing was translated on the way.

Under b-em: 5,765 bytes out, 5,765 bytes back, **0 differing words of 1,441**.

Two things this probe had to work around, both BASIC IV behaviour found under the
emulator rather than on the machine:

- `SAVE tf$` is a **syntax error** — BASIC IV will not take a string expression
  there.
- `SAVE "FBTEMP"` is a syntax error *too*, because BASIC IV treats `SAVE` as an
  immediate-mode **command** and rejects it inside a program. The probe uses
  `OSCLI("SAVE "+...)`, which is the same `OSFILE` call underneath and works on
  BASIC IV and V alike. The `SAVE` a person types at the prompt is not in doubt
  if this passes: identical bytes, identical route.

It needs **no framebuffer and no mode change**, so it runs on the co-processor,
on the host, and under the emulator.

## 6.5 What the emulator already showed

`FBBLIT` (`test/fbblit.bas`) is the part of this that does **not** need
hardware. `PROCxp` and `PROCblit` need an address, a pitch and somewhere to
write — not a framebuffer — so they run against a `DIM`med block on a 6502
Master under b-em, in seconds. It is BASIC IV safe and self-checking: every
pixel written is compared against the font bit it came from, and the bytes
around each cell are sentinels, so a blit that runs off the end of a row is
caught rather than admired.

**PASS, 2026-08-20**, first run: `F` and `L` render unmirrored, 0 wrong pixels,
0 sentinels overwritten, and the same glyph in different inks comes out
identically shaped. So the nibble table, the `DIV 16` / `AND 15` split and the
address arithmetic are right, and `FBFONT` on hardware is now only being asked
whether the **framebuffer** agrees about byte order — both the 6502 and the ARM
put the low byte of a word at the lowest address.

The three hardware probes were also run under b-em, which can only reach their
error paths, and that is worth something on its own: §9.4 records the error
handler as where BASIC IV/V mistakes hid, because nothing ever exercised those
lines. `FBPAL` and `FBFONT` trap at the `SYS` with error 4 and report cleanly;
`FBBENCH` traps at `DIM space`, which is 40K of buffers not fitting in a Master
and says nothing about copro 15.

**Keep `PROCxp` and `PROCblit` identical between `fbfont.bas` and `fbblit.bas`.**
A test of a different copy tests nothing.

## 6.6 Results come back as files, not as descriptions

Each probe writes a result file to the share and `tools/fbres.py` reads them
back: `RESPAL`, `RESFONT`, `RESBENC`. The file is opened **before** the `DIM` and
the mode change, so a probe that dies early still leaves a record with the error
and the stage in it.

Where the machine can answer, it does, and where it cannot the **answer** is
recorded rather than remembered:

- **`RESFONT` carries the whole harvested font**, 8 hex bytes per glyph. 256
  glyphs is more than anyone will check off a monitor, and `fbres.py --font`
  writes it out as a 2K binary — so a good harvest is kept rather than
  re-harvested.
- **The six box glyphs are a closed loop.** Their bit patterns go in through
  `VDU 23` and are known exactly, so the harvest is *verified*, not inspected —
  and byte order falls out of the same check, because a mirrored harvest turns
  `&1F` into `&F8`.
- **`FBPAL` tries `OS_ReadPalette` first.** If PiTubeDirect implements it, every
  entry's RGB is recorded before and after reprogramming and the whole question
  becomes a diff: which entries changed when 16–31 were asked for blue. Only if
  the call is absent does anyone judge a colour by eye, and then the answer is
  written to the file.
- **`RESBENC` carries raw centiseconds and the cell counts they were measured
  over.** No rates — those are arithmetic, and arithmetic belongs where it can be
  checked.

**The results file is overwritten, not appended.** `OPENOUT` truncates —
confirmed on hardware 2026-08-20, where a 7,960-byte `RESPAL` was replaced by a
156-byte one whose length matched its content exactly, with no tail left behind.

The hazard is not a stale tail, it is a **stale file**: a probe that cannot open
its output says so on screen and carries on printing to the display, leaving the
*previous* run's file sitting there looking current. Two guards, since neither
costs anything:

- Each probe writes `run=` and the value of `TIME` at startup — a nonce that
  differs between runs and needs no clock.
- `fbres.py` prints every file's modification time and size before analysing it,
  and refuses to treat a file with no `[end]` marker as a finished run.

`tools/fbres.py` was exercised against synthetic files for every branch it has
— good harvest, mirrored harvest, empty harvest, deep palette, mod-16 wrap, no
`OS_ReadPalette` — before ever seeing hardware output.

## 7. Running the probes

```sh
tools/mirror.sh test/fbpal.bas test/fbfont.bas test/fbbench.bas
```

Afterwards, back on this side:

```sh
tools/fbres.py                          # everything in share/
tools/fbres.py --font share/PIFONT      # and keep the harvested font
```

On the Beeb, with the co-processor already selected (`*FX 151,230,15` and
CTRL-BREAK):

```
*ARMBASIC
*PIVDU 2
NEW
*EXEC FBPAL
RUN
```

`*PIVDU` before the mode — MODE 21 does not exist until output is routed to the
Pi, and the host MOS refuses it (§9.3). `Bad command` at `*PIVDU` means the
co-processor is not the ARM one.

## 8. Risks

| Risk | What answers it |
|---|---|
| BASIC too slow for a full repaint | `FBBENCH`, before any engine code |
| Palette shallower than hoped | `FBPAL`. Fallback already written and proven (`FNx256`) |
| Font harvest reads back nothing | `FBFONT`. Fallback: generate an 8×8 font on Linux and transport it as DATA, or as a binary with a hand-supplied load address (`ssd-to-beeb.md`) |
| Engine too large to `*EXEC` each run | §6.4; failing that, split it into an `INSTALL`-able library |
| b-em cannot host the model for offline tests | Reduce the harness to 80×24 with one buffer, or move verification onto the hardware |

## 9. BASIC and the harness

Four things that cost real time, recorded so they cost it once. `baslint.py`
catches the first two statically.

### A `$` in an FN or PROC name

```basic
DEF FNrow$(y%)      raises "No such variable" when called
DEF FNrow(y%)       works, and may return a string
```

The `DEF` search **finds** the definition — an undefined name gives error 29,
this gives error 26 — and then fails on entry, before the body runs. Confirmed on
both `basic2.rom` and `basic4.rom`, host and co-processor. The return type comes
from the `=` expression, so the `$` carries no meaning anyway. The contract's
`FNv_reply$` is `FNv_reply` for this reason.

### `ELSE` binds to the first `IF` on the line

```basic
IF glass% THEN IF sim% THEN PROCv_fake ELSE PROCv_vars
```

reads as "if glass and sim, fake; **otherwise** vars" — the `ELSE` belongs to the
outer `IF`, not the nearest one. A model-only run took the `ELSE` and asked the
VDU driver where the screen was. Write the tests flat.

### The offline harness can run the real language — `BEEB_TUBE=12`

**Settled 2026-08-20, and it removes two constraints at once.**

| | PAGE–HIMEM | | |
|---|---|---|---|
| host | &0F00–&7C00 | 27.6K | BASIC IV |
| `BEEB_TUBE=0` | &0800–&8000 | 30.0K | BASIC IV, 6502 Internal |
| `BEEB_TUBE=6` | &0800–&8000 | 30.0K | BASIC IV, 6502 External |
| `BEEB_TUBE=4` | &0800–&B800 | 46.0K | BASIC IV, 65816 |
| **`BEEB_TUBE=12`** | **&8F00–&4000000** | **65,500K** | **BASIC V on ARM** |

Tube 12 is the **Sprow ARM**, and it boots `ARM Tube OS 0.45` straight into BBC
BASIC V — the same lineage as PiTubeDirect's copro 15, which is what FBVDU
actually ships on. `WHILE`, `+=` and `CASE` all run. So:

- **the offline tests run in the language the engine ships in**, not in a BASIC
  IV approximation of it;
- **the memory ceiling is gone.** 64MB. The full commented 60K source runs
  unstripped, `basstrip.py` is no longer needed to make a test fit, and phase 3's
  80×24 model with an alternate screen is nothing.

And since 2026-08-20 the harness does not type the program in at all: it
tokenises with `tools/bastok.py` and `CHAIN`s, which took a full 80-check parser
run from **three to five minutes to eight seconds**. See `specification.md` §2.5
— including the three context-dependent tokens that a hand-written table gets
wrong. `BEEB_EXEC=1` forces the old `*EXEC` path.

All 80 parser checks and all 31 model checks pass there, unstripped.

**What it does not have is the framebuffer.** `OS_ReadVduVariables` is `SWI &31
not known` — ARM Tube OS is not RISC OS and offers a subset. That costs nothing,
because `sim%` and `glass%` were built for exactly this: the renderer runs
against a DIMmed block and the model runs against nothing.

**A consequence for §2's decisions.** "BASIC IV safe everywhere except the `SYS`
procedures" was a concession to the offline harness, not to the target — the
target has always been copro 15 and BASIC V. With the harness on tube 12 that
concession is no longer needed. The engine is left as it is because it works, but
new code is not bound by it.

### `-tx` does nothing, and b-em rewrites its own config

Two ways to select the wrong machine and not be told:

`b-em` documents a `-tx` flag and accepts it without complaint. **It has no
effect.** A run with `-t3` is a run on the host, silently — and tube 3 is an
80186 in any case. A test that had been "running on a 65C102 with 64K" since the
start had always been running on the host with 27K, and the first thing to
outgrow it looked like a leak in the program.

**b-em rewrites `~/.config/b-em/b-em.cfg` when it exits.** A patch written as a
substitution for `tube=-1` therefore matches nothing on the second run, and the
run silently uses whatever the last one left behind. That is what an "ARM" run
that was really an 80186 looks like: the 80186 tries to boot DOS from a disc that
is not there and the log fills with wd1770 `not found`. **The fault presents as a
disc fault and is a config fault.** `tools/beeb-test.sh` now derives from
`emu/bem-base.cfg`, a snapshot in the repository, and asserts the line it wrote.

And only **line 2** carries the tube index. The per-model `tube=` fields further
down take a *name* — `ARM`, `6502 Internal` — so writing a number into them makes
b-em warn `invalid tube name` and use no tube at all.

**Measure before believing a diagnosis**: `PRINT ~PAGE, ~HIMEM`, and the heap top
is the word at `&02`.

### A growing string is a fresh allocation every time

BBC BASIC never reclaims the block a lengthened string abandons, so building a
row character by character costs twenty allocations and leaks nineteen. The test
readers fill one buffer and read it out with `$` indirection, which costs one.
