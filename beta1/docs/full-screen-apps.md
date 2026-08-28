# Running full-screen apps over PiTerm

**The short version:** `htop -d 50 -C`, and put it in `.bashrc` as an alias.
Shells, `less`, `vim` and anything that redraws on demand are comfortable. A
continuously-refreshing monitor at default settings is not, and the reason is
arithmetic rather than a defect.

## The bandwidth budget

| | bytes/sec |
|---|---|
| Sprow module ceiling (64 bytes per 1.31 cs read) | 4,872 |
| **PTERM measured, while data is flowing** | **4,268** — 88% of it |

That is the hard limit. PTERM is not the bottleneck: a successful
`Socket_Recv` takes 1.31 cs to hand over ~56 bytes and there is no `select()`
and no timeout, so the rate belongs to the module (§4, §5.5c).

## What a full-screen app costs

Measured from a real session capture, `captures/RXH`, 38,314 bytes:

| | bytes | share |
|---|---|---|
| SGR colour | 13,363 | **34.9%** (2,834 sequences) |
| cursor positioning | 3,792 | 9.9% |
| other escapes | 621 | 1.6% |
| printable text | 19,274 | 50.3% |

htop redraws roughly **5 KB per frame**. At its default 1.5-second delay that
is ~3,400 bytes/sec sustained against a 4,268 ceiling — about 80% utilisation
with no headroom. Any hiccup grows a backlog, and nothing ever drains it.

**The wait when you press `q` is that backlog.** The module has a 76 KB packet
buffer; a full one takes **18 seconds** to cross the Tube at 4.3 KB/sec.

## Why the terminal cannot just throw it away

VT state is cumulative. Every byte in the backlog changes the model — cursor
position, scroll region, SGR state, the alternate screen — so discarding
stale frames would corrupt the screen rather than skip it. PTERM has to read
and parse all of it. Parsing is cheap (1.2% of session time) and rendering is
cheap (3.1%); it is the **socket reads** at ~30% that cannot be avoided.

Frame-dropping at the *flush* is already what `drain%=1024` does: the pump
parses up to 1024 bytes before painting once, so intermediate frames never
reach the glass. That saves rendering, not bandwidth, and bandwidth is the
constraint.

## What actually helps

```
htop -d 50 -C
```

- **`-d 50`** — 5-second refresh instead of 1.5. Frames drop 3x. The single
  biggest win, and it costs nothing you would notice on a monitor.
- **`-C`** — monochrome, removing that 34.9%. In the capture above that alone
  is **3.1 seconds** of Tube time.

Together those put the load roughly **5x under the ceiling** rather than at
it, so no backlog forms and `q` returns at once.

`top -d 5` is the same trick for the same reason.

## btop, which is a much harder case

btop is built for a modern terminal: braille graphs, truecolour gradients,
rounded boxes, block-element meters. Measured at 80x64, 12-second captures
through `tools/ptycap.py`:

| | bytes/sec | vs the 4,268 ceiling | truecolour | braille |
|---|---|---|---|---|
| `btop` (default) | **12,812** | **3.0x over** *(uncompressed — see below)* | 55.5% | 2,015 chars |
| `btop -t -u 10000` | 3,551 | 0.8x | 0% | none |
| `htop` (for scale) | 3,193 | 0.7x | 0% | none |

**Default btop works, 2026-08-28.** Both objections are gone. Its 2,015
braille characters render, and over SSH with `zlib@openssh.com` the bandwidth
stops being the problem: measured on a 221-second btop session,
`results/RESPROF_0828_btop`,

| | |
|---|---|
| to the screen, in bursts | **58,600 bytes/sec** — 13.7x the module's 4,268 ceiling |
| compression floor | **at least 26.6x** — 1,701 plaintext bytes per 64-byte read |
| default btop's 12,812 B/s | becomes **~482 B/s on the wire**, 11% of the ceiling |
| stale cells | **0**, and `short=0` — 276 new glyphs painted correctly under load |

And `q` returns at once, because no backlog forms. The 26.6x is *higher* than
the 13.3x the controlled A/B measured, and for a reason: that test used
monochrome redraws, while btop's truecolour SGR runs are longer and repeat
more, so deflate does better on them than on the workload chosen to be fair.

```
btop -t -u 10000
```

**`-t` is the important flag** — *"force tty mode with ANSI graph symbols and
16 colors only"*. It removes the braille entirely and drops truecolour from
55.5% of the stream to nothing, which is **3.6x fewer bytes** on its own.

**Even so it is marginal.** At `-u 10000` a frame is about 21 KB, which is
**five seconds** of Tube time for a ten-second update: it spends half its life
drawing. htop at `-d 50 -C` is the better tool on this machine, and is the one
to reach for.

### The glyphs btop asked for — all drawn, 2026-08-28

*The font table as a whole, and the families still missing, are in
`docs/glyphs.md`. What follows is the btop half of it.*

**Every character in `captures/` now has a glyph.** The font grew from 256
slots to 768: 0–255 is still the harvested driver font, 256–275 holds twenty
characters drawn by hand, and 512–767 is the whole braille plane, generated
rather than stored.

What the captures actually asked for, counted rather than guessed — 19
distinct characters, 1,569 times, of which two are 89% of the total:

| | | | | |
|---|---|---|---|---|
| `U+25A0` ■ 864 | `U+2591` ░ 530 | `U+2588` █ 40 | `U+25B2`/`U+25BC` ▲▼ 24 each | `U+256D`–`U+2570` ╭╮╯╰ 12 each |
| `U+2191`/`U+2193` ↑↓ 10 each | `U+2190`/`U+2192` ←→ 4 each | `U+00B2`/`U+00B3`/`U+00B9` ²³¹ | `U+2074` ⁴ | `U+21B5` ↵ |

**Braille is generated, not stored.** A braille cell *is* a 2×4 bitmap and the
codepoint's low byte *is* the dot pattern, so all 256 come from a dozen lines
rather than 2 KB of `DATA`. Each dot fills its whole 4×2 region rather than
being drawn round: btop uses braille for line graphs, and solid regions join
into a readable trace where dots would only stipple. The generator was checked
against an independently computed reference for the awkward cases — dots 7 and
8 are the later-added bottom pair, so the bit order down the cell is 0,1,2,6
on the left and 3,4,5,7 on the right.

**The rounded corners had to be measured, not invented.** The DEC set draws a
horizontal on row 3 and a vertical on columns 3–4; a corner drawn to any other
convention joins nothing. `╭╮╯╰` use the same rows and columns as `┌┐┘└` and
stop one pixel short at the elbow, which is as much curve as 8×8 allows.

### The note this replaced, kept for the reasoning

~~`-t` leaves 803 characters the engine cannot render~~ — **all rendered as of
2026-08-28.** The original entry, because its reasoning is what the work
followed:

| | count | | count |
|---|---|---|---|
| `U+2591` light shade | 530 | `U+25BC` `U+25B2` | 12 |
| `U+25A0` black square | 216 | `U+2190`-`2193` arrows | 10 |
| `U+2588` full block | 34 | `U+21B5` | 1 |

The font is **harvested from the Pi VDU driver's DEC special-graphics set**,
which has the checkerboard `U+2592` but no full block, no light shade and no
arrows — so there is nothing to map these onto. Rendering them would mean
**synthesising glyphs** rather than mapping: a full block is eight bytes of
`&FF`, and the shades are dither patterns. `FNv_uni` in `src/fbvdu.bas` is
where the mapping lives and the glyph field is 12 bits wide, so there is
plenty of room. ~~Not done~~ — **done**, and the 12-bit field is exactly what
made it a table-size change and nothing more.

Braille would be a bigger version of the same idea and is genuinely tractable
— a braille cell is exactly 2x4 dots and the codepoint's low 8 bits *are* the
dot pattern, so all 256 could be generated procedurally rather than stored.
That would make every braille-drawing TUI work. It would not make btop fit
inside the bandwidth. ~~Not done~~ — **done**, and both halves of that turned
out true: braille renders, and it took compression rather than glyphs to make
btop fit.

## What does not work

**XOFF/XON flow control.** The obvious fix — have the terminal assert XOFF
when its queue is deep so the far end blocks instead of buffering — fails
here. ncurses puts the pty into raw mode and clears `IXON` precisely so
applications can bind Ctrl-S, so flow control is disabled during exactly the
full-screen apps that need it.

**Reporting a smaller window over NAWS** would genuinely cut the bytes, since
the app draws fewer cells, but it wastes the screen the engine exists to
fill.

## The general rule

A full-screen app at 80x64 needs about **25 KB/sec** to feel live. The module
provides **4.3**. Anything that redraws on demand is fine; anything that
redraws on a timer needs its timer turned down.

**Superseded 2026-08-28.** That was the rule while the terminal spoke telnet.
Inside SSH, `zlib@openssh.com` puts **25,295 bytes/sec** on the glass through
the same module — the figure this section named as the requirement, met by
compressing the stream rather than by making the wire faster. `docs/ssh.md`
has the measurements. The advice above still holds for an uncompressed
session, and `htop -d 50 -C` is still kinder than the alternative.
