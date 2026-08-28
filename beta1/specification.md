# BBC Master Network Terminal — Specification

**Status:** **WORKING.** The terminal runs on the hardware and speaks SSH.
**Last updated:** 2026-08-28 (SSH end to end; 25 KB/sec to the glass)

The goal below is met. A BBC Master 128 logs in to a modern machine over SSH —
curve25519, Ed25519, chacha20-poly1305, Terrapin mitigation, public-key
authentication — with the session on the Pi's HDMI output at 80x64, and 25,295
bytes/sec of terminal data reaching the glass through a module that carries
4,268. See `docs/ssh.md`, which is authoritative for the transport.

What follows is the record of how it got there, including the wrong turns. The
sections are in the order they were written, so **later sections correct
earlier ones** and several are marked superseded where that happened.

---

## 1. Goal

Use a BBC Master 128 to log in to a shell on another machine on the home
network and run Claude Code interactively, with acceptable responsiveness for a
full-screen TUI.

The BBC Master provides the keyboard, the chassis and the network connection.
Display is provided by the internal Raspberry Pi co-processor's HDMI output.

**Met, 2026-08-28.** The last barrier was not the terminal — that was finished
on 2026-08-22 — but the wire. `docs/full-screen-apps.md` closed with "a
full-screen app at 80x64 needs about 25 KB/sec to feel live; the module
provides 4.3", written as the thing this machine could not have. Compression
inside SSH delivers 25,295 bytes/sec of screen data over the same module,
because **the ceiling was a property of the encoding and not of the
hardware**.

---

## 2. Hardware (confirmed)

### 2.1 BBC Master 128

Extensively upgraded. Base machine: 65C12 @ 2MHz, MOS 3.20.

### 2.2 Sprow Master 10/100 Ethernet Module

Fits the user-installable module socket (physically the Econet socket position).
**Speaks no Econet.**

| Property | Value |
|---|---|
| Link | 10/100 Mbps, auto-negotiate, auto-crossover, PoE (802.3af) capable |
| Protocols | ARP, DHCP, TCP/IP, UDP, DNS, NETBIOS, SMB, ICMP |
| Buffers | 76 KB packet buffer, 1 KB non-volatile config |
| API | Berkeley sockets via **OSWORD &C0 (192)** |
| Bundled software | LANManager, LANManFS; web server example, NTP client |

Firmware lives in upgradeable flash on the module itself.

### 2.3 Raspberry Pi Co-Processor (PiTubeDirect)

Internal kit for the Master 128, plugged into the motherboard Tube connectors.

| Property | Value |
|---|---|
| Board | Raspberry Pi 3A+ @ 1.2 GHz |
| Firmware | PiTubeDirect, "Indigo" release — **bare metal, not Linux** |
| Emulates | 6502, 65SC102, Z80, 32016, 80286, 6809, ARM Eval System, others |
| Native mode | ARM at full core speed, with BBC BASIC V |
| Display | Pi VDU driver → HDMI framebuffer |

**Extended video mode to be used: MODE 21 — 640×512, 256 colours.**
A RISC OS mode number, not a stock Acorn one; it exists only on the Pi
framebuffer, not on the BBC's own video output. PiTubeDirect's *own* extended
modes are numbered 64–71 (mode 64 is the same 640×512 8bpp geometry) and are
the fallback if a RISC OS number is ever refused.

**CONFIRMED 2026-08-19: a BASIC prompt in MODE 21 on the Pi's HDMI output.**

Getting there needs two things, neither of them the default:

1. **`vdu=1` in `cmdline.txt`** on the Pi's SD card — the framebuffer is
   disabled out of the box. Requires physically pulling the card.
2. **Routing output to it at runtime**, which differs by co-processor:
   - Native ARM: `*PIVDU 2` (Pi only), `3` (both screens), `1` (host), `0` (off).
     Covers WriteC, WriteS, Plot and ReadModeVariable.
     **Copro 15 boots to a supervisor `*` prompt, not to BASIC.** Start it with
     **`*ARMBASIC`** — that is BASIC V 1.35 (`BAS135`) built into the core but
     not selected by default. `*BASIC` and `*BASICV` are the *host's* commands
     and both answer `Bad command` here. Confirmed 2026-08-19.
   - 6502 co-processors: no `*PIVDU`; initialise with `CALL &300`, after which
     the framebuffer is reached through the OSWRCH redirector.

Without step 2 the co-processor's VDU output goes back over the Tube to the
host MOS and paints on the BBC's own RGB output — which looks like the Pi
display "not working".

Text geometry available in MODE 21:

| Font | Columns × rows |
|---|---|
| 8×8 | 80 × 64 |
| 8×16 | 80 × 32 |
| 8×10 | 80 × 51 |

~~256 colours is a full match for the xterm-256color palette, so no colour
reduction or flattening is required anywhere in the pipeline.~~

**RESOLVED 2026-08-19 by `test/palette2.bas`.** The original claim was assumed,
never measured, and it is wrong as stated — but the outcome is still workable.

MODE 21 is **64 colours × 4 tints**, not 256 free colours. `GCOL` carries the
colour; the tint is a *separate* selector:

```
GCOL 0,c%                        c% = 0-63
VDU 23,17,2,t,0,0,0,0,0,0        t = 0, 64, 128 or 192
```

`r` in `VDU 23,17,r` is 0 text foreground, 1 text background, 2 graphics
foreground, 3 graphics background.

| Observed | |
|---|---|
| 64 colours × 4 tints, tint set properly | four bands, **hue preserved at every tint**, progressively lighter. 256 usable shades. |
| `GCOL 0,n` for n = 0-255, no tint call | colour to about n=112, then **uniformly near-white**. This is what looked like saturation in `palette.bas`. |
| `VDU 19,l,16,r,g,b` | **works** — the 16 low-bit palette entries are programmable, and the change is retroactive on what is already displayed. |

**Rule for the terminal: use `GCOL 0-63` plus the tint call, never a GCOL
number above 63.** Driving colour and tint from one number is what washes the
top of the range out.

**Consequences for `TERM`:**

- xterm's **16 ANSI colours can be exact** — `VDU 19` reprograms 16 entries.
- The other 240 need a **nearest-colour lookup** into the 64 × 4 space, computed
  once on the Linux side and baked in as a 256-byte table. Not a per-character
  cost, but it has to exist. `xterm-256color` is honest to advertise; a
  pixel-exact match is not on offer.

**SUPERSEDED FOR THE FRAMEBUFFER PATH, 2026-08-20 — `test/fbpal2.bas` on copro
15. There are 256 real palette entries.** Entry 200 was reprogrammed and changed
on screen while entry 8 — what 200 becomes under a mod-16 wrap — did not, by
`VDU 19` and by `OS_Word 12` independently, with a positive control on entry 4
run first. So a byte poked into the framebuffer selects one of **256
individually programmable entries**, the nearest-colour table above is never
written, and `xterm-256color` is *exact* for anything rendering its own pixels.

This does **not** touch the paragraph above it. That was measured through
`GCOL`, which is the driver's colour selection, and 64 colours × 4 tints remains
what `GCOL` offers. `BEEBTERM` renders that way and gains nothing here; `FBVDU`
(`docs/fbvdu.md`) owns the pixels and gains everything.

**`OS_ReadPalette` cannot measure it either — it is a stub.** Read on hardware
2026-08-20 by `test/fbpal.bas`: the SWI returns without error and writes
nothing, 1024 reads across four dumps all zero, including after the palette had
just been reprogrammed. A call that does not error is not the same as a call
that is implemented, and PiTubeDirect implements only a subset. Check returned
*values* before believing a SWI, here and anywhere else in this project.

**`POINT` cannot measure this.** It returned "63 of 256" on *both* the tinted
grid and the flat sweep — it reports the colour number and never the tint, so
the count says nothing about how many shades are actually distinct. The visual
result is the evidence here. Do not reach for `POINT` as an instrument again.

### 2.3a Owning the renderer is possible — the framebuffer address is exposed

Read from PiTubeDirect source 2026-08-19 (`src/framebuffer/`), against the
question of whether a VT written in ARM code could bypass the VDU driver:

| Fact | Where |
|---|---|
| `OS_ReadVduVariables` is implemented | `swi_impl.c`, `os_table[SWI_OS_ReadVduVariables]` |
| VDU variable **148 (&94) `V_SCREENSTART`** returns `get_fb_address()` | `framebuffer.c` |
| **150 (&96)** returns `height * pitch`; pitch, width, depth are all mode variables | `framebuffer.c` |
| Fonts ship with the driver | `src/framebuffer/fonts/` |

Copro 15 runs bare metal **on the Pi itself**, so that address is directly
writable — no Tube crossing, no VDU driver in the path.

`test/fbtest.bas` turns this from a reading of the source into something
visible: it asks `OS_ReadVduVariables` for 148 and 150 plus pitch, size and
depth, checks that size equals pitch x height, and then pokes a 64x64 block and
a diagonal straight into memory. In an 8bpp mode one byte is one pixel and its
value is the colour number, so a marker no VDU call could have drawn is proof
of both the address and the palette. **ARM native only** — `SYS` and 32-bit
addresses do not exist on the 6502 co-processors.

**CONFIRMED ON HARDWARE 2026-08-19.** `fbtest` on copro 15, MODE 21:

```
screen start   &1F8B0000
screen size    327680 bytes
bytes per line 640
bits per pixel 8
implied height 512 pixel rows
```

640 x 512 x 8bpp = 327,680 exactly. A 64x64 colour block and a 200-pixel
diagonal, poked byte by byte from **BASIC**, appeared on screen — and took
**0 cs**, i.e. under 10ms for ~4300 writes.

That last number changes the plan. A full 80x64 screen of 8x8 cells is 327,680
pixel writes, which at that rate is under a second — and with `!` word writes
instead of `?` it is four times fewer, and with damage tracking a `top` refresh
touches a few hundred cells rather than the whole screen. **So the renderer may
not need assembler at all**, and the trade below is much cheaper than assumed:
the fast edit-test loop can be kept.

(One correction to the probe's own output: it prints `text window 2 x 2
characters` because VDU variables 4 and 5 are the eigen factors, not the text
window size. Harmless — the numbers that matter are the address, pitch and
size.)

**So the question is now a trade, not a feasibility problem.** Owning the
renderer buys exact VT semantics by construction: pending wrap, scrolling
regions, an alternate screen that actually restores (impossible today — there is
no second buffer, §9.3), and reading the screen back for free. Every rendering
defect found on 2026-08-19 came from the VDU driver's semantics, not from the
terminal's logic.

What it costs is ARM assembler or C in place of BASIC, and with it the
seconds-long edit-test loop that made that day's debugging possible at all.
**It is not a performance argument** — §5.5d measures the display at 20x the
network. §8 Step 3 is where this is decided.

Constraints that follow from "bare metal":

- No TCP/IP stack on the Pi.
- Pi 3A+ has **no Ethernet port**; onboard WiFi is not usable from bare-metal
  firmware. The Pi cannot reach the network on its own.

---

### 2.4 Co-processor selection

PiTubeDirect emulates many cores, switchable with `*FX 151,230,N` followed by
**CTRL-BREAK**. The machine prints its own list — `*BASIC` then `CALL &2000` on
the co-processor — and marks the current selection with `*`. Read off the screen
2026-08-19; this supersedes both the wiki (years out of date) and a reading of
`src/copro-defs.c` on master, which had **8** as 80286 and **23** as hidden:

| # | Core | # | Core |
|---|---|---|---|
| 0 | 65C02 (fast) | 14 | Disable |
| 1 | 65C02 (3MHz), throttled (`copro1_speed`) | 15 | **ARM Native** |
| 2 | **65C102 (fast)** | 16 | LIB65C02 64K |
| 3 | **65C102 (4MHz)**, throttled (`copro3_speed`) | 17 | LIB65C02 256K Turbo |
| 4–7 | Z80 1.21 / 2.00 / 2.2c / 2.30 | 18/19 | 65C816 (Dossy / ReCo) |
| 8 | 80186 | 20–22 | OPC5LS / OPC6 / OPC7 |
| 9 | MC6809 | 23 | RISC-V |
| 11 | PDP-11 | 24 | **65C02 (JIT)** |
| 12 | ARM2 | 28 | Ferranti F100-L |
| 13 | 32016 | 10, 25–27, 29–31 | Null / hidden |

`copro=24` in the shipped `cmdline.txt` is the 65C02 JIT core — the fastest
6502 — not an undocumented value.

**Copros 1 and 3 are deliberately throttled.** `get_copro_mhz()` applies a
speed limit only to `TYPE_65TUBE_1` and `TYPE_65TUBE_3`; 0 and 2 run flat out.
So copro 3 is a period-accurate 4MHz 65C102 while copro 2 is the same core
unthrottled.

**CLOSED 2026-08-19.** It was unrecorded whether §5.5c's figures came from copro
2 or copro 3, which mattered because a throttled measurement would have made
3082 bytes/sec pessimistic. Re-run on copro 3: **no material difference**, if
anything marginally faster. So the throttle is not the bottleneck at these
rates — the Tube round trip and the module are — and **3082 bytes/sec stands for
both cores**. Copro choice can now be made on other grounds.

Two candidates matter for this project:

- **2 / 24** — fastest 6502 cores. BASIC IV (the host's ROM image), 64K.
  Everything proven so far (§5.5c) was proven on a 6502 core.
- **15, ARM Native** — BBC BASIC V at full core speed, and `*PIVDU` for
  framebuffer routing. This is what §8 Step 2 targets. BASIC V's `CASE`,
  `WHILE` and string handling make a VT102 parser far less painful.

**Before committing to 15:** the §5.5c pointer-crossing result was demonstrated
on a 6502 core, where the OSWORD control block pointer is a 16-bit address in a
space the host understands. On native ARM it is a 32-bit ARM address, and
whether the tube host translates it is unproven. Re-run `tubetest.bas` on 15
before writing anything for it.

**CLOSED 2026-08-20, ON HARDWARE, THE GOOD WAY.** `test/ptrtest2.bas` on
copro 15 under `*ARMBASIC`, against a listener that says
`PTRTEST-MARKER-42` on connect. There is no `CALL &FFF1` on ARM — the route is
`SYS "OS_Word",&C0,block`.

```
page=&8F00
lo_sa=&A444   lo_buf=&A474        below 64K
hi_sa=&1A6A0  hi_buf=&1A6D0       above 64K

lo_connect +2=0 +3=0 tries=1      lo_out=YES
lo_recv reported=16 changed=1 of 16
lo_buf=34 55 55 55 55 ...          lo_in=YES

hi_connect +2=0 +3=0 tries=1      hi_out=YES
hi_recv reported=16 changed=1 of 16
hi_buf=34 55 55 55 55 ...          hi_in=YES
```

**Pointers cross the Tube on copro 15, in both directions, at both address
ranges.** `Socket_Connect` read a 16-byte sockaddr out of ARM memory — it could
not have connected otherwise — and `Socket_Recv` wrote into ARM memory. Full
32-bit ARM addresses are honoured; the `&1Axxx` buffers behaved exactly as the
`&Axxx` ones did, so nothing is truncating to sixteen bits.

**§8 Step 1 stays cancelled.** `BEEBNET` is not needed for copro 15 any more than
it was for the 6502, and `PTERM` can call OSWORD &C0 directly.

**Read `changed=1 of 16` carefully — it is a stronger result than it looks.** The
probe reads one byte per call and **passes the same buffer address every time**,
so all sixteen reads land on byte 0 and only byte 0 can change. What makes it
proof is the *value*: `&34` is `4`, and `4` is the **sixteenth character** of
`PTRTEST-MARKER-42`. The byte that arrived is the byte that was predicted, at an
address chosen by the ARM. A truncated or ignored pointer cannot produce that.

**Why the first run, `test/ptrtest.bas`, said `ptr_out=NO`.** Not the addresses —
`ptrtest2` connected from `&1A6A0` first time. Two candidates remain: it failed
connect on the first non-zero `+3`, and `&1E` is *"cannot satisfy the request"*
(§5.5c), not a refusal; and the listener may not have been up. `ptrtest2` connects
at `tries=1`, so the retry was never exercised — which leaves **the listener as
the most likely cause**, and it is the case the test explicitly warns about.

The general lesson is the one §5.5c already teaches in a different form: *an
experiment that changes two things at once answers neither.* `ptrtest` moved
every buffer above 64K **and** asked whether pointers cross, so its failure was
unreadable. `ptrtest2` holds the call fixed and varies only the address.

### 2.5 Getting files onto the machine

**CONFIRMED 2026-08-19: LANManFS catalogues the share and loads from it.** The
Beeb mounts a Samba share on the Linux box — `tools/setup-samba.sh`, and read
its security warning, it re-enables SMB1 and LANMAN auth — so there is no disc
drive in the loop and no serial link to babysit.

- Programs are written in `test/` and mirrored to `share/` with
  **`tools/mirror.sh`**, which enforces the two rules that fail on the machine
  rather than on the host: an **uppercase name of 8 characters or fewer**, and
  **CR line endings**, not LF. Do not use `cp`. An LF-terminated file has no
  line terminator as far as `*EXEC` is concerned, so the whole file is poured
  into a 238-byte input buffer: a few echoed lines appear and the machine locks
  up. VDUTEST, PALETTE and MANDEL were all mirrored with `cp` and all three
  behaved this way on 2026-08-19.
- On the Beeb: `NEW` then `*EXEC <NAME>` types the program in, then `RUN`.
- **Faster: `tools/mirror.sh --tok`, then `CHAIN "<NAME>"`.** `*EXEC` feeds text
  through the input stream one character at a time and BASIC tokenises each line
  as it arrives; `tools/bastok.py` does that tokenising on the Linux side, so
  the machine only has to read a file. §6.4 measured `LOAD` at 14 KB/sec, which
  puts the whole 50K engine on in about three and a half seconds. Under the
  emulator the same change took a run from **three to five minutes down to eight
  seconds**, which is most of why phase 3 is affordable at all.

  A tokenised file must be **`CHAIN`ed, not `*EXEC`ed** — `*EXEC` on one would
  pour tokens into the input buffer. `mirror.sh` without `--tok` still writes
  text, and prints the command to use either way.

  **The token table was dumped out of ARM BASIC V, not written from a book**,
  and `tools/bastok-diff.py` checks the result against the machine's own `SAVE`
  of the same source: currently **1673 of 1673 lines byte-identical**. Three
  things a hand-written table would have got wrong, each of which produced a
  program that loaded and then failed somewhere else entirely:

  - In BASIC V the command keywords `LOAD SAVE LIST NEW DELETE RENUMBER AUTO
    OLD EDIT` are **two-byte `C7 xx`** tokens, not the single bytes BASIC IV
    uses, and `SYS` is `C8 99`.
  - `PTR PAGE TIME LOMEM HIMEM` and `ELSE` have **two tokens each**, chosen by
    context: `PAGE` is `&90` in an expression and `&D0` as an assignment target,
    `ELSE` is `&8B` inline after a `THEN` and `&CC` starting a statement. A
    keyword probed *alone on a line* gives the statement form — which is how
    `~PAGE` came back as *Unknown or missing variable*.
  - A literal line number after `GOTO GOSUB RESTORE THEN ELSE` is encoded as
    `&8D` and three bytes. Derived from the machine's own output rather than
    assumed: `RESTORE 2140` came back as `8D 44 5C 48`.
- Binaries work too, with the load address supplied by hand — LANManFS has
  nowhere to keep load/exec addresses, so `*RUN` over the share will not work.
  See `docs/ssd-to-beeb.md`.
- **Booting straight to the share** — `docs/cmos-config.md` §8. `*CONFIGURE
  FILE` and `LANG` take **ROM numbers**, not filing system ids (CMOS byte 5 is
  "default filing system ROM number" / "default language ROM number", which is
  why `*CONFIGURE FILE 9` selects DFS), so LANManFS *can* be the boot filing
  system even though its filing system id of 102 would never fit in a nibble.
  What CMOS cannot do is mount: `*MOUNT` is a command, and the module's manual
  says "the only valid boot option for shared discs is zero (off)", so no
  `!BOOT` will ever run from it. `test/fbboot.bas` captures the ROM numbers —
  **BASIC is ROM 12, the network ROM is ROM 8** — and proves the network needs
  nothing from CMOS at all: every `EM*`/`Gateway`/`DNS` setting reads `Unset`
  while `*EMINFO` shows a working DHCP-supplied stack.
- **The module's `Choices:Internet.Startup` is OSFile-only.** It lives in NVRAM
  on the module, and LANManFS diverts *only* OSFile to it — so `*TYPE` and
  `*EDIT`, which use OSFind/OSBGet, both answer "Bad name", including the
  `*EDIT` route the module's own manual gives. `test/fbnet.bas` reads it with
  OSFile 5 and 255; OSFile 0 writes it back.

---

### 2.4 The co-processor list, read off the machine

`*FX 151,230,N` selects the core; the menu marks the current one with `*`.
Captured from the hardware 2026-08-23 (`pictures/PXL_20260823_142035694.png`),
because **the project wiki's list is out of date and contradicts the machine.**
The photo is the **BBC's own RGB output into the TV's SCART input, in MODE 7** —
not the Pi's HDMI framebuffer.

| # | core | | # | core |
|---|---|---|---|---|
| 0 | 65C02 (fast) | | 14 | Disable |
| 1 | 65C02 (3MHz) | | 15 | **ARM Native** |
| **2** | **65C102 (fast)** | | 16 | LIB65C02 64K |
| 3 | 65C102 (4MHz) | | 17 | LIB65C02 256K Turbo |
| 4-7 | Z80 (1.21 / 2.00 / 2.2c / 2.30) | | 18 | 65C816 (Dossy) |
| 8 | 80186 | | 19 | 65C816 (ReCo) |
| 9 | MC6809 | | 20-22 | OPC5LS / OPC6 / OPC7 |
| 11 | PDP-11 | | 23 | RISC-V |
| 12 | ARM2 | | 24 | 65C02 (JIT) |
| 13 | 32016 | | 28 | Ferranti F100-L |

There is no 10. **Entry 0 is `65C02 (fast)`** and is not visible in the photo
because MODE 7 is 25 rows and the list is longer, so it scrolled off the top —
nothing to do with overscan.

**The wiki claims copro 2 is "lib6502-based 65C02" and copro 0 the "fastest
65C102".** The machine says the opposite way round: **0 is `65C02 (fast)`, 2 is
`65C102 (fast)`**, and LIB65C02 is 16/17. **Trust the menu.** `test/tuberate.bas:260` has always labelled `*FX 151,230,2` as the
65C102 and is correct.

Note **24 is `65C02 (JIT)`** — the core in upstream issues #126 and #141, and
not one this project has ever run.

### 2.5 What `cmdline.txt` actually parses

Every option, from `get_cmdline_prop()` in `src/tube-client.c` plus the two the
parser reads elsewhere. **This card's values are in the last column.**

| option | default | limit | what it does | ours |
|---|---|---|---|---|
| `copro` | build default | a valid core | core at boot | **15** |
| `copro1_speed` | 3 | 255 | MHz for core 1 | 3 |
| `copro3_speed` | 4 | 255 | MHz for core 3 | 4 |
| `copro8_memory_size` | 0 | 32 MB | RAM for the 80x86 | absent |
| `copro13_memory_size` | 0 | 32 MB | RAM for the 32016 | absent |
| `tube_delay` | 0 | 40 | Tube ULA sampling delay | **25** |
| `vdu` | **0 = OFF** | | enables the Pi framebuffer | **1** |
| `elk_mode` | 0 | | patches the Z80 ROM's Tube addresses to the Electron's `&FCEx` | 0 |

**`vdu=1` IS NOT THE DEFAULT.** PiTubeDirect ships with the framebuffer
disabled, and **FBVDU cannot work without it**. Do not lose that line when
editing `cmdline.txt`.

**`copro1_speed` and `copro3_speed` are visible on the machine.** The menu in
§2.4 renders them: entry 1 reads `65C02 (3MHz)`, entry 3 reads `65C102 (4MHz)`.
The values match real hardware — 3 MHz was Acorn's external 6502 second
processor, 4 MHz the Master's internal 65C102. **Entry 2, `65C102 (fast)`, has
no speed parameter**: same emulation with the throttle off, which is why it is
the one to use.

**`tube_delay` runs on the GPU, not the ARM.** The Tube ULA emulation lives on
the Pi's VideoCore, and `src/tube-ula.c` passes the value to the VPU through a
mailbox call at launch (`TAG_LAUNCH_VPU1`):

```c
extern unsigned int tube_delay;
r2 = tube_delay;
```

The comments there say why: the Tube registers are kept out of cached memory
because **predictable** timing matters more than fast timing, and the VideoCore
can hold a budget the ARM cannot. `tube_delay` shifts when that code samples the
data bus relative to the host's strobe, compensating for propagation delay
through the level shifting and GPIO. Sample early and the data is not valid yet;
sample late and it has gone. Either way a wrong or missing byte, whose
documented symptom is **the parasite waiting forever for a byte that already
went past** — this project's exact freeze signature.

The units are in the VideoCore assembly, not the C, so whether 25 means cycles
or something coarser is not established here.

`config.txt` also has `os_prefix=debug/`, shipped commented out, which selects a
debug kernel with interactive co-processor debuggers. It needs a 115200 serial
connection to be of any use.

**The wiki is stale on this page too.** It still says *"0 for the fastest 65tube
based 65C102 ... 2 for the lib6502 based 65C02"*, which §2.4's menu contradicts.
Second independent case in one day of the wiki disagreeing with the machine.

## 3. Architecture (decided)

### 3.0 Connection direction

**The BBC Master is always the client.** It initiates outbound TCP connections
to other machines. It never listens and never accepts inbound connections.

`Socket_Bind`, `Socket_Listen` and `Socket_Accept` are **out of scope**, as is
the module's bundled web server example. Nothing on the LAN connects *to* the
BBC.

### 3.1 Internal stack

```
       ┌────────────────────────────────────────────────┐
       │ BBC Master 128 (host, 2MHz 65C12)              │
       │   • Sprow module — OSWORD &C0 sockets          │
       │   • Keyboard                                   │
       │   • no 6502 code at all — BEEBNET cancelled    │
       └───────────┬────────────────────────────────────┘
                   │ Tube
       ┌───────────┴────────────────────────────────────┐
       │ Pi 3A+ co-processor                            │
       │   • PTERM in BASIC V: pump, VT102, render      │
       │   • SSHBLOB in C: crypto, packets, inflate     │
       │     — sans-IO, so BASIC keeps the socket       │
       └───────────┬────────────────────────────────────┘
                   │
         HDMI MODE 21: 640×512, 256 colours
```

### 3.2 Network flow (BBC outbound)

```
  BBC Master ──── SSH-2, outbound ─────► any machine running sshd
                  curve25519-sha256
                  ssh-ed25519 host key
                  chacha20-poly1305
                  zlib, server->client
```

**Superseded 2026-08-28.** This was telnet in plaintext, with `ssh` onward
from a jump host, because "modern SSH key exchange on a 2MHz 6502 is not
viable" (§3.5). That was true and was about the wrong processor: the terminal
runs on copro 15, where X25519 costs under a millisecond. The telnet path
still works and is still the fallback — `ssh%=FALSE` in `src/pterm.bas`.

### 3.3 Division of responsibility

| Component | Runs on | Responsibility |
|---|---|---|
| Network transport | BBC host | Sprow module, OSWORD &C0 sockets — driven **directly from the co-processor**, since pointers cross the Tube (§5.5c) |
| ~~`BEEBNET` ROM~~ | — | **Cancelled.** No host-side code is required (§8 Step 1) |
| Keyboard | BBC host | Read keys, pass to co-pro over Tube |
| Terminal emulation | Pi co-pro | VT102 parsing. **Telnet IAC only when `ssh%=FALSE`** — under SSH there is no IAC layer and 255 is an ordinary byte |
| SSH transport | Pi co-pro | `SSHBLOB`, ~48KB of C: key exchange, packet crypto, inflate. **Sans-IO** — it never touches the socket |
| Rendering | Pi co-pro | Draw to Pi framebuffer via Pi VDU driver |
| Display | Pi | HDMI, MODE 21 — 640×512, 256 colours |
| ~~SSH~~ | ~~LAN jump host~~ | **Superseded 2026-08-28.** The client speaks SSH itself. `tools/sshgate.sh` remains for the telnet path |

### 3.4 Rationale

Rendering happens on the Pi, into the Pi's own framebuffer, and therefore does
not cross the Tube. The 2MHz 6502 is removed from the render path entirely.

Both the network endpoint and the keyboard are on the host, so those *do* cross
the Tube — but at human/serial data rates, not screen-repaint rates.

### 3.5 Reaching target machines

No crypto on the BBC. Modern SSH key exchange on a 2MHz 6502 is not viable, so
the BBC speaks **plaintext telnet outbound only**. Each machine it logs in to
must therefore accept telnet.

**Normal case — the target accepts telnet directly.** The BBC connects to it and
gets a login. No SSH involved at all. Any target willing to run `telnetd`, or
this shim, is reachable directly:

```
sudo socat TCP-LISTEN:2323,reuseaddr,fork,bind=<lan-ip> SYSTEM:'stty rows 64 cols 80; TERM=xterm-256color exec /bin/login',pty,stderr,setsid,ctty
```

**One line, and it has to be.** This was written across three lines with
backslash continuations and **did not work** — `E exactly 2 addresses required
(there are 3)`. `pty,stderr,setsid,ctty` are options *on* the `SYSTEM:` address,
not a third address, and a continuation keeps the leading whitespace of the next
line, so the shell hands socat `SYSTEM:'...',` and `pty,stderr,setsid,ctty` as
two separate words. If it must be wrapped, break only at a space that is already
there and start the next line in column 1 — never inside the comma-separated
option list.

**`SYSTEM:`, not `EXEC:`** — socat's `EXEC:` splits on whitespace and does not
run a shell, so the `;` and the assignment would be passed as arguments.

**`stty rows 64 cols 80` is still needed here even though PTERM implements
NAWS.** socat is a raw TCP-to-pty bridge, not a telnet server: no `IAC` is ever
sent, so the negotiation never happens and the far end never learns the size.
PTERM's IAC layer only ever *responds*, never initiates, so nothing is injected
into the shell either. Against a real `telnetd` the NAWS exchange does happen and
the `stty` becomes unnecessary.

Note this execs a **login prompt**, not a fixed destination — the BBC chooses
who it logs in as.

Three things this line has to get right, each found the hard way on 2026-08-19:

- **`sudo`.** `/bin/login` is 755 and not setuid, so as an ordinary user it
  cannot read the shadow file and exits 1 — *silently*. All socat reports is
  `child NNNNN exited with status 1`.
- **`TERM`.** A raw pty does no terminal negotiation, so nothing else tells the
  far end what the BBC is. Without this, curses applications get it wrong or
  refuse to start.
- **`bind=`.** Unqualified, socat listens on every interface. If the host has a
  VPN or tailnet address, an unauthenticated shell would be reachable from it.

For a first end-to-end test, `bash -l` without `sudo` avoids sending a password
across the LAN in clear — at the cost of an unauthenticated shell for anyone on
that LAN. Neither form should outlive the session it was started for.

```
socat TCP-LISTEN:2323,reuseaddr,fork,bind=<lan-ip> SYSTEM:'stty rows 64 cols 80; TERM=xterm-256color exec /bin/bash -l',pty,stderr,setsid,ctty
```

**`/bin/login` SERVES NOTHING ON THIS MACHINE, 2026-08-20** — and it is the form
this section recommends, so read this before losing an evening to it. PTERM
connected, `Socket_Connect` returned success, and not one byte ever arrived. The
fault is entirely server-side and it reproduces from the Linux box itself:

| served command | what a client receives |
|---|---|
| `stty rows 64 cols 80; echo hello` | `hello` |
| `TERM=xterm-256color exec /bin/bash -l` | a full shell prompt |
| `exec /bin/login` | **nothing** |

So the pty plumbing is right and `pty,stderr,setsid,ctty` is right; `login` is
what does not speak. The socat children do not exit either — they sit there — so
it is not §3.5's silent `exit 1`, which is the *non-root* failure. Use `bash -l`
until someone works out why.

**Diagnosing this from the Beeb is the wrong end.** `socat STDIO TCP:<ip>:2323`
from the Linux box answers in one command whether anything is being served at
all, and separates "the terminal is broken" from "the far end is silent".

**SUPERSEDED 2026-08-27 by `tools/sshgate.sh`** — see `docs/ssh.md`. The
listener now serves a destination picker instead of a shell, and the
*gateway* makes the onward ssh hop with its own key, refusing password and
keyboard-interactive auth so a credential cannot be prompted for over the
cleartext link. The consequence below — "credentials typed at the BBC cross
the LAN in the clear" — no longer holds, because the BBC no longer types
any. The `bash -l` line above remains the right thing for a bare transport
test.

**Fallback — the target will not accept telnet.** Connect to any LAN machine
that will, and `ssh` onward *from that shell*. The onward hop is chosen
interactively at the BBC keyboard, not baked into a listener.

Consequences:

- The BBC must be able to reach **multiple** machines. Do not hardcode a single
  destination in a socat `EXEC:`. Either the target runs telnetd/the shim above,
  or you reach a shell and ssh from there.
- Destination selection belongs in the **terminal client** (a host/port prompt
  at startup), not in the LAN-side configuration.
- Accepted trade-off: telnet is cleartext, confined to the home LAN. Credentials
  typed at the BBC cross the LAN in the clear.

---

## 4. Reference: OSWORD &C0 (192) sockets API

Control block:

| Offset | Size | Field |
|---|---|---|
| +0 | 1 | send block length |
| +1 | 1 | receive block length |
| +2 | 1 | command (0–63 socket, 64–127 resolver, 128+ reserved) |
| +3 | 1 | result — 0 = success, non-zero = error |
| +4 | 4 | socket number / domain |
| +8 | 4 | buffer or name pointer |
| +12 | 4 | length |
| +16 | 4 | flags |
| +20 | 4 | IP address pointer |
| +24 | 4 | IP address length (0 = IPv4 at +20) |

**THE TWO ROWS ABOVE ARE WRONG FOR THE RESOLVER, and cost a run on
2026-08-28.** They describe the socket calls. `docs/netprogapi.pdf` is
authoritative and says something different for `Resolver_GetHostByName`:

| | |
|---|---|
| entry | `+8` = pointer to the name |
| exit | `+12` = address **type** (2 = AF_INET) |
| | `+16` = address **length** (4 = IPv4) |
| | `+20` = pointer to a **null-terminated list of pointers** to addresses |

So `+12` and `+16` are outputs, not inputs; there is no `+24`; and getting an
address takes **two** indirections. Supplying a buffer at `+20` and reading it
back returned `32.32.32.32` — four spaces of uninitialised memory, after the
module had written its own pointer over the field.

**MEASURED 2026-08-28, and then solved.** The call succeeds — `+3` zero, `+12`
returning 2 for AF_INET, `+16` returning 4 for IPv4, so the control block
crosses the Tube intact — but the pointer at `+20` dereferences to **zero** on
the co-processor. §5.5c's "pointers cross the Tube" is about buffers *we*
supply, which the Tube protocol copies; a pointer the module hands back is a
**host** address and nothing carries the bytes behind it.

**The module's DNS itself is fine** — `*MOUNT \\deskbox\\beeb` resolves with no
`HOSTS` file. Only the answer was unreachable.

**OSWORD 5 is the mechanism**, and it is in the Advanced User Guide §18.9:
*"read i/o processor memory … a 4 byte i/o processor address. The byte read is
returned in the last byte of the block."* Two indirections is eight of those
calls, and `FNresolve` in `src/pterm.bas` does exactly that.

PTERM tries `HOSTS` on the share first and the resolver second — the order a
Unix box uses, and for the same reason: the file is the local override.

Commands needed for this project:

| Code | Name | Use |
|---|---|---|
| &00 | Socket_Creat | create TCP socket |
| &04 | Socket_Connect | connect to target host |
| &05 | Socket_Recv | read inbound data |
| &08 | Socket_Send | write keystrokes |
| &10 | Socket_Close | tear down |
| &40 | Resolver_GetHostByName | hostname → IP |

**NOT AVAILABLE.** `netprogapi.pdf` lists these as unsupported, and hardware
confirms it - `Socket_Ioctl` returns error 88 on the real module:

| Code | Name | Note |
|---|---|---|
| &11 | Socket_Select | "Not supported, returns an error" |
| &12 | Socket_Ioctl | "Not currently supported" - so **no FIONBIO** |
| &06/&07 | Socket_Recvfrom / Recvmsg | unsupported |
| &09/&0A | Socket_Sendto / Sendmsg | unsupported |
| &0C/&0D | Socket_Setsockopt / Getsockopt | unsupported |
| &0E/&0F | Socket_Getpeername / Getsockname | unsupported |
| &13-&17 | Read/Write/Stat/Readv/Writev | unsupported |

**Consequence: non-blocking I/O is only achievable with the `MSG_DONTWAIT`
flag (8) passed at `YX+16` on each `Socket_Recv`.** There is no way to
configure the socket itself as non-blocking, and no `select()`. A terminal
main loop must therefore poll `Socket_Recv` with `MSG_DONTWAIT` rather than
waiting on readiness.

Client-side only. `Socket_Bind` (&01), `Socket_Listen` (&02) and
`Socket_Accept` (&03) are **not used** — see §3.0.

### 4.1 AUTHORITATIVE: Sprow's netprogapi.pdf

**Found 2026-08-18 at `sprow.co.uk/bbc/hardware/masternet/netprogapi.pdf`**
(copy in `docs/netprogapi.pdf`). This is the real programmer's reference and it
supersedes the inferences below. Key points:

- **OSWORD 192 (&C0) is correct.**
- The API is provided by the **LANManager** ROM, *not* LANManFS. The doc states
  explicitly that LANManFS need not even be the selected filing system.
- **`YX+3` must be ZERO on entry.** Putting anything else there breaks the call.
- **`YX+2` is set to zero on exit.** This is the documented presence test:
  issue `Socket_Close` with socket `-1` and check whether `+2` changed.
- `YX+0`/`YX+1` are the send/return block lengths and are *required* - they tell
  the Tube software how big the block is. Example lengths are small (16/8 for
  `Socket_Bind`), not the 28/28 used in early drafts here.
- Exit convention: `YX+4 = -1` on failure, otherwise the socket number or byte
  count. `YX+3` = 0 for OK, else an error number.
- Subreason ranges: &00-3F socket, &40-7F resolver, &80-FF reserved.

**sockaddr, confirmed:**

| Offset | Field |
|---|---|
| sa+0 | size of socket address (usually 16) |
| sa+1 | address family (2 for AF_INET) |
| sa+2 | port number |
| sa+4 | IPv4 address |
| sa+8 | zero |

`Socket_Creat`: domain 2 = PF_INET; type 1 = stream, 2 = datagram, 3 = raw.

**Send/Recv flags:** `MSG_PEEK`=1, `MSG_DONTWAIT`=8, `MSG_MORE`=16. Only these
three are supported. `MSG_DONTWAIT` may remove the need for the `FIONBIO` ioctl.

**A READ ABOVE ABOUT 64 BYTES IS NOT RELIABLE, 2026-08-20 (`test/fbsize.bas`).**
A hundred peek-then-read cycles at each size against a saturated socket, counting
the reads the module refused *after its own peek had said the bytes were there*:

```
size  asked   ok   refused   worst refused
1,2,4,8,16     100   100   0
32, 64          46    46   0
128             35    33   2      88
```

**And a refusal is not a refusal — the module consumes the bytes and then reports
failure.** That is how 111 bytes went missing from the middle of a live session
and printed an escape sequence as text on the screen. `PTERM` uses 64, counts
every refusal, and halves its ceiling whenever one happens, because silent
corruption is much worse than being slow.

**`MSG_PEEK` MEASURED ON HARDWARE 2026-08-20 (`test/fbpeek.bas`), and it is what
makes a fast read safe.** Three answers, all of them the useful way:

```
peek 8      n=8   [ABCDEFGH]    a peek returns data
peek 8      n=8   [ABCDEFGH]    the same bytes again - NON-DESTRUCTIVE
peek 200    n=116               an over-asked peek REPORTS, it does not refuse
recv 8      n=8   [ABCDEFGH]    the real read still sees everything
recv 8      n=8   [IJKLMNOP]    and the recv did consume
```

The third line is the one that matters. `Socket_Recv` loses the difference when
asked for more than the module holds, so the read size may never be a guess — but
an **over-asked peek reports what it found** (116 when 200 were asked for), so one
peek sizes the next read exactly:

```
peek rmax bytes  ->  a = how many are really there
recv exactly a   ->  nothing is ever over-asked
```

Two Tube round trips per read instead of one, for up to 128 bytes instead of one.
That is the difference between a terminal that is correct at 72 bytes/sec and one
that is correct at full speed.

Not supported at all (return errors): several socket options and calls - check
the doc before relying on any call beyond the basics.

Every layout guess made earlier turned out correct. The **conventions** did not:
see §5.6.

### 4.2 The stack is lwIP

The Master 10/100 Net User Guide's copyright page credits Adam Dunkels, the
Swedish Institute of Computer Science, Leon Woestenberg and Marc Boucher —
that combination is **lwIP**. The manual does not document the socket API, but
knowing the stack pins down the conventions §4 was guessing at, because lwIP's
sockets layer is a straight BSD implementation:

| Item | lwIP value | Our assumption | Match |
|---|---|---|---|
| `sockaddr_in` | `sin_len` byte at +0, family +1, port +2 big-endian, addr +4, 16 bytes | same (BSD 4.4) | yes |
| `AF_INET` | 2 | 2 | yes |
| `SOCK_STREAM` | 1 | 1 | yes |
| `FIONBIO` | &8004667E | &8004667E | yes |
| Errors | negative return | negative return | yes |

**Every guess in `nettest.bas`, `SOCKSTUB` and `BEEBTERM` is consistent with
lwIP.** This is strong supporting evidence, not verification — it is inference
from a copyright notice, and the OSWORD wrapper Sprow put around lwIP could
still differ. Step 0a on hardware remains the decider, but the expected outcome
is now "confirms what we built" rather than "tells us what to build".

---

## 5. Host-side network ROM

A sideways ROM on the host is a **required component**, not an optimisation.
Working name: `BEEBNET`.

### 5.1 Why it is required

OSWORD calls with A > &7F use a Tube convention where byte +0 is the send
length and byte +1 the receive length. The OSWORD &C0 block matches this
layout, so **the control block itself transfers across the Tube correctly.**

But the Tube copies only the control block — *not* the memory it points at.
`Socket_Recv` passes a buffer pointer at +8, so:

- a co-pro address in +8 is meaningless to the host;
- a host address leaves received data stranded on the host side.

**Confirmed by netprogapi.pdf:** the send/return lengths at `YX+0`/`YX+1`
"instruct the Tube software how big the block is when the OSWord is issued from
a coprocessor", and "due to a limitation in the host side of the Tube software
these values cannot exceed **128 bytes** in either direction."

So the control block *does* cross the Tube, with a hard 128-byte ceiling - not
the ~250 estimated earlier. But the doc says nothing about the pointed-to
buffers, and `Socket_Recv` still takes a pointer at `+8`. The pointer problem is
therefore unresolved and remains the reason `BEEBNET` is needed.

There is no documented configuration of the stock API that gets socket payload
from the host to the co-processor. Host-resident code is unavoidable.

### 5.2 Performance budget — the Tube is not the bottleneck

Estimates, to be measured rather than trusted:

| Path | Capacity |
|---|---|
| Tube block transfer (R3, type 6/7), host-6502-bound | ~100–200 KB/s |
| Busy full-screen TUI repainting hard at 80×60 | tens of KB/s peak |
| Typical Claude Code traffic | a few KB/s |

Roughly 50× headroom. **Raw Tube throughput needs no optimisation.** The
quantity that matters is *calls per second and bytes per call*, not bytes per
second: at ~250 bytes inline per response, 40 calls/sec already covers 10 KB/s.

### 5.3 Design

The ROM owns the socket. The co-processor never sees a pointer.

- **Read-ahead ring buffer in host RAM.** The ROM fills it from the socket
  independently of co-pro demand. This decouples co-pro polling from module
  access: empty polls become cheap, full ones return a maximal chunk.
- **Inline payload only.** A custom OSWORD carries data in the request/response
  block itself. **Cap it at 128 bytes** - that is the documented Tube limit.
- **Batching.** Always return the largest chunk available, never a byte at a
  time.

Exposed actions (sketch):

| Action | Direction | Payload |
|---|---|---|
| Open | co-pro → host | hostname/IP + port; resolves and connects |
| Read | host → co-pro | up to ~250 bytes inline from the ring buffer |
| Write | co-pro → host | up to ~250 bytes inline, to `Socket_Send` |
| Status | host → co-pro | bytes available, connection state, errors |
| Close | co-pro → host | tear down |

OSWORD number to be allocated from the user range and checked for conflicts
with the Sprow ROM (which uses &C0) and anything else fitted.

### 5.4 Escape hatch

If the ~250-byte inline ceiling ever binds, the ROM can initiate a genuine Tube
block transfer directly into co-processor memory, giving the full link rate.
Recorded as an upgrade path; a terminal is not expected to need it.

### 5.5 Development workflow

**Do not burn EPROMs.** The Master 128 has four sideways RAM banks (4–7).
Build a ROM image and `*SRLOAD` it into sideways RAM for an edit-test cycle of
seconds, while keeping full ROM semantics — service calls, `*` commands,
survives BREAK, proper workspace claiming. Commit to EPROM only once stable, if
ever.

### 5.5a CRITICAL: Socket_Recv blocks until the buffer is FULL

**Confirmed on hardware 2026-08-18.** This is the single most important
behavioural difference from standard Berkeley sockets and it is **not**
documented in `netprogapi.pdf`.

`Socket_Recv` does **not** return "up to N bytes" like BSD `recv()`. It normally
waits until it can satisfy **exactly** the byte count given at `YX+12`.

**QUALIFIED 2026-08-19: "exactly or not at all" is the common case, not the
rule.** A fully serviced call — `+2` zeroed, `+3` zero, no `&1E` — can still
return **fewer bytes than asked for**. Measured with `rxtest.bas` on both copro
15 and copro 2, identically:

```
odd: asked 128 +2=0 +3=0 +4=-109
odd: asked 128 +2=0 +3=0 +4=83
```

83 bytes for a 128-byte request. **Those bytes are real and must be consumed.**
Rejecting them because the count did not match loses exactly that much data, at
exactly the point the short read happens — which is what produced `sequence
gaps 2` at bytes 128 and 383, and 765 of 1000 bytes arriving.

Negative `+4` with `+3 = 0` also occurs and is an error, per §4.1's note that
failures return negative values.

**So the test on `+4` is a range, not an equality:**

| `+4` | Meaning |
|---|---|
| `1` … requested | that many bytes are in the buffer — **use them** |
| `0` | remote disconnected (§4.1) |
| negative | error |
| > requested | impossible; treat as no data |

`tput3.bas`'s `IF b%!4=sz%` is therefore too strict for a terminal: as a
benchmark it simply undercounts, but as a transport it discards live data.

**CONFIRMED on copro 2, 2026-08-19.** Same 1000-byte stream, with short reads
accepted: `short: asked 128 got 73`, `short reads 1`, and **`sequence gaps 0` —
nothing missing**. The stream stayed contiguous through the short read that had
previously torn a hole in it.

One loose end from that run: 967 of 1000 bytes, with no gap. The missing 33 are
at the **tail**, not the middle — the reader polled 1348 times getting `&1E` and
they never became available. So the module appears to hold a small trailing
fragment until more data arrives behind it. Harmless for a terminal, where the
next output pushes it through, but it would matter to anything expecting a
message to be complete when the sender has finished.

Evidence: with `YX+12 = 255` and 4 bytes in flight the call blocked
indefinitely. With `YX+12 = 4` and the same 4 bytes it returned immediately:

```
recv +2=0 +3=0 +4=4
```

Consequences, all of which cost a day to work out:

- **Never request more bytes than are certainly available.** A terminal cannot
  ask for a 256-byte bufferful and take what arrives.
- **`MSG_DONTWAIT` (8) works correctly.** Error `&1E` means "cannot satisfy the
  requested count right now" - a genuine would-block, not a rejection. Earlier
  notes here calling the flag broken were wrong.
- **Blocking mode (flags 0) hangs the machine** if the count is never
  satisfied, and with `*FX229,1` set there is no ESCAPE. Only BREAK recovers.
- **`+3=0` with `+4=0` means the remote disconnected**, per the doc. It appears
  the moment the far end closes.

**Practical pattern - ADAPTIVE SIZING, not one byte per call.**

An earlier version of this section recommended reading one byte at a time.
That was wrong, and it cost a day of measurements. Needing an exact count does
not mean only one byte is available - it means you must *ask for the right
amount*, and `MSG_DONTWAIT` tells you when you have asked for too much.

```
start sz = 1
loop:  recv(sz) with MSG_DONTWAIT
       success -> bank sz bytes, sz = sz * 2   (cap 128)
       &1E     -> sz = sz / 2                  (floor 1)
```

Idle polling costs one call; a burst ramps to 128 bytes per call within a few
iterations. **Measured on hardware: 128 bytes in a single call.**

**128 IS A HARD CEILING, AND EXCEEDING IT DESTROYS DATA.** Measured 2026-08-19
by raising `rmax%` to 512 and re-running `rxtest.bas` on copro 2:

```
largest read       128        <- never rose, though 256 and 512 were asked for
largest overshoot  256
sequence gaps      2          <- at bytes 256 and 521
bytes received     775 of 1000
```

The gaps sit exactly where the ramp first reached 256 and 512. So a request
above 128 does not simply return `&1E` and leave the buffer alone — **it
discards what was buffered**. The identical test with `rmax%=128` loses nothing.

This was worth testing because §5.5c's "largest successful read: 128" only ever
recorded that `tput3.bas` set `mx%=128` and nothing asked for more, and the
data does not travel in the control block — it goes to the buffer through the
pointer at `+8`, so the Tube's control-block limit is not the obvious
explanation. The limit is real regardless of the reason, and the penalty for
probing past it is silent data loss rather than a refusal.

**CHECK `+2` FIRST, ON EVERY CALL — an unclaimed OSWORD looks like success.**

`+2` holds the command byte the caller writes, and §4.1 says LANManager zeroes
it on every call. A surviving `+2` therefore means the call was never serviced —
and when that happens **no field is touched at all**: `+3` reads 0 because it
started 0, and `+4` reads back whatever the caller put there. `Socket_Creat`
writes `AF_INET` (2) to `+4`, so a phantom "socket number" of 2 appears, and
subsequent reads report a perfectly plausible `+4 = 2` byte count.

Observed exactly this on 2026-08-19: 3167 reads, all `+2 = 5, +3 = 0, +4 = 2`,
not one byte delivered — and the program still printed `connected to ...`.

**The cause was in the probe, not the machine** (see the note below), but the
signature is worth knowing because it is what an absent or unclaimed module
looks like from BASIC, and it is indistinguishable from data corruption unless
`+2` is checked. `nettest.bas` has always tested it; `tput3.bas` does not, and
`beebterm` tested it for create and connect but not for reads — so a module that
stopped answering mid-session would have rendered whatever was in `rx%`.

**`CALL &FFF1` takes the OSWORD number from `A%` and the block address from
`X%`/`Y%`.** Leave them unset and the call still happens — to a different
OSWORD, with a different block — and nothing reports an error. `rxtest.bas`
omitted them for its first three runs and produced, in order: apparent data
loss, an apparent missing byte count, and an apparent absence of the socket
module. None of it was real. Set the registers immediately before every
`CALL &FFF1`, never once at the top.

**A SUCCESSFUL-LOOKING CALL IS NOT A DELIVERY — check `+4` too.**

`+3 = 0` alone does not mean bytes arrived. `Socket_Recv` can leave `+4`
completely untouched, and `+4` is where the *caller* put the socket number, so
it reads back as a plausible small byte count. Measured 2026-08-19 with
`rxtest.bas`: socket 2, every call reporting `+3 = 0` and `+4 = 2`, at every
requested size, in both adaptive and one-byte-per-call mode. 500 calls, no `&1E`
at all, and 1000 bytes of *unwritten buffer* copied out and printed.

**The test is `+4 = the count you asked for`**, exactly as §5.5a's exact-count
rule implies. `tput3.bas` has always done this (`IF b%!4=sz%`); `beebterm`'s
`FNnet_recv` was written without it and printed garbage on hardware as a result.
Any new caller must copy the check, not just the control block layout.

**ALL BUT ANSWERED, 2026-08-20: it looks as though `&1E` DOES discard.**
`PTERMDBG` on copro 15 counted what the transport delivered and the server
logged what it sent, for the same session:

```
server sent    13987 bytes
Beeb received  13737 bytes        2046 reads, 35 short
lost             250 bytes
```

The stream contains no `&FF`, so the telnet IAC path is not eating them, and the
same bytes replayed offline through the engine match `pyte` cell for cell — so
the parser and the renderer are both innocent and the loss is in `FNnet_recv`.
The only path there that can lose data is this one: ask for `rsz%`, the module
has fewer, it answers `&1E`, and the client treats that as "nothing there".

The screen fault this produces is distinctive and was on a photograph before it
was on a measurement: an escape sequence that loses its `ESC[` prints its
parameters as text. `ESC[00m` becomes `00m`, `ESC[01;34m` becomes `01;34m`.

**OPEN, 2026-08-19: does `&1E` discard the buffered data?**

Nothing here establishes what happens to bytes already in the module's buffer
when a read asks for more than is available. If they are dropped, adaptive
sizing loses data on **every overshoot** — and the ramp overshoots once per
burst by construction. Reported from hardware the same day: BEEBTERM drops
characters during `ll`, while the login prompt is clean, which is the pattern
this would produce.

**§5.5c's 3082 bytes/sec cannot rule it out.** That measurement counted the
bytes that arrived; it never checked that none were missing. A throughput
benchmark is blind to loss by construction.

**FIONREAD is unsupported** — `Socket_Ioctl` with `&4004667F` returns `&88` on
both cores, so there is no way to ask how many bytes are waiting. Probing by
trial and error is the only option, which is why the read size has to adapt.

`test/rxtest.bas` decides it: the host sends `0123456789` repeatedly, so every
byte is predictable from the one before and a gap is detectable rather than
inferred. It runs adaptive and one-byte-per-call against the same stream, and
also probes **FIONREAD** — if the module implements it, the terminal can ask how
many bytes are waiting and request exactly that, which would remove overshoot
entirely and is a better design than probing by trial and error.

### 5.5b Working two-way channel achieved

**2026-08-18.** `test/beeblink.bas` on the Master, `tools/beeblink.py` on the
Linux host. Commands sent from the host, evaluated on the Beeb, results
returned over TCP:

| Sent | Returned | Proves |
|---|---|---|
| `2+2` | `4` | numeric EVAL round trip |
| `PAGE` | `3584` (&0E00) | memory reads |
| `HIMEM` | `12288` (&3000) | " |
| `HIMEM-PAGE` | `8704` | expression evaluation |
| `$STR$(PAGE)` | `3584` | string EVAL path |
| (a BASIC error) | `ERR 247 line 470` | error handler reports over the wire |

Only ~8.5K free between PAGE and HIMEM, which constrains how large a BASIC
program can be on the host side.

The `*` / OSCLI branch was still failing at the time of writing due to a typing
error in the hand-entered line 470, not a protocol problem.

### 5.5b-bis The 128-byte cap is not real (measured 2026-08-21)

`FBWAY` pulled **1024 bytes in a single `Socket_Recv`**, and `FBDECAY`'s way 4
averaged 1001 bytes a call across every block it caught. There is no 64-byte
cap, no 128-byte cap and no Tube control-block cap. When the module holds a
large block it hands over all of it at once.

`FBCOST` also showed **`refused=0` on every row**. The module never refuses. A
read larger than it can satisfy answers `&1E` — its would-block — meaning *"not
that many bytes yet"*, not *"too big"*. `RESSIZE`'s apparent refusals at 128
were a peek-then-read racing its own stale count.

What is real is the arrival rate. Four strategies compared under interleaved
quarter-second slices, so drift could not favour any of them:

| strategy | calls | hits | bytes | bytes/call |
|---|---|---|---|---|
| **bare read of 64** | 2532 | 114 | **7112** | **2.81** |
| bare read of 32 | 2550 | 199 | 6252 | 2.45 |
| peek, then read the count | 2548 | 67 | 4020 | 1.58 |
| peek, then pull it all | 2442 | 4 | 4004 | 1.64 |

**A bare read wins by 1.8x.** A call costs ~3.6ms whatever it carries, so the
peek's extra call costs more than the certainty it buys. Bulk pulling works and
does not pay: waiting for big blocks means catching four of them where a plain
64-byte read catches a hundred and fourteen.

**So a sideways ROM cannot help.** The limit is not extraction — not the read
size, not the Tube round trip, not the 3.6ms call. It is how fast the module
makes bytes available, and 95% of calls find nothing there. Nothing on the BBC
side changes that.

**Delivery is bursty, not decaying.** Twenty one-second buckets on a fresh
connection alternate between a burst and nothing at all, roughly every other
second, and the twentieth bucket is as fast as the second. An earlier guess
that a flooding sender overflows the receive buffer and degrades the connection
is **not supported** — nothing degrades.

**Caveat on the absolute numbers.** These probes run at 600-700 bytes/sec while
`PTERM` against a real shell measures 2416. The `yes | head` feeder is a poor
stand-in for a pty, so the *ranking* above is sound — it was drift-controlled —
but the rates are not.

### 5.5b-ter Where the 3.28ms actually goes (measured 2026-08-21)

| | |
|---|---|
| Module's own OSWORD &C0, host-side, **6502 assembler** (`FBASM`) | **1.83 ms** |
| Co-processor total, Tube + module (`FBNULL`) | **3.28 ms** |
| **Tube overhead** | **1.45 ms — 44% of every call** |

All three measured as an *empty poll*, so no data is moving and this is pure
per-call cost.

**Getting here needed four wrong turns undone.** BBC BASIC's own overhead
differs wildly between the two sides and swamped every earlier comparison:

| | wrapper | call |
|---|---|---|
| Host, BASIC IV | **35.55 ms** | 9.90 ms |
| Co-processor, BASIC V | **0.01 ms** | 3.27 ms |

On the host BASIC costs nearly four times the call; on the co-processor it is
free. Totals from the two sides are therefore **not comparable**, and comparing
them produced two confident and opposite wrong answers before `FBASM` measured
the call directly from assembler.

**What a sideways ROM could win.** It runs host-side, so it pays 1.83ms a call
and not 3.28. Sixteen recvs to gather 1KB: 29ms plus one bulk crossing, against
16 x 3.28 = 52ms today. Counting the cost of actually moving 1KB across the
Tube, realistically **1.3-1.8x**. Real, but not transformative, and it needs a
6502 assembler ROM plus a handover protocol.

**The module is the floor.** 64 bytes per 1.83ms is 35 KB/sec even with a free
Tube, and `Socket_Recv` will not return more than ~64 bytes however much is
queued (5.5b-bis).

**The bigger gap is not the ROM.** The current path's ceiling is ~17 KB/sec
(305 calls/sec x 64 bytes) and `PTERM` achieves 2.4 KB/sec — **12%**. Closing
that is worth more than the ROM's 1.3x and costs no new hardware. Real traffic
is bimodal: idle almost always, then 2-4KB queued at once. The number nobody has
measured is the **drain rate during a burst**, as opposed to the average over a
session that is mostly idle.

### 5.5b-quater A socket EXISTING crashes copro 15 (measured 2026-08-21)

Sustained work on the co-processor with a Sprow socket open kills the machine
within minutes. Established by elimination, one variable at a time:

| test | what it does | result |
|---|---|---|
| `FBSIT` | counts. No TIME, no files, no network | **lives** 10 min |
| `FBSITT` | + reads `TIME` once a pass | **lives** 10 min |
| `FBSITF` | + appends a line to the share | **lives** 10 min |
| `FBSITN` | + `PROCnap`'s `REPEAT UNTIL TIME<>t` | **dies** < 5 min |
| `FBIDLE3` | socket, polled flat out, safe nap, no files | **dies** |
| `FBIDLE1` | socket connected, **never polled** | **dies** |
| `FBIDLE4` | socket **created, never connected** | **dies** |
| `FBIDLEH` | `FBIDLE4` **on the host, no co-processor** | **lives** (2026-08-22) |

**Two independent causes.**

**1. `PROCnap` was a busy-wait on `TIME`.** On a co-processor `TIME` is read from
the host, so `t=TIME: REPEAT UNTIL TIME<>t` fires thousands of Tube transactions
per tick. `FBSITN` is that loop and nothing else — dead inside five minutes,
while the identical loop counting ran ten. **Fixed**: `PROCnap` is now an empty
`FOR` loop, calibrated once at startup by timing 20,000 iterations (two `TIME`
reads, not a spin). Never busy-wait on `TIME` on a co-processor.

**2. A socket existing at all.** `FBIDLE4` creates one and never connects it, and
still dies. So it is not TCP, not polling, not the read strategy, not the
buffering and not the renderer — **nothing the terminal does with the data can
affect it**, and no amount of tuning at this end is a fix.

**What this cost.** The crash was attributed in turn to the assembled block move,
the scroll, the socket read strategy, the send path, the module's 64-byte
metering and LANManFS. Every one of them was investigated at length and every one
was innocent. The check that would have caught it in one run — *does the machine
survive doing nothing?* — was done last instead of first.

**ANSWERED 2026-08-22: the host survives.** `FBIDLEH` — `mode%=4`, a socket
created and never connected, `CALL &FFF1` — ran on the host with no
co-processor and did not crash. So **the module has NOT always been like this**,
`BEEBTERM`'s long stable sessions were not luck, and the fault is on the
co-processor and Tube side. That is the half of the question §5.5b-quaterbis
predicts, since the block lengths are inert without a Tube to marshal them.

**Read that with §5.5b-quaterter, which is the confound.** `FBIDLEH` ran
`hbfile%=FALSE` and every co-processor run with a socket ran `hbfile%=TRUE`, so
this pair differs by share writes as well as by the Tube. `FBSITF` showed share
writes alone are harmless, but "socket **and** LANManFS writes" is not separated
by any run yet made — so "the fault is the co-processor and the Tube" is the
likely reading of this result, not an established one.

**Not tested**: whether a mounted LANManFS share contributes. `FBIDLE5` tried to
switch the filing system to ADFS first and locked up on the `OSCLI` itself,
before creating any socket — a faulty test, not a result.

**Superseded as the leading theory by §5.5b-quaterbis**, which found that every
call in this project sends a block longer than the one Sprow documents, and that
those bytes are the Tube transfer lengths — a fault that could only ever show on
a co-processor. "A socket exists" and "an over-long block was marshalled" are
not distinguished by any run in the table above: every socket in it was made by
the same over-long `Socket_Creat`.

### 5.5b-quaterbis WRONG: the over-long block is not the cause

**Proposed and falsified on hardware the same day, 2026-08-22.** Kept because
the block lengths still want correcting and because the elimination table below
must not be re-derived by someone who has the same idea again.

**Found in the documentation, 2026-08-22.** `netprogapi.pdf`
carries Sprow's own worked BASIC example, and it sets `+0` and `+1` per call:

| call | Sprow's `+0`/`+1` | what this project sends |
|---|---|---|
| `Socket_Creat` &00 | 16 / 8 | 28 / 28 |
| `Socket_Connect` &04 | 16 / 8 | 28 / 28 |
| `Socket_Recv` &05 | 20 / 8 | 20 / 8 in three places, 28 / 28 in the fourth |
| `Socket_Send` &08 | 20 / 8 | 28 / 28 |
| `Socket_Close` &10 | **8 / 4** | 28 / 28 |

`PTERM`'s `PROCzero` sets 28/28 once and every call inherits it. §4.1 recorded
the doc's warning — the lengths "tell the Tube software how big the block is",
and "example lengths are small (16/8 for `Socket_Bind`), not the 28/28 used in
early drafts here" — and the code was never brought into line.

**Why this is a candidate for 5.5b-quater.** For OSWORD with A >= &80 those two
bytes are the **Tube transfer lengths**; that is what the convention exists for.
On the host they do nothing, because the ROM is handed a pointer and nothing is
marshalled. Across the Tube they decide how many bytes are copied in each
direction. So an over-long block is a fault that **can only appear on a
co-processor** — which is the shape of the crash.

It also fits the elimination table better than "a socket exists" does.
`FBIDLE4` makes **one** over-long call and never touches the module again, then
dies minutes later; `FBSIT` never issues OSWORD &C0 at all and lives. The
variable those two differ by is an over-long marshalled block, not a socket.

**Not yet evidence.** No overrun has been shown to damage anything: the parasite
block is `DIM blk% 31`, so 28 bytes stay inside it at this end. Any harm is on
the host side of the marshalling, and that is inference, not measurement.

**FALSIFIED ON HARDWARE 2026-08-22.** `test/fbidle.bas` at `mode%=4` with
`doclen%=TRUE` **crashed copro 15 anyway**. At `mode%=4` the only OSWORD &C0
call in the whole run is `Socket_Creat`, and it went out at Sprow's own 16/8, so
the correction was applied to the one call that was made and changed nothing.
**The block lengths are not the cause.**

The lengths should still be corrected — they are a documented deviation and
`Socket_Close` at 28/28 against a documented 8/4 is nobody's idea of right — but
that is tidiness now, not a fix, and it must not be confused for one.

**What the theory got right and wrong.** It correctly predicted the host would
survive, but so does every co-processor-side explanation; that prediction never
discriminated between them and should not have been counted in its favour.
`doclen%` remains in the file as the switch that settled it.

### 5.5b-quaterter The confound is total: no socket has ever run without LANManFS

**2026-08-22, after the block-length theory died.** Laying every run out by what
it actually did, rather than by what it was built to test:

| test | machine | socket | share writes | result |
|---|---|---|---|---|
| `FBSIT` | copro | no | no | lives |
| `FBSITT` | copro | no | no | lives |
| `FBSITF` | copro | no | **yes** | lives |
| `FBSITN` | copro | no | no | dies — the `TIME` spin, §5.5b-quater |
| `FBIDLE1` | copro | connected | yes | dies |
| `FBIDLE3` | copro | polled | yes | dies |
| `FBIDLE4` | copro | created only | yes | dies |
| `FBIDLE4` + `doclen%` | copro | created only | yes | dies |
| `FBIDLEH` | **host** | created only | **no** | **lives** |

**Every co-processor run that had a socket also wrote to the share, and the one
run that did not write to the share was also the one with no co-processor.** The
two variables have never been separated. "It is the Tube" and "it is a socket
and LANManFS at the same time" both fit every row.

That second reading has a mechanism: LANManFS is a *network* filing system on
the same interface, so a mounted share plus a Sprow socket is two users of one
stack. It is the `FBIDLE5` theory, which was never actually tested — `FBIDLE5`
locked up on its own `OSCLI` before creating a socket, which is a faulty test,
not a result.

**Two runs separate them, and they are complementary.**

- **A — copro, socket, no share writes.** `share/Pi-TERM/FBIDLE`, `mode%=4`,
  `hbfile%=FALSE`, `doclen%=FALSE`, so it differs from the `FBIDLE4` that died
  by the share writes alone. Lives → LANManFS is implicated. Dies → the socket
  and the Tube are enough on their own and LANManFS is cleared.
- **B — host, socket, WITH share writes.** `share/Pi-TERM/FBIDLEH`, `mode%=4`,
  `hbfile%=TRUE`, differing from the host run that lived by the share writes
  alone. Dies → **the crash is not co-processor-specific at all** and
  §5.5b-quater's conclusion above is wrong; the host survived only because it
  was not writing.

Run **A first**: it is on the machine that has the problem, and it is the one
that can clear a suspect outright. B is only worth its ten minutes if A lives.

**The heartbeat still prints to the screen with `hbfile%=FALSE`** — `PROChb`
prints before it tests the flag — so a run with no share writes is still
watchable.

### 5.5b-quaterquater Test A: LANManFS is cleared, and 27 seconds is the new fact

**Hardware, 2026-08-22, build `0822c`.** Copro 15, `mode=4 doclen=0 hbfile=0` —
a socket created and never connected, no share writes, no polling.

```
FBIDLE copro build 0822c
mode=4 doclen=0 hbfile=0 mnowait=8
socket 3 created, NOT connected
start mode=4 doclen=0 b0822c hb=1 t=324317 ...
tick hb=2 t=324621  ...  tick hb=9 t=326721
```

**Dead at `hb=9`.** The ticks are 300cs apart to the centisecond the whole way,
so nothing degrades first — it runs perfectly and then stops.

**LANManFS is cleared.** The socket alone kills the co-processor with nothing
written to the share, so "a mounted share and a Sprow socket are two users of
one stack" is not the mechanism. §5.5b-quaterter's test B — the host *with*
share writes — is demoted with it: share writes are not necessary at this end,
and the host already survived without them.

**The new fact is the time.** `FBIDLE4` took nearly five minutes; this took
**24 seconds** — an order of magnitude faster for a run that did strictly *less*
work. Time-to-death is not a constant of the fault, and every "dies within
minutes" in §5.5b-quater should be read as "died, eventually" rather than as a
measurement.

**What is left running.** At `mode%=4` the program issues **one** OSWORD &C0 in
the whole run and never touches the module again. The loop is then only:

```
270   PROCnap          FOR i%=1 TO 20000:NEXT - no Tube traffic
275   IF TIME-last%>=hbcs%      TIME is a HOST read: a Tube transaction
```

So the parasite's sole ongoing activity is **a Tube transaction per pass**, and
the sole other thing running is the module's interrupt handler — which is what an
open socket activates. That is the whole remaining surface, and it suggests a
race between Tube traffic and the module's IRQ rather than anything the terminal
does.

It also re-reads §5.5b-quater's first cause. `FBSITN` (a `TIME` busy-wait, no
socket) died and `FBSITT` (`TIME` once a pass, no socket) lived, which was
written up as "never busy-wait on `TIME`". The rate mattered — but so, it now
seems, does whether a socket is open, and the two were never crossed.

**Test C, staged as build `0822d`, `mode%=5`.** Mode 4 with the `TIME` reads
removed altogether: `PROCquiet` calibrates naps-per-second against `TIME` for one
second, prints the figure, and then never reads `TIME` again — the heartbeat
goes out on R1, the VDU channel, and R2 falls silent.

- **lives** → the crash needs Tube traffic *and* an open socket. That is a large
  narrowing, and the rate becomes the next thing to vary.
- **dies** → an open socket kills the machine with the parasite quiet, so the
  parasite is not party to it and the fault is entirely host-side.

Time it by the wall clock; the count is in naps, deliberately.

### 5.5b-quaterquinquies Test C: it is the Tube traffic, not the socket

**Hardware, 2026-08-22, build `0822d`, `mode%=5`.** A socket created and never
connected, and the `TIME` reads removed from the loop altogether — `PROCquiet`
calibrates naps-per-second for one second and then never reads `TIME` again, so
R2 falls silent and only the three-second heartbeat goes out on R1.

**It passed 600 seconds.** Mode 4, the same run with `TIME` read every nap, was
dead between 24s and 27s. **The socket is not sufficient. Tube traffic from the
parasite is what kills it**, and an idle socket on its own is harmless for at
least twenty-five times as long as the machine used to survive.

That is a different fault from the one §5.5b-quater named, and the section's
title — "a socket EXISTING crashes copro 15" — is now known to be wrong.

**The four cells, and the one that has never been run:**

| | no socket | socket |
|---|---|---|
| no `TIME` reads | `FBSIT` — lives | `mode 5` — **lives 600s** |
| `TIME` at high rate | `FBSITN` — dies <5min | `mode 4` — dies 24s |

**`FBSITN` had no socket at all and still died.** So high-rate Tube traffic kills
this machine on its own, and whether the socket is party to it has never been
tested at a *matched* rate — every run with a socket also had a different loop.
The socket may be doing nothing more than making a pre-existing fault arrive
sooner.

**Test D, staged as build `0822f`, `mode%=6`.** `mksock%` now controls the socket
independently of the loop, so the rate and the socket are orthogonal.

- **`mksock%=TRUE tdiv%=1` — the positive control, and it goes FIRST.**
  `PROCquiet` is not mode 4's code, so if this does not die near 24s the
  instrument does not reproduce the fault and any survival at `mksock%=FALSE`
  would mean nothing. It is also the cheap run: half a minute against ten.

**The control did not die — and the reason is a rate point, 2026-08-22.**
Build `0822f` at `tdiv%=1` with a socket passed a minute where mode 4 died at
24s. Line 265 is why:

```basic
265   IF mode%=2 AND TIME-plast%>=pollcs% THEN plast%=TIME:PROCpoll
```

**BBC BASIC's `AND` does not short-circuit.** Both operands are evaluated, so
`TIME` is read there on *every* pass even at `mode%=4`, where `mode%=2` is
false — on top of the read at line 275. **Mode 4 was two Tube transactions per
pass; `0822f` was one.** Halving the rate took survival from 24s to over a
minute, which is the first point on the rate curve and came out of a run that
was only meant to validate the instrument.

`tper%` (reads per firing) and `napn%` (nap length) were added for this.
`tper%=2` matches mode 4 exactly and is the control to re-run, as build
`0822g`; `napn%` raises the rate above anything mode 4 reached.

**Control passed, 2026-08-22.** `0822g` at `tdiv%=1 tper%=2` with a socket
**died at 24s**, the same as mode 4. `PROCquiet` reproduces the fault, so the
instrument is trusted and a survival with the socket off now means something.

**The rate curve so far**, all on copro 15 with a socket open:

| build | Tube reads per pass | result |
|---|---|---|
| mode 5 | 0 | passed 600s |
| `0822f` | 1 | passed 60s+ |
| mode 4 / `0822g` | 2 | dead 24–27s |

Monotonic in rate, and the strongest pattern in the investigation.

**Test D proper, staged as `0822h`: `mksock%=FALSE`, everything else identical
to the control that just died.**

**RESULT 2026-08-22: `0822h` died at 87s.** No socket anywhere in the run.

### 5.5b-quatersexies THE FINDING: Tube traffic crashes copro 15

> **QUALIFIED 2026-08-23 by §5.5b-vicies.** Upstream issue #154 reports a
> thermal crash on the same Pi 3A+ with the same silent-freeze signature, and
> the runs below fit it as well as they fit a transaction budget. The
> rate-independence argument rests on a single fast run whose thermal state was
> never recorded, and **§5.5b-unvicies now has MODE 7 passing where MODE 0
> froze.** **Read what follows as unsettled.**

**A socket is not required and never was.** `0822h` made no socket at all, did
two `TIME` reads per nap, and died in 87 seconds. §5.5b-quater's title — "a
socket EXISTING crashes copro 15" — is wrong, and so is everything built on it.

**The socket is not innocent either.** At the identical rate it is 24s with a
socket and 87s without, so an open socket makes a pre-existing fault arrive
about 3.6 times sooner. It accelerates; it does not cause.

**The curve**, copro 15, `TIME` reads per nap:

| build | reads/pass | socket | result |
|---|---|---|---|
| mode 5 | 0 | yes | passed 600s |
| `0822f` | 1 | yes | passed 60s+ |
| mode 4 / `0822g` | 2 | yes | dead 24–27s |
| `0822h` | 2 | **no** | dead 87s |

**Why this explains the rest of the project.** `FBVDU` renders at 16,960
cells/sec and has never crashed, because an ARM co-processor writes the Pi's
framebuffer directly — that is not Tube traffic. `PTERM` polled a socket ~53
times a second and lasted about three minutes. `FBSITN`'s `TIME` busy-wait died
with no socket and no network, and was written up as a `TIME` quirk when it was
the first sighting of this.

**The open question, and it decides whether the design survives.** `tcall%`
selects what the gate calls:

| `tcall%` | call | channel |
|---|---|---|
| 0 | `TIME` | OSWORD 1, R2 |
| 1 | `INKEY(0)` | OSBYTE 129, R2 but **not** `TIME` |
| 2 | `VDU 0` | R1, and a documented no-op so nothing reaches the screen |

- **`INKEY(0)` dies too** → *any* R2 call does it, and `PTERM` **cannot be tuned
  out of it**, because polling a socket is an R2 call. Run this first.
- **`INKEY(0)` survives** → it is OSWORD 1 specifically and the terminal can
  simply never read `TIME`.
- **`VDU 0` survives at rate** → the fault is one channel rather than the Tube
  as a whole, and R1 stays usable either way.

**RESULT 2026-08-22: `0822j` died at 24s** — `INKEY(0)`, no socket. So **any R2
call does it, and `INKEY(0)` is worse than `TIME`**: 24s against 87s at the same
rate. `PTERM` cannot be tuned out of this, because polling a socket is an R2
call. The transport, not the tuning, is what would have to change.

### 5.5b-quatersepties The variable that has never been removed

**The LANMANAGER ROM has been active in every run ever made here** — with a
socket and without one, in `FBSIT`, `FBSITN`, every `FBIDLE`, every build today.
It hooks interrupts to service the interface, and a long host IRQ handler
landing inside a Tube transfer is a textbook cause of exactly this symptom. It
would also explain the 3.6× acceleration from an open socket: more socket state
is more work per interrupt.

Nothing in §5.5b-quatersexies distinguishes "the Tube is broken at this rate"
from "the module's interrupt handler breaks the Tube at this rate".

**`test/tubebare.bas` is the test, and it is deliberately typeable**, because
unplugging the ROM takes LANManFS with it and there is then no share to load
from:

```
*ROMS                 find LANMANAGER's slot
*UNPLUG <n>           disable it
CTRL-BREAK            ROMs are scanned at reset
*ARMBASIC             the share is gone - type the program in
RUN
```

Two `INKEY(0)` per nap and nothing else, matching `0822j` exactly. `0822j` died
at 24s with the ROM in.

- **passes ten minutes** → the module's interrupt handler is the cause, the Tube
  is only what exposes it, and this is a fixable position.
- **dies at 24s anyway** → the Tube itself is broken at this rate on this
  machine and the module is cleared. The next question is then whether it is
  specific to PiTubeDirect's ARM core, which a different co-processor answers.

**RESULT 2026-08-22, and it is not yet comparable: crashed at count 97475.**

97,475 naps against `0822j`'s 24 seconds, and **the two cannot be compared
without naps-per-second**, which no run has yet reported off the screen. The
first `TUBEBARE` printed a count and no clock — a fault in the instrument, not
in the machine, and the same mistake as the missing build stamp: it recorded the
quantity that was easy rather than the one that compares.

Fixed: the heartbeat now prints `TIME-t0%` alongside the count, so the run times
itself. That costs one R2 call per 25 naps against 50 `INKEY`s per 25 naps —
about 2% more traffic, worth paying for a number that compares.

**Wall clock: over a minute**, against `0822j`'s 24 seconds on the same
`INKEY(0)` loop at the same rate with the ROM in. So unplugging LANMANAGER
roughly doubled survival — **and it still died.**

### 5.5b-quaterocties The module accelerates; the Tube is what breaks

Every layer of network activity makes this worse and none of them causes it:

| variable | with | without |
|---|---|---|
| open socket (`TIME`) | 24s | 87s |
| LANMANAGER ROM (`INKEY`) | 24s | >60s |

**The fault is in the Tube path itself.** A machine with no socket, and with the
network ROM unplugged so LANManFS will not even mount, still dies inside a
couple of minutes doing nothing but `INKEY(0)` and an empty `FOR` loop. Nothing
about the terminal, the module or the network is required to reproduce it.

**The next fork: is it PiTubeDirect's ARM core, or the Tube path generally?**
`*FX 151,230,N` then CTRL-BREAK selects a core (§2.4). Running `TUBEBARE` on
copro 2 (65C102) answers it:

- **6502 core also dies** → the ARM core is cleared and the suspect is the
  shared Tube layer, the Master's Tube hardware, or the MOS.
- **6502 core survives** → it is PiTubeDirect's ARM implementation, which is a
  defined bug with an upstream to report it to.

**RESULT 2026-08-22: the 65C102 passed ten minutes.** Same loop, same program,
`copro=2`. The ARM froze in 24s with the ROM in and just over a minute with it
out; the 6502 does not freeze at all.

**But that is not yet a core difference, because it is confounded with speed.**
A 6502 may simply be too slow to reach the rate that breaks the machine, and
nap length cannot settle it — the same `FOR` limit is a completely different
transactions-per-second on each core.

### 5.5b-quaternonies TUBERATE: hold the rate, vary the core

`test/tuberate.bas` makes the **rate** the dial. `want%` is naps per second; it
times the default nap for one second, scales it to hit the target, and reports
what it achieved. Two `INKEY(0)` per nap, so Tube transactions are about twice
`want%`. Still typeable, because an unplugged LANMANAGER means no share.

Run it on the ARM at the rate the 65C102 survived:

- **ARM survives at the 6502's rate** → rate alone explains everything, no core
  is special, the ARM simply gets there faster — **and a safe rate exists**.
- **ARM dies at the 6502's rate** → the ARM core is genuinely at fault, and
  there is an upstream to report it to.

**If a safe rate exists, the question that decides the project is whether it is
above `PTERM`'s polling, which ran at about 53 reads a second** (§4.14).

### 5.5b-quaterdecies A rate threshold and a transaction budget fit equally

**2026-08-22: the 65C102's rate is 43.48 naps/sec**, so ~87 Tube transactions a
second. Ten minutes at that rate is **~52,000 transactions**. `TUBEBARE` froze
the ARM at 97,475 naps — **~195,000 transactions**.

**So the 6502 has not done a quarter of the work the ARM needed to fail.** It
did not survive the ARM's ordeal; it stopped early. §5.5b-quaternonies' "the
65C102 passed ten minutes" is true and does not mean what it appears to.

**Two readings, and every result so far fits both:**

| | consequence |
|---|---|
| **rate threshold** — below some rate it is safe indefinitely | there is a budget the terminal must live under, and the project continues if it clears ~53 polls/sec |
| **transaction budget** — a fixed number of transfers, then it stops | **there is no safe rate**, only a slower death, and no amount of tuning saves the design |

These have opposite consequences and nothing measured so far separates them,
because every run has been ended by patience rather than by a count.

**`tuberate.bas` now ends on a count.** `targ%` is transactions and 200,000
clears the ARM's failure figure; the run prints `PASSED` and stops when it gets
there. At 87 a second that is about **38 minutes** — long, but it is the first
run that can tell a threshold from a budget, and a shorter one provably cannot.

**Run it on the ARM at `want%=43`.** Line 330 reports the ARM's free-running
rate on the way past, which is a number this project has never measured and
which every rate result so far has been quoted without.

- **PASSED at 200,000** → a rate threshold exists, the ARM is safe at 87/sec,
  and the next job is bisecting `want%` to find the ceiling.
- **froze before 200,000** → a budget, not a threshold. The ARM cannot be tuned
  out of it and neither can the terminal.

### 5.5b-quindecies ANSWERED: it is a transaction budget, not a rate

**Hardware, 2026-08-22, the decisive run.** ARM, LANMANAGER unplugged, no
socket, `TUBERATE`:

```
193050 tx  cs=173842  nps=55.52      FROZE
```

Against `TUBEBARE` on the same core and the same conditions: 97,475 naps,
**194,950 transactions**, dead in about seventy seconds.

| run | rate | duration | transactions at failure |
|---|---|---|---|
| `TUBEBARE` | ~2,780 tx/sec | ~70s | 194,950 |
| `TUBERATE` | 111 tx/sec | 1,738s | **193,050** |

**The counts agree to within 1% at rates twenty-five times apart.** The machine
dies after about 195,000 Tube transactions however fast they are spent. Even
allowing for `TUBEBARE`'s duration being known only as "over a minute", the
durations differ by at least fourteen times while the counts do not differ at
all.

**So there is no safe rate.** Slowing down buys time in exact proportion and
nothing else. Every "dies in 24s / 87s / a minute" figure in the sections above
is a statement about how fast that run was spending a fixed budget, not about a
threshold it crossed.

**This is the signature of a leak** — something allocated per Tube transaction
and never released, until a pool is exhausted and the next call waits forever.
It is not timing, not a race, not interference: those would all scale with rate.

**And the host survives it.** CAPS LOCK still toggled its LED after the freeze,
so the host MOS is still servicing interrupts. What is wedged is the parasite or
the link, which puts the leak on the co-processor side — ARM Tube OS or
PiTubeDirect's ARM core — rather than in the Master.

**Why the socket and the ROM looked like causes.** They shrink the budget rather
than creating the fault: with LANMANAGER in, failure came at roughly 66,700
transactions instead of 195,000. Every network layer costs budget; none of them
is what runs out.

**A defect in the instrument, recorded.** `want%=43` produced 55.52 naps/sec, not
43. The calibration times a bare nap and the real loop is not bare, so the
scaling is out by about a quarter. It does not touch this result — the finding
is a count, and the rate only had to be *far* below the free-running one — but
the figure to quote is the measured 55.52, never the target.

### 5.5b-sexdecies The test that now matters: the 65C102 to 200,000

The 65C102 ran ten minutes at 43.48 nps, about **52,000 transactions** — a
quarter of the ARM's budget, so it proved nothing. Repeat it with `TUBERATE`
and `targ%=200000`: about 38 minutes at that rate.

- **65C102 PASSES 200,000** → the leak is in the ARM core specifically, and
  there is an upstream to report it to. A 6502 co-processor becomes a real
  option, at the cost of 64K and BASIC IV.
- **65C102 freezes near 195,000** → the leak is in the shared Tube layer or the
  Master's own MOS, and no co-processor choice escapes it.

**Rate is what compares between cores, not nap count.** A 6502 runs the `FOR` at
a fraction of the ARM's speed, so the same `napn%` is a quite different number of
transactions a second. `TUBEBARE`'s heartbeat now prints `nps%` for exactly this
reason: read it off the first line, adjust the `20000` at line 260 until both
cores are doing the same transactions a second, and only then compare.

**The failure mode, characterised 2026-08-22.** The `TUBEBARE` unplug run was
valid — `*ROMS` showed LANMANAGER unplugged — and it ended as a **freeze**: the
screen simply stopped, no `Error N at line M` from the program's own `ON ERROR`,
no reset, and only BREAK recovered the machine.

That rules out several things it was never separated from before. A BASIC error
would have printed. Memory corruption would have shown as wrong output or a
`No room`. A watchdog or a crash would have reset. **A silent stop with both
sides alive enough to be reset is what a Tube protocol lockup looks like** —
one end waiting on a byte the other will never send.

**Worth one keypress next time it freezes: does CAPS LOCK still toggle its
LED?** The LED is driven by the host MOS. If it still toggles, the host is
running and it is the parasite or the link that is stuck; if it is dead too,
the host went down with it. That is free, and it halves the search.

**And the possibility that should be named.** Marginal hardware fits this
evidence as well as any software explanation does: sustained high-rate transfers
failing while low-rate ones run indefinitely is a classic signature of a tired
Tube ULA, a poor connection to the PiTubeDirect board, or its power. If the
6502 core dies at a matched rate too, reseating the board and checking the Pi's
supply is cheaper than any further software test.

**Also staged, `0822k`, `tcall%=2`:** `VDU 0` is R1 and a documented no-op. If
R1 survives at rate the fault is one channel rather than the whole Tube. Cheaper
than the unplug test, and it needs no reconfiguration — but it characterises
rather than fixes.
- **`mksock%=FALSE tdiv%=1` — the real test.** Mode 4's Tube rate, no socket.
  Dies near 24s → the socket is irrelevant and the finding is not "a socket
  crashes copro 15" but **"Tube traffic does"**, which is a far larger problem
  and affects every co-processor program, not just the terminal. Lives 600s →
  the socket really is required and the rate ladder characterises it.

`tdiv%` is the rate ladder: `TIME` read every `tdiv%` naps and the answer thrown
away. A **negative** `tdiv%` is reads per second, resolved against the
calibration, because the rate that matters is not known at line 179 — `0` never,
`-1` once a second, `-10` ten a second, `1` every nap.

**A caveat about where this leads.** If it is the Tube transaction rate, that is
awkward rather than good news: `PTERM` must poll the socket, which is R2 traffic
by definition, and phase 5 was doing about 53 productive reads a second. A
rate-dependent fault would explain why `PTERM` ran well for roughly three minutes
and then stopped, and it would mean the terminal cannot simply be tuned out of it.


**RESULT, and it contradicts the earlier 65C102 run.** 2026-08-22, `free run 45
nps` (which identifies the core — the ARM free-runs near 1,390):

```
tx=14336   elapsed 171s   nps=41.99      FROZE
```

**14,336 transactions.** The same core ran ten minutes earlier at 43.48 nps —
about 52,000 transactions — without freezing, and this run made *fewer* prints
(every 256 naps against every 25), so it was the gentler test of the two.

**The likely difference is that LANMANAGER was plugged back in.** A power cycle
restores it, because the CMOS cell is dead and cannot hold an `*UNPLUG`. The ROM
cost the ARM a threefold budget reduction; a larger cost on the 6502 would
account for 14,336. **Until `*ROMS` is checked, this run is not comparable to
anything** and the 65C102 question is still open.

**RE-RUN, and it settles it: the 65C102 freezes at ~51,550 transactions.**
2026-08-22, `tx=51550`, ~618 seconds, 41.68 nps. That is the same point as the
earlier "ten-minute survival" of ~52,000 — **that run did not survive, it froze
just as it stopped being watched.** Two independent runs now agree on the
65C102's budget.

### 5.5b-septendecies BOTH CORES LEAK, and the budget is per core

| core | LANMANAGER | budget at failure |
|---|---|---|
| ARM native (15) | out | ~195,000 |
| ARM native (15) | in | ~66,700 |
| 65C102 (2) | out | **~51,550** (two runs: 51,550 and ~52,000) |
| 65C102 (2) | in | **~14,336** |

**The 65C102 is not immune — it is worse.** So the leak is **not** the ARM core,
and no co-processor choice escapes it. The `0822` outlier of 14,336 is explained:
LANMANAGER was back in after a power cycle, and the ROM costs the 6502 a 3.6×
budget reduction — the same order it costs the ARM (2.9×).

**But the budget differs by core, roughly fourfold, and that is informative.** A
leak in the Master's own MOS or in the Tube hardware would exhaust after the same
number of transactions whichever core issued them; the protocol and the byte
counts are identical. A budget that changes with the core points at
**PiTubeDirect's per-core Tube client** — parasite-side software, different
implementation per core, leaking at a different rate in each.

That is consistent with everything else: the count is fixed for a given core
across a 25× rate change, the host stays alive (CAPS LOCK toggles), and only the
parasite stops answering.

**Consequence for this project: copro 15 is the right choice after all** — it has
by far the largest budget of the two measured. And the mitigation is arithmetic
rather than engineering: at ~195,000 transactions, a terminal spending one
transaction per poll at `PTERM`'s 53/sec would last about an hour. `PTERM` died
at three minutes because the ROM and an open socket cut the budget to ~66,700 or
less, and because it spends several transactions per loop, not one.

**So the terminal is not fixable but it is budgetable**, and the two things worth
knowing next are how many transactions `PTERM` actually spends per second of
useful work, and whether a co-processor reset reclaims the budget.

### 5.5b-duodevicies A reset reclaims it — but the budget is not a constant

**Reset: answered, 2026-08-22.** After the co-processor restarted itself, the
same run reached **79,900 transactions** in ~959 s at 41.67 nps — *past* the
51,550 of the run before it. **A co-processor restart reclaims the full budget
and nothing carries across**, which is what parasite-side state predicts and
which gives a workaround, however ugly.

**But three 65C102 runs, LANMANAGER out, do not agree:**

| run | transactions |
|---|---|
| first | ~52,000 |
| second | 51,550 |
| third (post-restart) | **79,900** |

A 55% spread, and not explained by the program: `79,900 = 50 x 1,598` and
`51,550 = 50 x 1,031`, so both printed every 25 naps — same cadence, same rate
(41.67 against 41.68 nps), same ROM state. The 14,336 outlier printed every 256
naps (`14,336 = 512 x 28`) *and* had the ROM in, so it is separately explained.

**This weakens the "fixed budget" claim, and the weakening should be recorded
rather than the claim defended.** What survives is the part that was actually
demonstrated: **the count is rate-independent** — the ARM gave 194,950 at
~2,780/sec and 193,050 at 111/sec, a 25x rate change for the same count. What is
*not* established is that the count is exact. The ARM's two runs agreeing to 1%
now looks like a two-sample coincidence rather than a constant, and a third ARM
run is wanted before that pair is quoted again.

**So the shape of the fault is: something is consumed per transaction and not
returned, exhausting after tens of thousands of them, with the ceiling varying
run to run and by core.** A pool that fragments would behave like this; a simple
counter would not.

**A third instrument defect, and the same one each time.** The screen printed
`c%` in the field labelled `cs=`, so every line showed `tx` at exactly twice the
"centiseconds" and the machine appeared forty times faster than it was. The
elapsed time was only recoverable because the `nps` column was right. That is
now three runs that could not state their own conditions — the missing build
stamp, the missing clock, and this. `tuberate.bas` now prints a build stamp,
`want%`, `targ%`, a `*ROMS` reminder, and **`secs=` rather than `cs=`** so the
field cannot be misread.

### 5.5b-undevicies RE-BASELINE on the repaired machine: the leak survived

Every figure in §5.5b-quater through §5.5b-duodevicies was measured on a machine
booting with a dead CMOS cell, garbage configuration and undefined RTC control
registers. §5.5b-quinquies closed that on 2026-08-23 — new module, MOT pin tied
high, battery-backed, retaining across a power-down — and the Tube connectors
were cleaned and the board checked at the same time. So the baseline was re-run.

`TUBERATE`, ARM native (copro 15), LANMANAGER unplugged, `want%=43`,
`targ%=200000`.

| run | tx at freeze | nps | elapsed | notes |
|---|---|---|---|---|
| 2026-08-22 a | 194,950 | ~2,780 | — | pre-repair |
| 2026-08-22 b | 193,050 | 55.52 | 1,738s | pre-repair |
| 2026-08-23 #1 | 165,200 | 55.67 | 1,484s | post-repair, CAPS LOCK still alive |

**THE LEAK SURVIVED THE REPAIR.** New RTC, good CMOS, cleaned Tube edge
connector — and the parasite still freezes silently with the host running. That
removes the last hardware explanation and the last "sick machine" caveat. What
is left is PiTubeDirect's parasite-side Tube client, which is where §5.5b-
duodevicies already pointed when it found the budget differs per core and a
co-processor reset reclaims it.

**165,200 is not a material difference from 193–195k.** It is 15% low, and this
measurement is not that precise: the three 65C102 runs spread 52,000 / 51,550 /
79,900, which is 55%. The two pre-repair ARM runs agreeing to 1% was two points
being lucky, not a tight budget. §5.5b-duodevicies had already weakened the
"fixed budget" claim once; this weakens it again. **What survives is
rate-independence and the existence of a ceiling, not its exact value.**

**A first run was voided** because LANMANAGER was still plugged — the ROM cuts
the budget about 3× (§5.5b-quatersepties), so that run measured nothing. The
banner at line 334 now says so. It previously warned that a power cycle would
put the ROM back "because the CMOS cell is dead", which stopped being true on
2026-08-23 and would have actively misled.

**The screen mode is unrecorded** for every run in this table, and none of these
programs set one or print one. MODE 7 is the right choice — 1K of screen RAM
instead of 20K, so scrolling is a 1K move, and teletext characters are generated
in hardware — but the point is consistency across the comparison, and that was
not controlled before. One more instrument that cannot fully state its own
conditions, after the missing build stamp, the missing clock and the mislabelled
field.

### 5.5b-vicies REOPENED: upstream issue #154 is thermal, and our data does not exclude it

Web research on 2026-08-23 found
[hoglet67/PiTubeDirect#154](https://github.com/hoglet67/PiTubeDirect/issues/154),
*"Crash in Hognose (various versions, inc. rc1) when temperature hits above
around 55C but not Gecko"*, open and undiagnosed. It matches this project's
symptom on every axis that was ever recorded:

- **Pi 3A+** — the same model — in an external level shifter, in a box.
- Hangs silently; **the Master survives and CTRL-BREAK recovers it.**
- **20+ minutes to the first crash from cold**, then within ~5 minutes of a
  reload once the Pi is hot.
- Crashes above ~55-56C. **Lid off: 48.3C and no crash, stable over 3 hours.**
- Gecko card fine, Hognose card fails, swap back and the fault returns.

**THE RATE-INDEPENDENCE RESULT IS NOT AS STRONG AS §5.5b-quatersexies CLAIMS.**
Written out with wall-clock as well as count:

| run | tx | tx/sec | time to freeze |
|---|---|---|---|
| ARM 2026-08-22 a | 194,950 | ~2,780 | 70s |
| ARM 2026-08-22 b | 193,050 | 111 | 1,738s (29 min) |
| ARM 2026-08-23 #1 | 165,200 | 111 | 1,484s (24.7 min) |
| 65C102 | 51,550 | 83 | 621s (10.4 min) |
| 65C102 | 79,900 | 83 | 962s (16 min) |

The two slow ARM runs die at 25 and 29 minutes, sitting on #154's "20+ minutes
from cold". The fast run's 70 seconds matches its "within 5 minutes of a reload"
with the Pi already hot. The 65C102 dying *earlier in wall-clock* fits as well,
because JIT emulation works the Pi harder than native ARM passthrough and so
heats it faster. **Every point fits thermal at least as well as it fits a
budget.**

Worse, **the whole rate-independence finding rests on ONE fast run**, and its
thermal history was never recorded. Every other run is near 55 nps, where count
and time are proportional and cannot discriminate between the two models at all.
Two models, one discriminating datum, and no control on the variable that the
rival model turns on.

**This is the same defect as the missing build stamp, the missing clock, the
mislabelled field and the unrecorded screen mode — a run that cannot state its
own conditions — except that this time it reached a conclusion and the
conclusion was written into the spec as settled.**

**Discriminating tests, cheapest first:**

1. **Lid off, repeat the run.** No code, no typing, and it is the reported fix.
2. **Record the release.** Gecko -> Hognose -> Indigo; Indigo Beta1 (2024-04-12)
   supersedes both. #154 says Gecko is clean and Hognose is not.
3. **A fast run from a cold Pi** — `want%` about 1400, giving ~2,800 tx/sec.
   Budget predicts a freeze near 165-195k after about 70 seconds. Thermal
   predicts it runs past 3,000,000 transactions until the Pi warms up.

**Every future run must record: release, screen mode, lid on or off, and
whether the Pi was cold or already hot.**

Secondary, if heat is cleared: `tube_delay` in `cmdline.txt` is a real Tube
timing parameter (reported values 0-30; 25 working where 15 did not), and its
documented failure mode is a byte lost in transfer leaving the parasite waiting
indefinitely for the host — which is precisely this freeze.

### 5.5b-unvicies BREAKTHROUGH: MODE 7 passes where MODE 0 froze

**2026-08-23. Two consecutive `TUBERATE` runs passed 200,000 transactions on the
ARM (copro 15) with the host in MODE 7.** Setup: `*CONFIGURE MODE 7`, load
TUBERATE, `*UNPLUG 8`, CTRL-BREAK, `OLD`, `RUN`. Confirmed running on the
parasite and not the host by `PRINT ~PAGE,~HIMEM` (HIMEM = &4000000). No freeze,
no error, ran to the `PASSED` line.

Before this, **every** ARM run froze: 194,950 / 193,050 / 165,200.

**THE RETRODICTION.** The garbage CMOS the machine booted with throughout the
investigation read `Baud 1 / Delay 0 / Lang 0 / `**`Mode 0`**. So **every failing
run in this project booted into MODE 0, and not one was in MODE 7.** That is not
a new experiment; it is the existing evidence re-read once the variable nobody
was recording became interesting. It also explains why the fault seemed so
robustly reproducible: the mode was pinned by dead CMOS, so it never varied and
so never fell under suspicion. §5.5b-vicies had already flagged the unrecorded
screen mode as an instrument defect — it turned out to be the whole answer.

This matches [issue #70](https://github.com/hoglet67/PiTubeDirect/issues/70),
*"Switching language ROMS crash machine, when started in modes other than 7"* —
an independent report, closed, naming mode 7 as the safe one.

**The machine is on Indigo Beta1**, the current release, so §5.5b-vicies's
thermal candidate (#154: Hognose bad, Gecko good, Pi 3A+) does not apply here.
Heat is demoted, though not eliminated — nothing states #154 was fixed in Indigo.

**CONFIRMED 2026-08-23 BY DELIBERATE BREAK.** `*CONFIGURE MODE 0`, CTRL-BREAK,
`*FX 151,230,15`, CTRL-BREAK, `*ARMBASIC`, same program, everything else
identical: **froze at 143,900 transactions**, about 21.5 minutes. The prediction
recorded before the run was "between 150,000 and 200,000, about 25 minutes in" —
**wrong at the margin, 4% under the floor**, right on direction, magnitude and
timing.

| mode | transactions | outcome |
|---|---|---|
| 0 | 194,950 | froze |
| 0 | 193,050 | froze |
| 0 | 165,200 | froze |
| 0 (deliberate) | **143,900** | froze |
| **7** | >200,000 | **passed** |
| **7** | >200,000 | **passed** |

**THIRD MODE 7 PASS, 2026-08-23, and with LANMANAGER INSERTED.** That is
better than the clean replicate that was asked for. With the ROM in, the ARM
previously froze at ~66,700 (§5.5b-quatersepties made the ROM an aggravating
factor cutting the budget threefold); in MODE 7 it passed 200,000, three times
past its own previous failure point. The matrix is now perfectly separated by
mode:

| mode | LANMANAGER | result |
|---|---|---|
| 0 | out | froze x4 — 143,900 to 194,950 |
| 0 | **in** | froze ~66,700 |
| **7** | out | **passed x2** |
| **7** | **in** | **passed** |

Eight ARM runs, every pass in MODE 7 and every freeze in MODE 0. That
arrangement by chance is 1 in 56, **about 1.8%** — under the line rather than
merely suggestive.

**ANOTHER STANDING FINDING DISSOLVES: the ROM never shrank a budget.** There was
no budget to shrink. The ROM-in runs failed for the same reason all the others
did, and ~66,700 was simply another draw from the distribution MODE 0 generates.
That is the fourth conclusion overturned in one day, and all four fell the same
way — measured carefully, inside an uncontrolled constant nobody had recorded.

**OPEN THREAD: the MODE 0 figures decline monotonically** — 194,950, 193,050,
165,200, 143,900. Four descending in a row is about a 4% coincidence, so it may
be real drift across the day, with heat the obvious candidate (§5.5b-vicies).
It does not touch the mode conclusion but it is not explained.

**MECHANISM, hypothesised.** MODE 0 gives the host 20K of screen RAM and far
more VDU-driver work per character; MODE 7 is 1K with characters generated in
hardware by the SAA5050. Every `PRINT` from the parasite crosses R1, so the
likely trigger is **VDU traffic on R1 to a host too slow to drain it** — not the
mode as such, with the mode only setting the drain rate. **This retro-explains
why FBVDU has never crashed**: it writes the Pi framebuffer directly and puts no
VDU traffic on R1 at all. The immunity was recorded long before it had a reason.

**The test that separates mode from traffic:** same MODE 0, change line 390 to
`c% MOD 2500` so it prints 100x less. Passing means it is the R1 traffic and the
mode only sets how slowly the host drains it — which also predicts PiTerm is
safe in *any* mode. Still crashing means the mode alone does it regardless of
traffic, which is stranger and more interesting.

**IF CONFIRMED, THE FIX COSTS THE PROJECT NOTHING.** FBVDU renders directly into
the Pi framebuffer, so the host's screen mode is independent of the terminal
display. PiTerm can leave the host in MODE 7 permanently — 1K of screen RAM
doing nothing — while the terminal runs 80x64 on the Pi's own HDMI output. No
loss of function, and the §5.5b-undevicies calculation that gave PTERM about 26
minutes of session before a freeze would no longer apply.

### 5.5b-quinquies The CMOS/RTC chip is dead (2026-08-21)

`*STATUS` spooled off the real machine (`RESCMOS`):

```
Baud 1 / Data 0 / Delay 0 / FDrive 0 / File 0 / Lang 0 / Mode 0 / Print 0
Internal Tube ... No Tube            <- both
EMLink/EMAdvertise/EMAddr/EMMask/Gateway/DNS   all Unset
Mar,DB ?? 197B.F3:48:22
```

Against the emulator's plausible defaults (`Baud 6`, `Delay 30`, `Lang 12`,
`Mode 7`). **CMOS is holding nothing.**

**CORRECTED BY 5.5b-septies: only the CLOCK will not accept a write; the CMOS
RAM takes one and holds it across a power cut. AND BY 5.5b-octies: the clock
writes were made with reason codes that do not exist or do not mean what was
assumed, so the clock has never been properly asked.** As written below:
The chip **reads but will not accept a write**: `OSWORD &0F` types 8 and 0 both
leave the clock unchanged, tried from the co-processor and from the host. A flat
battery, and quite possibly leakage damage — a classic Master fault.

**This is not about the network needing the date.** Raw TCP timers are relative
tick counts and DHCP supplies the address (`EMAddr` is `Unset` and connections
work). It matters because **on a Master the CMOS and the real-time clock are one
chip**, so a flat battery leaves its *control* registers undefined as well as its
time. **[KILLED BY 5.5b-undecies: measured on the chip, PIE, AIE and UIE are all
clear and RS is 0. It is not this.]** A periodic-interrupt enable coming up set
would free-run an IRQ that nothing claims — which the host alone may absorb while host + Tube + module
interrupts does not, and that is exactly the asymmetry in 5.5b-quater.

**Fit a battery before any more crash work.** Until then the co-processor crash
cannot be attributed cleanly, because the machine is running on garbage
configuration and an unknown interrupt state every boot.

**CLOSED 2026-08-23. The clock is battery-backed and CMOS retains.** New module
in (see §5.5b-quinquies-bis for the pin 1 / MOT trap that had to be solved
first), configuration written, and the settings and the clock both survived a
long power-down — not the short cycle §5.5b-nonies warns about, which the 100µF
hold-up capacitor would have passed with no cell at all.

**This matters for the Tube budget work, not just for tidiness.** Every
measurement in §5.5b-quater through §5.5b-duodevicies was taken on a machine
booting with undefined RTC control registers and garbage CMOS. §5.5b-undecies
checked PIE/AIE/UIE and found them clear, so the free-running-interrupt theory
was already dead — but the *whole* Tube baseline was measured under conditions
that no longer apply, and **it should be re-measured now that they do.**

Cheap confirmation, no program needed: `*CONFIGURE MODE 7` then `*STATUS`. If
`Mode` still reads `0`, CMOS writes are dead and this is hardware.

### 5.5b-quinquies-bis A modern RTC module needs pin 1 tied HIGH on a Master

**2026-08-23, solved on hardware.** The replacement module — an `nwX287`-class
board (CR2032 + BQ3285/BQ4285, sold as a DS1287 / DS12887 / DS12B887 / BQ3287
replacement) — went in and **CMOS would not accept a write at all**, where the
original Hitachi part had accepted and held CMOS RAM writes (§5.5b-septies).

**Cause: the MOT pin, pin 1.** The original MC146818 / HD146818P contains
internal circuitry that *auto-detects* Motorola versus Intel bus timing. The
Dallas and Benchmarq replacements do not — pin 1 selects it, and Necroware's own
documentation is explicit: *"If pin 1 is pulled high, then the chip will work in
Motorola mode and if it is set to low, then the Intel mode is selected… if the
accordant connection on the mainboard is floating, the chip will go into the
default mode, which is Intel."*

**The Master is a Motorola-mode machine**, and §5.5b-nonies already proves it
without needing a datasheet: PB7 is the **address strobe**, and the addressable
latch supplies **RTC R/W** (line 1) and **RTC data strobe** (line 2). A separate
R/W line alongside a data strobe is the Motorola signal set; in Intel mode those
pins are ALE, /RD and /WR and there is no R/W line at all.

Acorn had no reason to tie pin 1 high, because the Hitachi part worked it out for
itself. So the socket leaves it floating, the module defaults to Intel, and the
machine drives it with Motorola signals — reads half-work, writes never land.

**Fix: force Motorola mode with the module's solder jumper.** On `nwX287` v2 that
is a blob; on the three-pad variants, pads 2-3 are Motorola and 1-2 Intel.
**Confirmed working on this machine 2026-08-23.**

**Two consequences for the tests already written.**

1. **`FBRTC`'s `VRT FIRST READ` no longer means what it did.** The MC146818 set
   VRT by sensing an *external* battery through a pin; this module carries its
   own cell. The `VRT = 0` that condemned the old battery is not a test that
   transfers to the new part.
2. **The Master's battery rail is still unpowered.** §5.5b-nonies notes the
   chip-select inverter's pull-up is fed from the battery-backed supply, as a
   guard against write corruption at power-down. A module with an internal cell
   does not restore that rail, so the guard stays absent.

### 5.5b-sexies Testing the battery backup after fitting a cell

**Written 2026-08-21, not yet run.** `test/fbbatt.bas`, `test/fbbatt2.bas`,
`tools/battcheck.py`, armed with `tools/battarm.sh`.

Battery backup is *retention across a power cut*, so no single program can test
it and nothing that survives a Ctrl-Break counts — the chip never lost power.
The test is in two halves either side of a real mains-off period of five minutes
or more, and it separates **three** failures that are usually spoken of as one:

| | question | fails when |
|---|---|---|
| writable | does the chip take a write with the machine powered? | 5.5b-quinquies: it did not, and no battery explains that |
| retained | did the CMOS RAM survive the cut? | flat or reversed cell, open holder, track or diode |
| running  | did the *oscillator* run on the cell, or did the clock freeze at the value written? | chip, not cell — RAM retention and a running clock are separate |

Both halves run on the **host**, not the co-processor: the RTC is host hardware
and `OSWORD &0F` across the Tube gives error 16 (`test/fbsetth.bas`). Phase 1
writes a known time with `OSWORD &0F` and two harmless CMOS markers with
`*CONFIGURE DELAY 45` / `*CONFIGURE REPEAT 17`, then reads both back
immediately; phase 2 reads only. Both spool `*STATUS` and an `OSWORD &0E` clock
string to `RESBAT1`/`RESBAT2` on the share, in `== TAG ==` blocks
`battcheck.py` parses.

The markers are DELAY and REPEAT because nothing else reads them, they take any
byte, they appear in `*STATUS` by name, and both currently read `0`, so 45 and
17 cannot be a default.

**The clock string is the instrument, not `*TIME`.** `OSWORD &0E` type 0 returns
`Day,DD Mon YYYY.HH:MM:SS` into a buffer, so the program can compare years
rather than the user reading a screen: a dead chip reads `197B` in those four
characters, which is not even decimal.

**A frozen clock is not the same result as a lost one.** If the markers survive
and the clock reads back exactly what was written, the cell is holding the RAM
and the oscillator is not running on it — that points at the chip. `battcheck.py`
prints the advance and says so.

Phase 1 alone answers the question that blocks everything else, and it is the
programmatic form of 5.5b-quinquies' one-liner (`*CONFIGURE MODE 7` then
`*STATUS`). If it says NOT WRITABLE there is no point powering anything off:
measure across the cell **in the holder** with the machine off, which separates
a dead cell from a break in the wiring faster than any program.

### 5.5b-septies CORRECTION: the CMOS RAM writes, the CLOCK does not

**ITSELF CORRECTED BY 5.5b-octies — the clock half of this section is built on
two malformed `OSWORD &0F` calls. The CMOS RAM half stands.**

**`RESBAT1` off the real machine, 2026-08-21 16:58.** Phase 1 of the
battery test (5.5b-sexies) splits what 5.5b-quinquies recorded as one fault:

```
clock before write   Mar,5A © 197B.F9:12:08
wrote                Fri,21 Aug 2026.16:40:15
clock after write    Mar,5A © 197B.F9:12:10      <- both types, unchanged
Delay/Repeat after   45 / 17   (wrote 45 / 17)   <- took immediately
```

**`*CONFIGURE` reaches the chip and sticks. `OSWORD &0F` does not.** The user
then power-cycled and reports every setting still there, so **the cell is
backing up the CMOS RAM** — which is what configuration needs and what
5.5b-quinquies said was gone.

**5.5b-quinquies' "the chip reads but will not accept a write" is wrong as
stated, and wrong in an instructive way**: every write it tried was a *clock*
write, and it generalised from the clock to the chip. The RAM was never tested.
Two register files behind one interface fail separately, and the cheap
discriminating test — `*CONFIGURE` something and read `*STATUS` — was named in
that very section as the confirmation and then not run.

What survives from it: the clock half is genuinely faulty. It reads, it **ticks**
(two seconds elapsed between the two reads above), and it rejects both
documented `OSWORD &0F` block types. A year of `197B` and an hour of `F9` are
not valid BCD, so the likeliest reading is the chip sitting in a control state
the MOS does not expect — Register B's mode bits — rather than dead registers.

**The crash hypothesis is not cleared by this.** A free-running periodic
interrupt lives in the same control register that the clock's behaviour points
at. `OSBYTE &A1` cannot see it: the manual restricts it to CMOS offsets 30-49,
and the *configuration* bytes are 0-29 (offset 5 is filing system/language,
12 the auto-repeat delay, 13 the rate). The RTC's own registers are reachable
only through the System VIA slow bus, which the Advanced Reference Manual
guards with "extreme care should be taken".

**Not a fault at all**: the machine appearing to lose its language after the
power cycle was a `*CONFIGURE NOBOOT` the user had made themselves. Offsets 12
and 13 are nowhere near offset 5, so `FBBATT`'s two markers could not have
touched it.

### 5.5b-octies THE CLOCK WAS NEVER ASKED PROPERLY — OSWORD &0F reason codes

**2026-08-21 evening, from the New Advanced User Guide §19.4.2.** `OSWORD &0F`
has **three** reason codes and **none of them is 0**:

| XY+0 | writes | block |
|---|---|---|
| 8 | **time only** | `hh:mm:ss` at +1 (colons at +3, +6) |
| 15 | **date only** | `ddd,nn mmm yyyy` at +1 (comma +4, spaces +7 and +11) |
| 24 | **time and date** | date at +1..+15, `.` at +16, time at +17..+24 |

`FBSETT`, `FBSETTH` and `FBBATT` all wrote **type 8 with the whole
24-character string**, so the MOS read `Fr` as the hours field, and then
**type 0, which is not a function at all**. Neither call ever asked the chip to
set anything. Every "the clock will not accept a write" in 5.5b-quinquies and
5.5b-septies rests on those two calls and is therefore **unproven** — a software
fault of ours, not a measurement.

The maddening part: **the string was right all along.** `Fri,21 Aug 2026.16:40:15`
is exactly the type 24 layout, and exactly the 24 characters `OSWORD &0E` hands
back. Only the reason code byte was wrong.

`FBBATT` now writes type 24, and if the year still does not take it writes 15
and 8 separately, which distinguishes date registers from time registers.
`battcheck.py` marks any record whose `CLOCK AFTER` tags lack a `24` as
predating the fix and refuses to draw a clock conclusion from it.

**This is the project's own rule again, in its most expensive form yet: verify
the call against the manual before concluding anything about the hardware.**
The same session had already corrected a "the chip will not accept a write"
generalisation (5.5b-septies) — and the corrected version was still built on
these two bad calls. A chip was about to be replaced on the strength of them.

**Consequence for the RTC replacement**: run the corrected `FBBATT` on the
**existing** chip first. If type 24 takes, the clock half is not faulty and the
only proven fault is a flat cell.

### 5.5b-nonies What the slow bus actually is, and what "extreme care" guards

The 146818 is **not on the 6502 bus**. Every access is hand-built out of System
VIA writes (Advanced Master Reference Manual, "Real-time clock/CMOS RAM"):

- **Port A (`&FE41`) is the slow data bus**, shared by the RTC, **the keyboard
  and the sound generator**. It carries the register *address* and then the
  *data*, and `DDRA` (`&FE43`) is flipped between output and input mid-access.
- **PB7 = address strobe, PB6 = chip select**, written directly.
- **R/W and data strobe come from the addressable latch**, written one bit at a
  time as `PB[0:3]` = data bit in b3, line number in b0-b2: line 0 sound write,
  1 RTC R/W, 2 RTC data strobe, 3 keyboard enable, 4-5 hardware scroll, 6-7 caps
  and shift lock LEDs.

The manual's own write sequence is thirteen VIA writes:

```
&02,&82 -> PB ; &FF -> DDRA ; addr -> PA ; &C2,&42,&41 -> PB
&FF -> DDRA ; &4A -> PB ; data -> PA ; &42,&02 -> PB ; &00 -> DDRA
```

**So "extreme care" means: this sequence is not atomic, and it shares its
resources with two other devices.** An interrupt landing in the middle that
scans the keyboard or writes to the sound chip re-uses port A and the same
latch, and the RTC — still selected, address already strobed in — can take
whatever byte is on the bus. That is a write into the configuration at an
address the interrupted code chose.

**Nothing in this project has ever done that.** Every access here has been
`*STATUS`, `*CONFIGURE`, `OSWORD &0E`/`&0F` or `OSBYTE &A1` — MOS calls that
obey the sequence. The transport is also demonstrably intact: the `*CONFIGURE`
markers in 5.5b-septies went out over exactly this path and came back correct.

**Two further hardware notes from the same manual, both bearing on this
machine:**

1. **The power-down write guard is powered from the battery.** "If power is
   removed during an access to this chip, the chip select will become invalid,
   with the possibility of write accesses being corrupted. This is avoided by
   inverting the chip select with a transistor whose collector resistor is
   connected to **the battery backed supply**." With a flat cell that pull-up
   has no supply — so a flat battery does not merely fail to retain, it removes
   the protection against corruption at every power-off. That fits CMOS full of
   garbage far better than CMOS merely empty.

2. **A 100µF capacitor sits across the clock chip supply** "to prevent loss of
   data in the event of accidental battery disconnection". At a few µA of
   standby draw that is tens of seconds to a couple of minutes of hold-up with
   **no battery at all** — so **a short power cycle is not a retention test**.
   Leave it off for an hour, or overnight, before believing the settings
   survived on the cell.

**Register B is out of reach of the MOS.** `OSBYTE &A1`/`&A2` address CMOS
*offsets* 0-49, which are RTC registers 14-63; the clock and control registers
0-13 are not addressable that way. So the free-running-periodic-interrupt
hypothesis behind the co-processor crash can only be tested by driving the slow
bus directly — the one job that actually justifies the sequence above.

### 5.5b-decies The slow bus works — both directions, validated in b-em

**2026-08-21, `test/fbrtc.bas` and `test/fbrtcw.bas`, run under b-em on the
host.** The answer to "can we set the control bits and the time directly" is
**yes**, and the code is written and proven before it goes near the machine.

The manual's thirteen writes decode cleanly against its own port B bit map (its
*comment column* is misaligned in the PDF; its bytes are not), and they are
textbook 146818 Motorola timing:

```
&02 idle            &82 AS high        DDRA=&FF   PA = register number
&C2 CE on           &42 AS low  <- address latched on the falling edge
&41 R/W low = write                    DDRA=&FF
&4A DS high         PA = data          &42 DS low <- data latched here
&02 CE off          DDRA=&00
```

A read is the same to the address latch, then `&49` (R/W high), **`DDRA=&00`
before DS goes active**, `&4A`, read port A, `&42`, `&02`.

**`SEI` around the whole sequence is not optional.** Port A and the addressable
latch are shared with the keyboard and the sound generator, so the 100Hz key
scan landing mid-access would strobe whatever it left on the bus into whichever
register was last latched. That is the entire content of "extreme care".

**The read is proved against ground truth**: registers 0-9 came back as the
host's actual wall clock in BCD — `sec 15 min 16 hour 22 dow 6 date 21 month 8
year 26` at 22:16 on Friday 21 August. Not a plausible-looking dump; the right
answer.

**The write is proved the same way**: after `FBRTCW`, registers 0-9 read back as
exactly the stamped values, and the MOS's own `OSWORD &0E` changed with them.
So b-em emulates RTC writes perfectly well over this path — the 2026-08-21
belief that it might not was about `OSWORD &0F`, which was being called wrongly
(5.5b-octies).

**AND THE CENTURY IS THE MOS'S, NOT THE CHIP'S.** With year register `&26` the
MOS prints **`Fri,21 Aug 1926`**. The chip holds two digits and this MOS
prefixes `19` unconditionally. Consequences:

- `197B` in 5.5b-quinquies was this same prefix applied to a garbage register,
  not a corrupt century.
- **Comparing the four-character year would report a successful write as a
  failure**, since 2026 goes in and 1926 comes back. `FBBATT`, `FBBATT2` and
  `battcheck.py` now compare **two** digits and normalise the century.
- Nothing on this machine will ever display 20xx from `OSWORD &0E`. That is
  cosmetic — nothing in the terminal work reads the year.

**What `FBRTCW` settles by construction.** It writes `B := &82` (SET, 24-hour,
BCD, **PIE, AIE and UIE all cleared**) and `A := &20` (DV=010 running, **RS=0000
so the periodic tick cannot even be raised**), then the time, then `B := &02`.
After that the chip *cannot* assert an interrupt. So it is a direct test of
5.5b-quater: if the co-processor still dies with a socket open, the RTC is
eliminated; if it stops dying, the crash has its cause. Registers 14-63 are
never written, so the configuration cannot be harmed.

`FBRTC` also reads **register C twice, a second apart**. C clears on read, so a
flag set again is being *regenerated* — a regenerated `IRQF` is the free-running
unclaimed interrupt itself, caught in the act. And **register D bit 7, VRT**,
says whether backup power has ever been lost: the battery question answered in
one bit, with no power cycle at all.

**Run `FBRTC` on the old chip before it comes out**, and again on the
replacement. The register dump is the only like-for-like comparison there will
ever be between them.

### 5.5b-undecies HARDWARE RESULT: the chip is healthy, and it is not the crash

**`RESRTC` off the real machine, 2026-08-21 22:22.** The first look ever taken
at this chip's own registers.

```
00: 59 EC 14 F3 F2 4B 4A DB      08: E1 7B 20 02 10 00 A3 00
A 20  UIP 0 DV 2 RS 0            C 10  IRQF 0 PF 0 AF 0 UF 1
B 02  SET 0 PIE 0 AIE 0 UIE 0    C again after 1s  10  IRQF 0 PF 0 UF 1
      SQWE 0 DM 0 24/12 1 DSE 0  D  &00 first read, &80 second
```

**THE FREE-RUNNING INTERRUPT HYPOTHESIS IS DEAD.** `B` has **PIE, AIE and UIE
all clear** and `A` has **RS = 0000**, so the periodic tick is disabled at
source and no enable is set. `IRQF` is 0 on both reads. The chip *cannot* assert
an interrupt and is not trying to. 5.5b-quinquies' "a flat battery leaves its
control registers undefined, and a free-running unclaimed IRQ fits the
asymmetry" was a good hypothesis, cleanly killed by measurement. **5.5b-quater's
crash must be looked for somewhere else, and the RTC is not worth another
hour.**

`UF` set on both reads is the update-ended flag doing its job — it is raised
once a second whenever the oscillator runs, regardless of `UIE`, and with
`UIE` 0 it never becomes an interrupt. Its regeneration is the clock ticking,
not a fault.

**THE CHIP IS NOT FAULTY.** `DM` 0 is BCD, `24/12` 1 is 24-hour, `DV` 010 is the
running oscillator — every mode bit is already what we would have set. And the
counters are correct: the dump caught `sec &59 min &14`, and the clock section a
moment later read `sec &01 min &15`. **A BCD rollover, 59 to 00 with the minute
incrementing.** Seconds and minutes keep proper time.

What is wrong is only the *contents* of the higher registers — hours `&F2`,
day `&4A`, date `&DB`, month `&E1`, year `&7B`, none of them valid BCD, plus
three alarm registers of garbage that `AIE` 0 makes harmless. That is exactly
what a chip that lost power looks like, and it is why the hours will never come
right on their own: the rollover logic compares against BCD 24, and `&F2` simply
counts up to `&FF` and wraps.

**So there is nothing here that a replacement chip fixes.** The garbage needs
writing over, which is `FBRTCW`, and the *cell* needs replacing. The chip
itself has been innocent throughout — as has, on the evidence of 5.5b-octies,
its refusal to accept a time it was never properly asked to take.

**VRT: READ REGISTER D FIRST, ONCE, OR NOT AT ALL.** The dump read `D = &00` and
the control section, later in the same run, read `D = &80`. Both are correct
readings of a bit that **is set to 1 by the act of reading register D**. Only
the first read since power-on carries information, and it said **VRT 0:
backup power has been lost.** The battery is flat — which is what everything
else has been saying since 5.5b-quinquies, now confirmed by the one bit designed
to say it.

`FBRTC` reads D as its very first access now and labels the later one as the
meaningless read. **The definitive battery test is therefore: power cycle, then
run `FBRTC` and look only at the `VRT FIRST READ` line.** One run, no five-minute
wait, no markers, no 100µF capacitor to reason about — and repeatable, because
each power loss re-arms it.

**The markers are gone as expected**: CMOS offset 12 reads 25 and offset 13
reads 9 — the Master defaults, not the 45 and 17 of 5.5b-septies. The boot with
`R` held restored defaults, exactly as `battcheck.py` warns. The configuration
is at least *sane* now rather than the all-zeros garbage of 5.5b-quinquies.

### 5.5b-duodecies The century is one byte of ROM, and three ways to have it

**`RESRTCW` off the real machine, 2026-08-21.** The slow-bus write works on the
hardware, first time:

```
== BEFORE CLOCK == Mar,DB  ?? 197B.F2:23:39
== AFTER REGS  == sec 16 min 15 hour 22 date 21 month 8 year 26
== AFTER CLOCK == Fri,21 Aug 1926.22:15:16
```

Registers 0-9 are valid BCD and the MOS agrees with every field **except the
century**. The chip holds two digits of year; **MOS 3.20 prefixes `19`
unconditionally**, from a single constant in ROM. `197B` in 5.5b-quinquies was
that same prefix on a garbage register, not a corrupt century.

**The constant is one byte, and it is verifiable without taking anyone's word
for it.** b-em ships both images, and they differ by exactly one byte:

```
$ cmp -l mos320.rom mos320p.rom
120962  31  40        <- 1-based, octal: offset 0x1D881, 0x19 -> 0x20
```

`0x1D881` is bank 7 of the 128K image — sideways `&9881` in **ROM 15, TERMINAL**,
where a slab of MOS code lives. That matches the address the Y2K community
documented, arrived at independently.

**Four MOS images, same chip state, same program** (`BEEB_OS=` in
`tools/beeb-test.sh` swaps the image, so nothing has to be burned to find out):

| image | year printed | |
|---|---|---|
| `mos320` | **1926** | stock, what this machine runs |
| `mos320p` | **2026** | stock plus that one byte |
| `mos350` | **1926** | **3.50 does NOT fix it** |
| `mos353` | **2026** | the updated MOS series does |

`0x1D881` holds `0x38` in 3.50/3.53 — different code layout, so **the patch
address does not transfer between MOS versions.** And `mos350` vs `mos350p`
differ by 43 bytes in banks 1 and 7, none of them this one: that pair is a
different patch entirely, not the century.

**Three ways to have the right year, in increasing order of effort:**

1. **Repair it in the caller.** `FBRTCW`'s `FNcent` — if the two-digit year is
   below 80, substitute `20`. Verified on stock 3.20: `1926` in, `2026` out.
   Costs nothing, needs no hardware, works on any Master, and is what BeebWiki
   recommends. **For this project that is the whole answer** — nothing in the
   terminal reads the year, so the century is cosmetic.
2. **Burn a patched 3.20.** One byte at `0x1D881`, `&19` to `&20`, into a 1Mbit
   EPROM for IC24. Correct until 2089 for `*TIME`, `TIME$` and everything else,
   with no software changes anywhere. It is a *constant*, not a pivot, so 19xx
   dates then become unrepresentable — which matters to nobody.
3. **Fit an updated MOS** (3.53 or the `D` series, Tom Seddon's `acorn_mos`).
   Y2K fix included, banner reads `MOS 3.20D`/`MOS 3.50D`, machine-detection
   OSBYTEs deliberately unchanged. More change than the problem needs unless
   its other fixes are wanted anyway.

**Plain MOS 3.50 buys nothing here** — worth knowing before ordering a
switchable 3.20/3.50 ROM for this reason.

### 5.5b-terdecies The module's own configuration, read at last

**`RESNET`/`RESSTRT` off the real machine, 2026-08-21 23:33.** 211 bytes, 19
CR-terminated lines, longest 39:

```
# Interface settings          # CIFS defaults
EMLink Auto                   Logon GUEST GUEST
EMAdvertise 10 Half Full 100 Half Full
                              # Hosts
# Network settings            (empty)
EMAddr Auto
EMMask Auto
Gateway 192.0.2.1
DNS 192.0.2.1
```

**`*EDIT` and `*TYPE` cannot reach it** — the pseudo file lives in NVRAM on the
module and LANManFS diverts **only OSFile** to it, so anything that opens it as
a stream is asking the *share* for a name it cannot parse. That is why the
module's own manual's `*EDIT Choices:Internet.Startup` answers `Bad name`. The
route is OSFile 5 for the length, OSFile 255 to load at a given address, OSFile 0
to replace (`test/fbnet.bas`, `test/fbnetw.bas`).

**Three things this settles.**

**1. The `Gateway`/`DNS` contradiction is resolved.** 5.5b-duodecies recorded
`*STATUS` reading `DNS Unset` while `*EMINFO` reported 192.0.2.1, and put it
down to DHCP. **It is not DHCP — the values are here**, in the module's own
file, which is where `*CONFIGURE DNS` evidently writes. Plain `*STATUS` is
reporting the *CMOS* copies, which are vestigial and have never been used. Only
`EMAddr`/`EMMask` come from DHCP (`Auto`). Worth confirming with the module's own
`*STATUS DNS`, which may well read the file and disagree with plain `*STATUS`.

So the earlier advice stands for the wrong reason: the six settings still do not
need restoring to CMOS, not because DHCP supplies them but because **the module
keeps its own copy in memory the flat battery never touched.**

**2. There is no auto-mount, and there never was.** The CIFS section holds
exactly one directive, `Logon GUEST GUEST` — credentials, no server, no share.
The manual's "defaults used to allow the shorthand versions of commands such as
*MOUNT" means *those* defaults and nothing more. **Nothing in the module can
mount without being asked**, which closes the question 5.5b-sexies' §8.3 left
open: automation needs a sideways ROM, or two typed commands. There is no third
way hiding in the configuration.

**3. `Hosts` is empty**, so `\\deskbox\beeb` rests entirely on the DNS at
192.0.2.1 knowing the name. `test/fbnetw.bas` appends `192.0.2.10
deskbox`, which is consulted *before* the DNS and takes the router out of the
path. The file ends `# Hosts`,CR,`#`,CR, so an appended line lands in the right
section without moving anything.

**The write is a whole-file replace** — OSFile 0 has no append — so `FBNETW`
loads what is there, adds one line, writes the lot back, and saves `NETBAK`
first, but **only while the file is still pristine**, so a second run cannot
overwrite the good copy with a modified one. `restore%=TRUE` puts `NETBAK` back.
The module checks only that each line is 80 bytes or fewer including the CR:
*"the text itself is not checked for valid syntax in any way"*, which cuts both
ways — a typo will be accepted and simply not work.

### 5.5c BREAKTHROUGH: pointers DO cross the Tube

**2026-08-18, `test/tubetest.bas` run on the Pi 65C102 co-processor.**

```
-- connected from 192.0.2.20
<< TUBETEST speaking from the co-processor
```

Independently confirmed at both ends: the co-processor created a socket,
connected outbound, and sent data that arrived at the Linux listener.

**`Socket_Connect` passes a pointer to a sockaddr at `YX+8`. It worked.** So
the host resolves pointers supplied by co-processor code - the assumption §5.1
was built on (that they would be meaningless) is **wrong**.

#### What this changes

`BEEBNET` was designed to exist because socket payload supposedly could not
reach the co-processor. That justification is gone:

- Terminal code on the co-processor can call OSWORD &C0 **directly**.
- No host-side ROM is needed for correctness.
- §5.1's "host-resident code is unavoidable" no longer holds.

#### What still argues for BEEBNET

Throughput, not correctness:

- `Socket_Recv` must be called one byte at a time (§5.5a).
- From the co-processor each call is an OSWORD **plus a Tube round trip**.
- A terminal moving even a few KB/s would pay thousands of Tube crossings
  per second.

So `BEEBNET`'s remaining purpose is **batching** - draining bytes host-side
into a ring buffer and handing the co-processor large blocks (up to the
documented 128-byte control-block limit) - rather than making the network
reachable at all. That is an optimisation, and should only be built once
measurement shows the direct path is too slow.

#### Receive direction also confirmed

Step 5 of `tubetest.bas` received data sent from Linux, byte by byte, on the
co-processor. **The full round trip works in both directions:**

```
co-processor -> Tube -> host -> Sprow module -> Ethernet -> Linux
Linux -> Ethernet -> Sprow module -> host -> Tube -> co-processor
```

Nothing in the architecture is now unproven at the transport level.

Note the BBC treats CR (13) as carriage-return only, with no line feed - two
messages terminated with bare CR overwrite each other on one screen line. Send
CRLF, or let the VT parser handle it as `beebterm.bas` already does.

#### MEASURED 2026-08-18: the direct path is too slow

`test/tput.bas` and `test/tput2.bas`, run on the Pi 65C102 co-processor:

| Measurement | Result |
|---|---|
| Empty polls, with a 28-iteration clear loop per call | 265 calls/sec |
| Empty polls, minimal per-call setup | 285 calls/sec |
| **Sustained data rate** | **72-83 bytes/sec** |

Stripping the BASIC overhead gained only 7.5%, so **interpreted BASIC is not
the bottleneck** and rewriting the inner loop in assembler would not materially
help.

**But it is NOT raw Tube bandwidth either.** The Tube ULA has no published
bytes/sec rating because fast block transfers are synchronous - the host simply
runs a fetch-store loop, so the rate is set by 6502 execution. At 2MHz and
~8-12 cycles per byte that is on the order of **150-250 KB/s**, roughly 3000x
what we measured.

What dominates is **fixed cost per OSWORD call**: a ~28-byte control block
across the Tube, an OSWORD dispatch, a full LANManager transaction with the
Sprow module, and a response written back into co-processor memory - all to
deliver ONE byte. Nothing measured so far distinguishes Tube protocol overhead
from the module transaction itself.

Note a data-returning call costs roughly 4x an empty one - returning a byte
requires the host to write into co-processor memory across the Tube, on top of
the call itself.

**Consequence: a 2000-byte screenful takes ~28 seconds.** The direct path
cannot carry a terminal, let alone a TUI that repaints continuously.

#### Measured with adaptive sizing, 2026-08-18

On the **host** (Tube disabled), `test/tput3.bas`:

| | |
|---|---|
| Sustained rate | **1370 bytes/sec** |
| Average successful read | **57 bytes** |
| Largest single read | **128 bytes** — *see below; this cap is not real* |
| 2000-byte screenful | **~1.5 seconds** |

Against 72 bytes/sec reading one byte at a time, that is a **19x** improvement.

Note a data-returning call costs far more than an empty poll: ~24 successful
reads/sec against 643 empty polls/sec, i.e. roughly 41ms per read of 57 bytes.
There is a real per-byte copying cost, not just per-call overhead - so read
size helps but does not scale linearly.

On the **co-processor**, same test:

```
894 bytes, 19 reads, 8099 calls total
burst took 29 cs
= 3082 bytes/sec
= 47 bytes per successful read
largest successful read: 128
2000 bytes would take 64 cs
```

**3082 bytes/sec - more than double the host**, despite the Tube, and against
72 bytes/sec reading one byte at a time. A **43x** improvement.

| Path | Rate | 2000-byte screenful |
|---|---|---|
| Co-pro, one byte per call | 72 b/s | 28 s |
| Host, adaptive | 1370 b/s | 1.5 s |
| **Co-pro, adaptive** | **3082 b/s** | **0.64 s** |

The co-processor beating the host is counter-intuitive given empty polls run
at 285/sec there against 643/sec on the host. The likely explanation is that
BASIC loop overhead around each call dominates on a real 2MHz 6502, while the
emulated co-processor runs it far faster - so once reads are large, the host's
CPU becomes the limit rather than the Tube.

**Caveat:** both figures may be bounded by how fast the test harness fed data
rather than by the Beeb. They are safe **lower bounds**, not ceilings.

**RESOLVED: `BEEBNET` is NOT needed.** Adaptive read sizing (§5.5a) achieves
128 bytes per call directly from the co-processor, so the Tube cost - which is
per *call*, not per byte - is divided by 128:

| | calls/sec | x 128 bytes |
|---|---|---|
| Host | 643 | ~82,000 bytes/sec |
| Co-processor | 285 | ~36,000 bytes/sec |

A 2000-byte screenful on the co-processor is ~16 calls, well under 0.1s -
against 28 seconds when reading one byte at a time.

**The architecture stands as originally designed:** terminal on the
co-processor, calling OSWORD &C0 directly, no host-side ROM. `src/beebnet.asm`
is cancelled.

**The decisive measurement, not yet done:** run `tput2.bas` on the **host**
with the Tube disabled.

| Host result | Meaning | Action |
|---|---|---|
| ~300 calls/sec, like the co-pro | cost is LANManager/module, not the Tube | **BEEBNET is pointless** - batching a slow source gains nothing. Rethink. |
| Much faster | cost is Tube protocol overhead | BEEBNET is worth building as a batching layer |

Do not write any 6502 until this is known.

### 5.5d Step 0c PASSED: the display is not the bottleneck

**2026-08-19, `test/vdutest.bas` on copro 15 (ARM Native), reached with
`*ARMBASIC`, output routed with `*PIVDU 2`, MODE 21.**

| Probe | Result |
|---|---|
| Text geometry | **80 x 64** — the driver comes up on the 8x8 font |
| VDU 31 cursor positioning | **OK** — all eight seeks read back exactly |
| VDU 17 colour | works, 0-63 all reachable as text colours |
| VDU 23 redefinition | **works** |
| Plain text | **60,769 chars/sec** |
| Text with a colour change per line | **63,200 chars/sec** |
| Full 80x64 repaint | **8 cs** |

**Colour changes are free.** The figure *with* a `VDU 17` on every line is
marginally *higher* than without, so the difference is inside the noise. A TUI
can recolour as often as it likes.

**The display is ~20x faster than the network.** 60,769 chars/sec against
§5.5c's 3082 bytes/sec: a full 80x64 screenful takes 0.08s to paint and 1.7s to
arrive. Every remaining performance question is about the socket, not the
screen - which is exactly what §3's split assumed.

**The frame Claude Code draws works.** VDU 23 synthesises the box-drawing glyphs
no BBC font has, and the six pieces assemble into a correct box around a line of
text. §7 Q7's glyph half is answered.

**Inconclusive at the time - the 256-colour grid.** (Resolved the same day by
`palette2.bas`; see §2.3. `vdutest.bas`'s colour page has since been rewritten
to use the tint properly, so a re-run will no longer show this.) The 64 text colours came out distinct,
but the `GCOL 0,n` swatch grid for 0-255 showed a large block of near-white
across the higher indices instead of 256 separate patches. That is saturation
above some index, a 64-colour-plus-TINT split, or the plot geometry running off
the mode's coordinate space - `test/palette.bas` is the dedicated probe and
decides which. **Do not assume xterm-256 indices map straight onto GCOL numbers
until it has been run.**

### 5.6 Step 0a - PASSED on real hardware

**2026-08-18, BBC Master at 192.0.2.20, via `test/beeblink.bas`:**

```
-- connected from 192.0.2.20:4097
<< BEEBLINK ready
```

The Master created a socket, connected outbound to this host, and sent data.
`Socket_Creat`, `Socket_Connect` and `Socket_Send` all work. `Socket_Recv`
works too - the host's Send-Q drained to zero, so the Beeb consumed everything
sent to it.

**This settles §4 empirically.** Confirmed on hardware, not merely inferred:

| Item | Value | Status |
|---|---|---|
| OSWORD number | 192 (&C0) | confirmed |
| Provided by | LANManager ROM (LANManFS not required) | confirmed |
| `sockaddr` | len 16 at +0, family 2 at +1, port +2, IPv4 +4 | confirmed |
| Port byte order | big-endian (network order) | confirmed |
| `PF_INET` / stream | 2 / 1 | confirmed |
| `YX+3` on entry | must be zero | confirmed |
| `YX+2` on exit | zeroed by LANManager | confirmed |

The lwIP inference in §4.2 held. Every *layout* guess made before reading
`netprogapi.pdf` was correct; only the *calling conventions* were wrong.

**Outstanding:** the Beeb's reply path (`PROCsend` in `beeblink.bas`) raises
error 26 on hardware. Receiving and executing works; sending back does not.
Under diagnosis - suspected typo in the hand-typed lines 520-580, or `t%` not
allocated by the `DIM` at line 80.

#### Superseded: the earlier FALSE NEGATIVE

**The 2026-08-18 "nothing claimed OSWORD &C0" result was caused by a bug in the
probe, not by the hardware.** `netprogapi.pdf` (§4.1) shows two errors:

1. The probe set `YX+3 = &FF` as a sentinel. **The doc requires `YX+3` to be
   ZERO on entry.**
2. The probe watched `YX+3` for a change. **The documented presence indicator is
   `YX+2`**, which LANManager zeroes during the call.

`test/netpresent.bas` implements the documented test correctly. The original
finding below is retained for the record but should be treated as void until
retested.

#### Original (void) finding

**Run on real hardware 2026-08-18 via `test/beeblink.bas`. Result:**

```
nothing claimed OSWORD &C0
```

The control block came back untouched with the &FF sentinel intact, so no ROM
claimed the call. `Socket_Creat` was never reached.

What this does *not* mean: the module is fine. It holds 192.0.2.20, answers
ping, and its Acorn MAC (00:00:A4:01:3F:EB) is in the host's ARP table.
**The module's own flash firmware runs DHCP/ARP/ICMP autonomously**, with no
BBC-side ROM involved - so a working network presence proves nothing about the
host API.

Two candidate causes:

1. **The LANMANAGER ROM is unplugged or absent.** The manual's install
   procedure says to run `*ROMS`, find the ROM named `LANMANAGER`, and if it is
   marked unplugged enable it with `*INSERT <rom>`. This is the leading
   hypothesis.
2. **The socket API uses a different OSWORD number.** &C0 comes from the
   mdfs.net "BBC IP networking" page; Sprow's own site only says "a simple
   OSWord parameter block" without naming the number. If LANMANAGER is present
   and enabled but &C0 is still unclaimed, the number is wrong and must be
   found by probing.

Diagnostics to run: `*ROMS`, `*HELP LANMANAGER`, `*EMINFO`.

Until this is resolved, §4.1's lwIP inference remains untested - the failure
happened before any socket call, so it says nothing either way about the
sockaddr layout or the constants.

### 5.7 Still untested

That the OSWORD &C0 control block transfers across the Tube per the A > &7F
convention is **inferred from the block layout, not verified.** The whole
host/co-pro split rests on it. Test before building anything on top — see §8
Step 0.

---

### 5.5e THE STUTTER WAS OUR OWN PROFILER, writing to the share every 3s

**2026-08-23.** Symptom, reported by ear: sitting at the shell prompt with
nothing typed, the Beeb's speaker hiss — the ordinary electrical noise of a
running machine — dropped out at a regular beat of roughly three seconds and
came back. Under `ll` the scroll paused at the same beat. The program was not
slow; it was **stopped**.

`prof$="RESPROF":profcs%=300` — the crash-survival profiler, firing every 300
centiseconds from the main loop at line 10150. `PROCprof` does an `OPENUP`, a
seek to `EXT#`, three writes and a close, **deliberately** closing each time so
a hard crash cannot lose the buffer. That is a complete SMB file transaction
over LANManFS **on the same Ethernet module the telnet socket is using**, three
times a minute, with the terminal halted for the whole round trip.

**Fixed:** `profcs%=0` now means off, and off is the default. Line 10150 became
`IF profcs%>0 THEN IF TIME-plast%>=profcs% THEN PROCprof` — a nested bare `IF`,
not `AND`, because BBC BASIC's `AND` does not short-circuit and `ELSE` binds to
the first `IF` on the line. Set `profcs%=300` only while diagnosing, and expect
the stutter to come back with it.

**IT MAY ALSO BE A CRASH CAUSE, AND THIS IS THE IMPORTANT PART.** "LANManFS as a
second user of the stack" was raised early and recorded as cleared by Test A —
**but Test A was `TUBERATE`, which opens no files at all.** For PTERM the theory
was never tested, because PTERM has been interleaving an SMB transaction with
its socket traffic every three seconds for the entire life of the program. Every
PTERM run in this project carried that confound.

**Method lesson, and it is the same one as the screen mode.** The instrument was
inside the measurement. A profiler built to survive crashes was itself doing
network I/O on the contended resource, three times a minute, in every run used
to characterise the fault. Like MODE 0 it was constant, so it never varied, so
it never looked like a variable.

### 5.5f THE SD CARD WAS NOT AT DEFAULTS EITHER: tube_delay=15 since 18 August

**2026-08-23.** The PiTubeDirect card was read on the Linux box for the first
time. Card label `IB1_M`, build `PiTubeDirect_20260412_1231`, git `58b5713` —
Indigo Beta1, the current release, confirming what the Beeb's banner said.

`cmdline.txt` held:

```
copro=2 copro1_speed=3 copro3_speed=4 tube_delay=15 elk_mode=0 vdu=1
```

and beside it `cmdline.txt.bak`, **identical but for `tube_delay=0`**. Both
timestamped **2026-08-18 21:56**.

**`tube_delay`'s default is 0** — from `get_tube_delay()` in
[`src/tube-client.c`](https://github.com/hoglet67/PiTubeDirect/blob/master/src/tube-client.c),
which reads the property, defaults to 0 and clamps at 40. It sets when the Pi
samples the Tube data bus relative to the host's strobe. **15 is the specific
value forum reports flag as troublesome**, with 25 reported working and 0 the
shipped default.

**THIS PROJECT BEGAN ON 2026-08-19. Every measurement in it was taken with a
non-default `tube_delay` that had been changed the evening before, and nothing
in the record mentions it.** Why it was changed is not recorded.

**RESTORED to `tube_delay=0`.** The `=15` version is kept on the card as
`cmdline.txt.20260823`, and all three files are backed up off-card. If booting
misbehaves at 0, try 25 before anything else — that is the value reported
working where 15 was not.

**THIRD UNCONTROLLED CONSTANT FOUND IN ONE DAY**, and all three are the same
mistake wearing different clothes:

| constant | set by | why it hid |
|---|---|---|
| host screen MODE 0 | dead CMOS battery | pinned, so it never varied |
| `profcs%=300` SMB write every 3s | our own crash profiler | the instrument was inside the measurement |
| `tube_delay=15` | an edit on 2026-08-18 | off-machine, in a file nobody read |

**The lesson is not "check the screen mode".** It is that a constant cannot be
seen by varying anything else, and every one of these was found by *reading the
configuration*, never by experiment. The experiments were all sound and all
measured the wrong thing.

**`copro=2` LEFT ALONE deliberately.** Setting `copro=15` would boot straight to
ARM native and retire the `*FX 151,230,15` + CTRL-BREAK ritual before every run,
but the residual PTERM crash is still open and this card has just had one
variable changed. Add it once that is settled.

`config.txt` is otherwise stock Indigo Beta1, with `overscan_top`/`bottom` added
at 24 because the TV was cutting off the first and last rows. That is display
geometry only and cannot affect Tube timing. The TV's own "Just Scan" setting is
the better fix where it exists, since it costs no picture.

### 5.5g ROOT CAUSE: the Tube drops one byte per 874,000, as a Poisson process

**2026-08-24, `TUBEDIFF` at td=20, 200 passes, 13.1 MB across the Tube.**

```
# summary td=20 passes=200 badpass=15 badbytes=458593 lost=14 dup=0 other=1
```

**14 of 15 failures are exactly ONE byte lost, with the block shifting up by
one. Never two. Never a repeat.** The fifteenth is a single byte reading `&55`
with no shift at all — the value an undriven bus returns on this hardware,
since `config.txt` pulls D6,D4,D2,D0 up and D7,D5,D3,D1 down.

Every claim was re-derived from the logged hex by `tools/resdiff.py` rather than
taken from the Beeb, whose arithmetic crossed the same Tube it was measuring.
`ndiff` matches what a single loss at that offset predicts, and the sum delta
equals minus the lost byte in 13 of 14. The exception, pass 17, is short by 257
against a lost byte of 117, so it lost a second byte later in the pass.

**THE STATISTICS SAY POISSON, AND THAT IS THE FINDING.**

| test | result |
|---|---|
| offsets uniform across the 64K block | KS **D=0.139, p=0.91** — uniform |
| clustering mod 2, 4, 8 ... 512 | none; every p between 0.20 and 0.80 |
| gaps between failing passes | mean 11.7, **sd 13.2** — exponential |
| adjacent-pass pairs | 3 against 1.1 expected, p=0.09 — not significant |

Independent, memoryless, uniformly distributed, single-byte losses. **That rules
out** protocol block boundaries, buffer wraps, state that accumulates, and
anything else that would make this an upstream logic bug. **It rules in** a
marginal physical event — something intermittently missing a threshold or a
setup time. "Always exactly one, never two adjacent" points at a **single missed
handshake** rather than a burst of noise.

**THE RATE, in the terms that matter:**

- one byte lost per **874,000** bytes
- one every **7 seconds** of active transfer at ~125 KB/sec
- **10.1% of `PTERMRUN`'s 88,301 bytes**

**One load in ten of the terminal arrives damaged** — tokenised BASIC with a
byte missing, so every line pointer after it is wrong. It can run for minutes
and then walk into the damage. **That is the residual PTERM crash, and no work
on the terminal could ever have fixed it.**

**`tube_delay` is not the lever.** 8 bad at 0, 8 at 40, 7 at 20 by checksum
across the parameter's entire legal range (§5.5f). A sampling-phase control that
changes nothing, against a fault whose signature is mis-sampling, is itself
evidence: the problem is below the parameter.

**Note the checksum undercounted by half** — 7 of the 15 real failures. A shift
loses one byte and gains whatever lands at the end, so a byte sum barely moves
while every position after the fault differs. Every result taken with `TUBECRC`
alone is therefore an underestimate, including the whole §5.5f sweep.

**Next is a scope, and the numbers are friendly to one.** Rare per byte, but one
event every seven seconds of transfer is easily within reach of infinite
persistence or a glitch trigger. Rails first — the Pi 3A+ runs `force_turbo=1`
at 1.2 GHz, and if it is fed from the Master's 5V rail then droop and switching
noise are prime suspects. Then Beeb ground against Pi ground, then the 2 MHz
phase clock and nTUBE, which is where a missed handshake would show. Use a
ground spring, not the flying lead.

**THERE IS NO RIBBON.** This is the **internal** PiTubeDirect kit: a Pi 3A+ on
a board that plugs **directly into the Master's motherboard Tube connectors**.
No cable, no length to shorten, nothing to reroute — earlier advice in this
document to reseat or reroute a ribbon was simply wrong about the hardware.
§2.3 says "internal kit ... plugged into the motherboard Tube connectors" and
should have been read.

**And every blind fix is now an A/B measurement**: separate supply for the Pi,
lid off, reseating the Tube connectors themselves, cleaning contacts — run
`TUBEDIFF` before and after and compare. That is the real change from 2026-08-23, when the only instrument
was "did it freeze".

### 5.5h The only change between the two runs was cleaning the POWER connectors

**2026-08-25.** Run 1 gave 15 failures in 200 passes; run 2 gave 7. The single
intervention between them: **contact cleaner sprayed on the motherboard power
connectors, sliding them on and off a few times.** Nothing else was touched.

**On its own the number proves nothing** — 15 against 7 is a two-sided binomial
p of 0.134, comfortably inside what two Poisson samples of this size do by
chance (§5.5g's tools; 15 carries +-3.9 and 7 carries +-2.6).

**But it is not on its own, and that is the point.** §5.5g ranked the 5V rail
first among scope targets *before* this was known, on the argument that a Pi 3A+
running `force_turbo=1` at 1.2 GHz off the Master's rail would produce exactly
this failure profile: random, memoryless, single-byte, and immune to every
software parameter. A change to the power path moving the count in the predicted
direction is worth more than the p-value alone suggests — but it is **post-hoc**,
noticed after the fact rather than predicted before it, so it raises the prior
and settles nothing.

**RUN 3 (2026-08-25): 8 failures, so the post-clean rate is reproducible.**

| | pre-clean | post-clean |
|---|---|---|
| failures / passes | 15 / 200 = 7.50% | 7 + 8 = 15 / 400 = **3.75%** |
| 1 byte lost per | 873,813 | **1,747,626** |
| `PTERMRUN` loads damaged | 10.1% | **5.1%** |

Rate ratio exactly **0.50**, two-sided p = **0.087** (one-sided 0.044). The two
post-clean runs agreeing closely says the instrument is reproducible, which
makes the 15 look genuinely different rather than a wild draw.

**IT CANNOT BE MADE CONCLUSIVE, AND THAT IS STRUCTURAL.** There is exactly one
pre-clean measurement and it can never be repeated, so its +-3.9 is permanent
and dominates the comparison. Projected: +200 passes reaches p~0.070, +400
p~0.050, +600 p~0.040. **Three hours of runtime to crawl from 0.087 to 0.040.**
A control arm that no longer exists cannot be strengthened by collecting more of
the other arm. Stop spending runs on this question.

**AND THE PRACTICAL NUMBER MATTERS MORE THAN THE p-VALUE. Even taking the
halving at face value, one load in twenty still arrives corrupt.** That is
diagnostic progress, not a fix: a terminal that silently loses a byte of its own
program every twentieth start is no more shippable than one that does it every
tenth.

**It cannot be A/B'd.** Cleaning is not reversible, so the pre-clean rate can
never be re-measured. Three routes forward instead:

1. **Pin down the new rate.** More runs at the current state, or `reps%` at 600
   in `test/tubediff.bas` (line 330). 600 passes would make a genuine halving
   land at p~0.004 instead of 0.134.
2. **Clean further and watch the count.** The Tube connectors themselves, and
   any other connector in the Pi's supply path. A monotone fall across
   successive cleanings is much harder to explain away than one step.
3. **Scope the rails, now with a specific hypothesis** rather than a survey:
   5V AC-coupled at the Pi end, then Beeb ground against Pi ground.

**And the most informative test remains the cheapest: power the Pi from a
separate supply and run `TUBEDIFF`.** If contact resistance in the Master's
power path is the cause, an independent supply bypasses it entirely. That is a
five-minute test with no instruments, and unlike cleaning it *is* reversible, so
it can be run both ways.

### 5.5i FIXED: the interface board had NO bulk capacitor, and that was the fault

**2026-08-26.** A 1000 µF low-ESR electrolytic plus a 100 nF ceramic across 5V
and GND at the interface board. `TUBEDIFF`, same 200 passes, same td=20:

| run | failures / 200 | rate |
|---|---|---|
| pre-clean | 15 | 1 byte per 873,813 |
| post-clean (contacts) | 7 | 1 per 1,872,457 |
| post-clean (contacts) | 8 | 1 per 1,638,400 |
| **with capacitor** | **0** | **none observed** |

**p = 5.5e-4** against the pooled post-clean rate (7.5 expected, none arrived),
**p = 3e-7** against pre-clean. Not a marginal improvement — the fault stopped.

**THE ISSUE 4 BOARD CARRIES NO BULK CAPACITANCE AT ALL.** The upstream reference
HAT fits 22 µF (`C3`) plus two 100 nF; ours fits nothing, while carrying a Pi
3A+ held at 1.2 GHz by `force_turbo=1` and fed through forty-year-old wiring and
a Tube connector. The rail could not hold up under the Pi's transients, and the
Tube dropped a byte per 874,000 as a result.

**Everything now fits, including what did not before:**

- **Poisson, memoryless, uniformly distributed** (§5.5g) — droop is not
  correlated with position in a transfer, so losses fall anywhere.
- **`tube_delay` made no difference across its whole legal range** (§5.5f) — a
  sampling-phase control cannot fix a rail that has sagged.
- **Always exactly one byte, never two adjacent** — a brief sag costs a single
  handshake, not a burst.
- **The rare `&55` read** — the undriven-bus value, a sample taken while the bus
  was not being held.
- **Cleaning the POWER connectors halved it** (§5.5h) — same rail, partial fix,
  and the mechanism was ranked first in §5.5g *before* that result was known.
- **Cleaning the Tube connector in the 2026-08-23 hardware session changed
  nothing measurable** — right suspect family, wrong connector.

**ZERO OBSERVED IS NOT ZERO RATE.** By the rule of three, 200 clean passes puts
the 95% upper bound at 1.5% of passes, which still permits **up to 2% of
`PTERMRUN` loads to be damaged — one in fifty.** That is not yet good enough to
declare the terminal sound.

| clean passes | 95% upper bound on damaged `PTERMRUN` loads |
|---|---|
| 200 | 2.02% |
| 400 | 1.01% |
| 600 | 0.67% |
| 1000 | 0.40% |

`reps%` is line 330 of `test/tubediff.bas`.

**WORTH REPORTING.** An interface board that mounts a Pi 3A+ with no local bulk
decoupling is a design deficiency, not a tuning matter, and the symptom it
produces — silent single-byte loss on the Tube — is invisible to every ordinary
test. It presents as random crashes and lock-ups minutes later, which is exactly
what this project spent days chasing through five wrong theories.

## 6. Rejected options (with reasons)

| Option | Reason rejected |
|---|---|
| RS423 serial transport | Superseded by Ethernet. Retained only as a possible debug fallback. |
| Econet | The Sprow module does not implement Econet. |
| Native BBC terminal ROM with direct-to-screen blitter | Obsolete once rendering moved to the Pi. Was needed only to beat the ~0.09s full-screen repaint / ~11fps ceiling of MODE 0 on a 2MHz 6502. |
| Server-side thin client (`pyte` screen model + delta protocol + rate cap) | Pure compensation for a slow renderer. Unnecessary with a framebuffer. |
| Colour flattening + Unicode transliteration on the server | Unnecessary with full colour and a real font. |
| Native SSH on the 6502 | Key exchange would take minutes. **Still true, and about the wrong processor** — the terminal runs on copro 15, where X25519 costs under a millisecond. Reopened as `docs/ssh.md`, which measures SSH as a 4-9x bandwidth *win* rather than a cost. |
| Pi performing the networking | Bare metal: no TCP stack; 3A+ has no Ethernet port; WiFi not usable bare metal. |
| Terminal on co-pro rendering to the *BBC* screen | Strictly worse than host-native: every character crosses the Tube *and* goes through the slow MOS VDU driver. |
| Improving/patching Acorn's TERM ROM | Wrong target — it is a serial terminal driven through OSWRCH. |

---

## 7. Open questions

1. **Socket buffer transfer across the Tube** (§5.6) — blocking; test first
   (Step 0b). Determines the size of `BEEBNET`, and note that `Socket_Connect`
   is affected as well as `Socket_Recv`.
1a. **OSWORD number for `BEEBNET`** — allocate from the user range, check for
   conflicts with the Sprow ROM (&C0) and anything else fitted.
2. ~~**Pi VDU driver capability.**~~ **RESOLVED 2026-08-19 (§5.5d).** VDU 31,
   VDU 17 and VDU 23 all work, at 60,769 chars/sec plain and 63,200 with a
   colour change per line - about 20x the network's 3082 bytes/sec. The display
   is not the bottleneck and never will be.
3. ~~**Extended mode number.**~~ **RESOLVED: MODE 21, 640×512, 256 colours.**
4. **Text geometry** — MODE 21 gives 80×64 at an 8×8 font, 80×32 at 8×16, or
   80×51 at 8×10. **The driver comes up on 80×64** (§5.5d), and it is legible
   on the monitor in use. So this is now a taste decision rather than a
   capability one: 80×64 is a very tall terminal, and 80×51 or 80×32 may suit
   Claude Code better. Still undecided.
5. ~~**Does a telnet client already exist** for the Sprow module?~~
   **MOOT 2026-08-28** — the machine has an SSH client now, written here, and
   there was no prior art for that either: no SSH client has existed for a BBC
   Micro before. The original question, for the record:
   **Does a telnet client already exist** for the Sprow module? Bundled software
   is LANManager, LANManFS, a web server example and an NTP client — no telnet
   seen, but the User Guide has not been read.
6. **Keyboard mapping** — how the co-pro reads BBC keys over the Tube, and how
   to produce the keys Claude Code needs: Esc (requires `OSBYTE 229,1` to
   disable the escape condition), Ctrl combinations, arrows, Shift-Tab, Ctrl-R.
7. ~~**Claude Code specifics.**~~ **RESOLVED 2026-08-19, and colour is now
   implemented and working on hardware (§9.3).** The font does not
   carry `╭ ─ ╮ │ ╰ ╯`, but VDU 23 redefinition works, so they are synthesised
   and the assembled frame renders (§5.5d). `TERM=xterm-256color` is honest to
   advertise (§2.3): the 16 ANSI colours can be set exactly with `VDU 19`, and
   the other 240 map by nearest colour into the 64 × 4 space. What remains is
   implementation — build the 256-byte table — not a question.
   **Better than that as of 2026-08-20 (§2.3):** the framebuffer path has 256
   real palette entries, so `FBVDU` sets all 256 to their true xterm values and
   the nearest-colour table is not needed at all. The 256-byte table is only
   required if rendering goes back through `GCOL`.
8. ~~**Which target machines will accept telnet**~~ **ANSWERED 2026-08-28, and
   the question dissolved rather than being answered.** Any machine running
   `sshd` is now reachable directly, so nothing has to accept telnet and no
   intermediate machine is needed. `tools/sshgate.sh` still exists for the
   telnet path and for reaching a machine the Beeb has no key for.
9. **Destination entry** — **half answered 2026-08-28.** `ask%=TRUE` prompts
   at startup for host, user and port, defaulting to the configured values,
   and a name that is not a dotted quad is put through the module's
   `Resolver_GetHostByName` (&40) rather than through `PROCsa`'s `VAL`, which
   would have turned `deskbox` into 0.0.0.0 silently. What remains: `host$`,
   `port%` and `sshu$` are configuration lines in `src/pterm.bas`; a saved list
   would want the **host key** stored beside each entry, because the core
   verifies the signature but deliberately does not judge whether the key is
   the one you meant — that is `known_hosts`, and it belongs to the caller
   (`docs/ssh.md`). Nothing does that yet: the fingerprint is checked by eye.

10. **The gateway has never been run from the Beeb.** `tools/sshgate.sh` was
   built on 2026-08-28 and tested only on loopback. It is largely superseded by
   the client speaking SSH directly, but it is the oldest untested thing in the
   tree.

11. **Where the remaining time goes.** The compressed A/B moved 3,140 bytes in
   1.62s — 1,938 bytes/sec, well under the module's 4,268 — but the five-second
   profile shows 4,008 B/s in one window and 1,032 in the next. The average is
   a **duty cycle, not a rate limit**, so there are gaps to fill rather than a
   wall to lift, and nobody has looked at what fills them.

---

## 8. Implementation plan

### Ordering note

Nearly every useful OSWORD &C0 call passes a **pointer** — `Socket_Connect`
takes a name pointer at +8, not just `Socket_Recv`. So if §5.6 confirms that
pointed-to memory does not cross the Tube, `BEEBNET` is needed before *any*
co-processor networking works, including the prototype. The display half can
proceed independently of this.

### Step 0 — De-risk

Three independent tests, no commitment beyond them:

0a. **Network path, host only.** Host BBC BASIC calling OSWORD &C0 directly,
    with host pointers. No Tube, no ROM. Proves the module connects, resolves
    and receives. Establishes a known-good baseline.

0b. **Tube behaviour.** The same calls issued from the co-processor. Determines
    whether the control block crosses (expected) and what happens to the
    pointed-to buffers (expected to fail). This decides §5.6.

0c. **Pi VDU capability.** Open questions 2 and 3 — VDU 31 / 17 / 18 / 23
    support and text throughput. (Mode number now known — MODE 21.)

### Step 1 — ~~`BEEBNET` host ROM~~ **CANCELLED**

0b came back the unexpected way. **Pointers do cross the Tube** (§5.5c), so the
co-processor can call OSWORD &C0 directly and no host-side ROM is required for
correctness. `src/beebnet.asm` is not written and should not be.

What survives is a **performance** question, not a correctness one: adaptive
read sizing gets 128 bytes per call and 3082 bytes/sec (§5.5c), and §5.5d shows
the display running 20x faster than that, so the socket is the system's
bottleneck. Whether a host-side batching layer could raise it is decided by one
measurement that has still not been taken:

**Run `tput2.bas` on the host with the Tube disabled.**

| Host result | Meaning |
|---|---|
| ~300 calls/sec, like the co-pro | the cost is LANManager/module, not the Tube. Batching a slow source gains nothing and `BEEBNET` stays cancelled for good. |
| Much faster | the cost is Tube protocol overhead, and `BEEBNET` becomes worth reconsidering as an optimisation — but only after Step 2 shows the terminal actually needs it. |

Ten minutes on the hardware. Until it is done, **do not write any 6502.**

### Step 2 — Prototype in BBC BASIC V on the ARM co-processor — **DONE**

Write the terminal in BASIC V on the native ARM co-pro (copro 15, reached with
`*ARMBASIC`, output routed with `*PIVDU 2` — §2.3). It issues VDU calls to the
Pi framebuffer and calls OSWORD &C0 **directly**, validating display and network
paths **with no assembler and no host ROM**.

Scope: prompt for destination host/port, resolve, connect, telnet IAC
negotiation, VT102 subset, render, keyboard input.

### Step 3 — Evaluate

Judge whether BASIC V at 1.2 GHz is fast enough. If not, port the hot paths to
ARM assembler or C.

**Decided 2026-08-19: own the renderer, as a separate subproject — `FBVDU`,
specified in `docs/fbvdu.md`. Its Phase 0 completed 2026-08-20 and every answer
was favourable** — 256 programmable palette entries, the font harvested off the
driver in 1 cs, a full 80×64 repaint in 9 cs, and a clean `SAVE`/`LOAD` round
trip over LANManFS. §2.3a framed this as a trade rather than a
feasibility problem, and the trade came down on the side of owning it, for the
reason §2.3a gives: **it is not a performance argument.** Every rendering defect
found that day came from the VDU driver's semantics, and no amount of BASIC on
top of that driver produces pending wrap, a second screen buffer, or insert and
delete line.

The edit-test loop that §2.3a worried about losing is kept: `FBVDU` is written
in BASIC on copro 15 first, and the later target is a **purpose-built
co-processor core** rather than a rewrite in ARM assembler underneath the
existing client. A 6502 co-processor cannot be part of this — 64K of address
space, and the framebuffer is on the Pi behind the OSWRCH redirector.

`BEEBTERM` is untouched by that work and remains the fallback until `FBVDU`
replaces its display half.

### Step 4 — Claude Code integration

`TERM` selection, colour, glyph coverage, key mapping, window size reporting.
All of these are done except the glyphs `docs/full-screen-apps.md` lists as
unmapped (braille, shading, blocks and arrows), which are a font problem and
not a terminal one.

### Step 5 — SSH — **DONE 2026-08-28, and it was not in this plan**

Added in a day, from an assessment to a working terminal. `docs/ssh.md` is
authoritative; the short version:

| | |
|---|---|
| suite | curve25519-sha256, ssh-ed25519, chacha20-poly1305@openssh.com, `kex-strict-c-v00` |
| auth | public key, Ed25519. Passwords are **not implemented and will not be** |
| compression | `zlib@openssh.com`, **server-to-client only** — the client needs inflate and never deflate |
| entropy | the SoC hardware RNG, reachable from user mode on this core |
| size | 48,844 bytes of ARM at `&4100000` |
| handshake | 1.35 seconds from connect to a running shell |

**Three spikes came first, each answering a question that could have killed
it.** Spike 1: compiled C runs on copro 15, and `A%` arrives in `r0` under
both `CALL` and `USR` (`results/RESSPIKE_0827b`). Spike 3: the SoC RNG is
reachable from user mode, so the ephemeral key is not seeded from `RND`
(`results/RESRAND_0828b`). The middle one, calling OSWORD &C0 from C, was
never needed: the sans-IO design left the socket with BASIC.

**The design decision that made it small.** The C core does no I/O at all —
bytes in, bytes out. So PTERM's pump survived untouched, and the same source
compiles natively and runs against a real `sshd` on the deskbox box, where
every protocol bug was found with a debugger instead of on a Beeb through a
Tube with a monitor for output.

**Integrating it into PTERM cost five lines**, each a no-op when `ssh%=FALSE`:
`PROCbyte` (no IAC), `PROCnaws` (window-change), `PROCnet_open` (handshake),
`FNnet_recv` (ciphertext in, plaintext out) and `PROCnet_send`. The engine, VT
parser, drain loop, keyboard and flush are untouched, and the profiles prove
it: parse, flush and per-scroll costs are what they were under telnet.

---

## 9. Repository state

| Path | Status |
|---|---|
| `tools/beebasm` | Built from source (`stardot/beebasm`). Working. |
| `tools/b-em/` | **b-em emulator, built and working.** Bundles MOS 3.20, so no ROM sourcing needed. |
| `tools/run-beeb.sh` | Launches b-em as Master 128 (model 10) with VDFS mounted at `emu/vdfs`. |
| `tools/beeb-test.sh` | Runs a BASIC file on the emulator and captures output. |
| `test/nettest.bas` | Step 0a probe. **Verified running on the emulator.** |
| `test/README.md` | How to run Step 0a and interpret results. |
| `test/vdutest.bas` | **Step 0c probe.** VDU 31/17/23 support, text geometry, chars/sec. Not yet run. |
| `test/palette.bas` | 256-colour showcase — proves or disproves the xterm-256color claim in §2.3. Not yet run. |
| `test/mandel.bas` | CPU-bound co-processor showcase. Mode-21 aware (256 colours). Not yet run. |
| `test/fbtest.bas` | Framebuffer probe (§2.3a). **Confirmed on hardware 2026-08-19.** |
| `docs/fbvdu.md` | **FBVDU subproject** — a terminal VDU that owns the framebuffer. Authoritative for the display engine. |
| `docs/ssh.md` | **What adding SSH would take**, and why it is a bandwidth win. Authoritative for the transport's future. |
| `tools/sshgate.sh` | **The listener PTERM connects to.** Destination picker, not a login; onward ssh uses the gateway's key. Replaces §3.5's bare socat line. Verified on loopback 2026-08-27. |
| `tools/gate.sh` | Served over socat's pty by `sshgate.sh`. The menu, and the two `-o` flags that keep passwords off the wire. |
| `tools/gate.hosts` | The destination list. Edit this, not the scripts. |
| `tools/sshzlib.py` | Models SSH framing and `zlib@openssh.com` against `captures/`. The measurement `docs/ssh.md` turns on. |
| `src/spike1.c` | **SPIKE1** — the first compiled C in this project. Five staged probes, so a crash on the parasite localises itself. |
| `tools/armbuild.sh` | Builds `ARMBLOB`, checks the entry is at offset 0 and the code is ARM not Thumb, patches length/sum/id into `armspike.bas`, and copies to the share without CR translation. |
| `test/armspike.bas` | **Spike 1 driver.** Probes the memory, `*LOAD`s the blob, checksums it, then runs it under both `USR` and `CALL`, logging to `RESSPIKE`. **PASSED ON HARDWARE 2026-08-27** — see `results/RESSPIKE_0827b` and `docs/ssh.md`. |
| `results/RESSPIKE_0827b` | The passing run. `A%` arrives in `r0` under both `CALL` and `USR`, and `USR` returns `r0`. |
| `src/rng.c` | **Entropy spike.** Reads the SoC hardware RNG at `&3F104000`. Staged, because it touches a peripheral in user mode on a bare-metal core. |
| `test/rngspike.bas` | Spike 3 driver, logging to `RESRAND`. **PASSED ON HARDWARE 2026-08-28.** |
| `results/RESRAND_0828b` | The passing runs. The RNG is reachable **from user mode** — no `OS_EnterOS`, no SVC mode — and 32 bytes of seed costs microseconds. |
| `src/ssh/ssh.h`, `src/ssh/ssh.c` | **The SSH client core, sans-IO.** No socket, no clock, no allocation — BASIC keeps the transport. Version exchange, packet framing, algorithm negotiation. |
| `tools/sshtry.c` | Linux harness. Drives the core against a real `sshd` — the half that never goes on the Beeb. |
| `tools/sshbuild.sh` | Builds the core for **both** targets every run, `-Werror`, so libc creep fails the build immediately. |
| `src/ssh/sha256.c` | FIPS 180-4, the one primitive Monocypher lacks. Verified against NIST vectors on every build. |
| `vendor/monocypher/` | Monocypher 4.0.2 — X25519, Ed25519, ChaCha20, Poly1305. Public domain, cross-compiles freestanding. |
| `tools/sshtest.c` | The offline primitive checks. `sshbuild.sh` refuses to finish if they fail. |
| `vendor/miniz/` | miniz 3.0.2, inflate half only. `zlib@openssh.com` decompression. |
| `src/ssh/nolibc.c` | `memcpy`/`memset`/`memmove`/`memcmp` for the ARM link. **ARM only** — linking it natively makes gcc compile `memcpy` into a call to itself. |
| `src/ssh/beeb.c`, `beeb.ld` | The blob's face to BASIC: `A%` is an opcode, parameters at `&4108000`, session at `&4110000`. Seeds itself from the SoC RNG. |
| `tools/sshkey.sh` | Generates the Beeb's **own** ed25519 key and writes `SSHKEY` (64 raw bytes) to the share. |
| `test/sshbeeb.bas` | Drove the blob standalone before PTERM did: loads, checksums, connects, pumps. **PASSED on hardware 2026-08-28**, and carried the compression A/B. |
| `src/pterm.bas` | **The terminal, and it speaks SSH.** `ssh%=TRUE` at line 481 via `PROCsshcfg`; five one-line hooks and a block at 18000+. `ssh%=FALSE` restores the telnet path unchanged. **Running on hardware 2026-08-28.** |
| `results/RESSSH_0828d_zlib_redraws` | The compressed leg of the A/B: 3,140 wire, 40,978 screen, 1.62s. |
| `results/RESSSH_0828e_plain_redraws` | The uncompressed leg: 41,780 wire, 40,982 screen, 19.59s. **13.3x fewer bytes, 12.1x faster.** |
| `results/RESPROF_0828_ssh`, `_ssh2` | PTERM's own profiler over SSH. Same shape as under telnet — ~22% pump, ~71% idle — which is the evidence that the transport changed and the terminal did not. |
| `tools/basrenum.py` | Renumbers a listing. **`--bands` added 2026-08-28**: a driver shares a file with the engine by line number, so it renumbers in bands (`0:10:3 1000:10000:10`) rather than as one sequence. **Used in anger 2026-08-28**: the engine filled its band to exactly 9990, and `--bands 1000:1000:2` reflowed 1,844 lines from step 5 to step 2, taking the spare from 0 to 2,652 at no cost in file size. |
| `tools/mirrorck.sh` | Says whether what the Beeb will load is older than what is in `src/`. **Added 2026-08-28**, after a correct fix was reported as "nothing changed" because the share still held the previous build — a stale share is indistinguishable from a fix that did not work. |
| `PiTerm-spec.pdf` | The one-pager, printed. **Regenerate with `tools/mkpdf.sh`** — it went two revisions stale because nothing rebuilt it. |
| `tools/mkpdf.sh`, `tools/piterm-print.html` | Renders the PDF from the Artifact's markup plus a print stylesheet. `--no-pdf-header-footer` is required; the older `--print-to-pdf-no-header` is accepted and ignored under `--headless=new`. |
| `tools/baslint.py` | **Two checks added 2026-08-28**: the single-line `DEF FN` form is no longer reported as having no exit, and a variable READ BEFORE ASSIGNMENT is now caught — BBC BASIC stops with "No such variable", which on a co-processor looks exactly like a hang. |
| `test/fbpal.bas` | FBVDU Phase 0: palette depth. **Run 2026-08-20, inconclusive — superseded by `fbpal2.bas`.** |
| `test/fbpal2.bas` | The discriminator FBPAL should have been: does the companion entry change too. **PASSED on hardware 2026-08-20 — 256 real palette entries.** |
| `test/fbfont.bas` | FBVDU Phase 0: harvest the driver's font out of the framebuffer. **PASSED on hardware 2026-08-20 — 101 glyphs in 1 cs, box pieces exact.** |
| `test/fbbench.bas` | FBVDU Phase 0: cell blit rate. **Run 2026-08-20 — full 80x64 repaint in 9 cs, 11 a second.** |
| `PIFONT` | The 8x8 font harvested off the Pi VDU driver, 2048 bytes, produced by `test/fbfont.bas`. **Not distributed** - the glyphs are the driver's, not ours. Only the offline `sim%` path needs it. |
| `test/fbsave.bas` | FBVDU Phase 0: SAVE/LOAD round trip over the share, byte-compared against memory. **PASSED on hardware 2026-08-20 over LANManFS.** |
| `src/fbvdu.bas` | **FBVDU Phase 1 COMPLETE, on hardware 2026-08-20.** Model, blitter, damage tracking, scroll, cursor, attributes. 80x64, 16,960 cells/sec, all six visual checks passed. |
| `tools/basstrip.py` | Strips REM lines for memory-bound targets. Halves the engine. |
| `tools/baslint.py` | Lints BBC BASIC for undefined PROCs, unbalanced FOR/NEXT, over-long lines and BASIC V keywords. |
| `test/fbblit.bas` | FBVDU blitter arithmetic against a DIMmed block. BASIC IV safe. **Passing under b-em 2026-08-20.** |
| `tools/fbres.py` | Reads the probes' `RESPAL`/`RESFONT`/`RESBENC` off the share and analyses them. |
| `emu/vdfs/` | Host directory mounted as a filing system by the emulator. |
| `src/stub.asm` | **SOCKSTUB - fake socket module. Working.** Claims OSWORD &C0 with canned responses for offline development. |
| `build/SOCKSTUB` | Assembled 16K ROM. Installed in the emulator as slot 4 (`rom04=sockstub`). |
| `test/stubtest.bas` | Short focused test of the stub. **Verified passing.** |
| `src/beebterm.bas` | **BEEBTERM - terminal client. Working against the stub.** 249 lines of BBC BASIC. |
| `src/beebnet.asm` | **Cancelled** (§5.5c, §8 Step 1). Not written, and should not be. |
| `src/term.asm` | **Obsolete.** Serial/RS423 ROM from the superseded design; incomplete and does not build. Delete or archive. |

### 9.0 The share is three folders, and it is regenerated, not edited

The Beeb sees `share/` over LANManFS and it is gitignored — every file in it is
a CR-terminated copy of something in `test/` or `src/`, so rebuild it rather
than editing it. As of 2026-08-22 it holds folders only, no loose files, and the
Beeb reaches each with a `*DIR` first:

| folder | what is in it |
|---|---|
| `Pi-TERM` | The co-processor terminal: the `FBVDU` engine, `PTERM`, the drivers, and the two tokenised `CHAIN` builds. |
| `CMOS` | The CMOS/RTC/battery investigation (§5.5b-quinquies through §5.5b-terdecies) and its `RES*` output. |
| `GAMES` | The boot menu and the discs behind it. Tracked in git, unlike the other two, because `ARCADE` has no source here. |

`tools/mirror.sh --dir NAME <files>` writes into a subfolder. The folder name
obeys the same 8-character rule the file names do, for the same reason: LANManFS
truncates a longer one silently and two folders become one folder.

```sh
tools/mirror.sh --dir Pi-TERM src/fbvdu.bas src/pterm.bas \
    test/fbvt.bas test/fbglass.bas test/fbrate.bas \
    test/fbmodel.bas test/fbparse.bas test/fbidle.bas test/fbidleh.bas
tools/fbbuild.sh src/pterm.bas > /tmp/PTERMRUN.bas
tools/fbbuild.sh test/fbvt.bas > /tmp/FBRUN.bas
tools/mirror.sh --dir Pi-TERM --tok /tmp/PTERMRUN.bas /tmp/FBRUN.bas

tools/mirror.sh --dir CMOS test/fbbatt.bas test/fbbatt2.bas test/fbboot.bas \
    test/fbnet.bas test/fbnetw.bas test/fbrtc.bas test/fbrtcw.bas

# TUBECRC is CHAINed, so it must go through --tok. Mirrored as text on
# 2026-08-23 and the machine answered "Bad program" - the same trap the
# PTERM/PTERMRUN pair exists to warn about.
tools/mirror.sh --dir Pi-TERM --tok test/tubecrc.bas

# TUBEDATA is BINARY and must not be CR-translated. Generate it, never
# mirror it; the byte sum baked into TUBECRC depends on it exactly.
python3 tools/mktubedata.py
```

**The Tube and SSH-spike files were cleared off the share on 2026-08-28**, both
investigations being finished and written up. Nothing was lost: every one comes
back from the lines above, and `TUBEDATA`, `ARMBLOB` and `RNGBLOB` are
generated rather than mirrored. What the share carries now is what the machine
actually loads - the `FBVDU`/`PTERM`/`FBVT` trio, the two tokenised `CHAIN`
builds, `SSHBLOB`, `SSHKEY`, `HOSTS`, `KNOWNHST` - plus the six FBVDU engine
tests and `SSHBEEB`, which `tools/sshbuild.sh` still names.

### The quiet build

`tools/sshterm.sh` writes `share/Pi-TERM/SSH`: the same program with every
instrument off. `CHAIN "SSH"` on the Beeb.

|  | `PTERMRUN` | `SSH` |
|---|---|---|
| glass check at exit, `RESGLAS` | on | off |
| profiler, `RESPROF` | every 50 cs | off |
| wire log, `RXL` | 64K buffer, saved | off |
| startup banner | on | off |
| `RESERR` on a fault | on | **on** |

The instruments stay on by default in the thing that gets developed — every
measurement this project relies on came out of them. What they cost is not
nothing: about 131K of buffers `DIM`med at startup, up to 88K written at exit,
and a `TIME` comparison in the innermost loop. A terminal someone just wants to
use should carry none of it.

**Confirmed on the hardware, 2026-08-28.** Two sessions minutes apart make the
difference visible without needing to take anyone's word for it:

| | 19:36:56 `PTERMRUN` | 19:38:20 `SSH` |
|---|---|---|
| logged in by | publickey, no password | publickey, no password |
| `RESGLAS`, `RESPROF`, `RXL` | written at 19:37:08 | **not touched** |
| `KNOWNHST` | — | a new host remembered |

The second session connected to a machine the Beeb had never seen, prompted,
and wrote `192.0.2.10 SHA256:ee9ZjC9B...` — which is what `ssh-keygen -lf`
says that host's key is. So the quiet build still does the work; it just stops
reporting on itself. The evidence that the instruments are off is a set of
timestamps that did **not** move.

`err$` stays on deliberately. `RESERR` is written only once the program has
already failed and costs nothing until then; turning it off trades a
diagnosable crash for a blank screen.

**One source, patched — not a second copy.** `src/pterm.bas` remains the only
version; `sshterm.sh` rewrites six assignments in a copy and fails if any does
not take, the same rule `sshbuild.sh` applies to its build stamps.

**And the result is checked in the file the machine will load**, by
`tools/quietck.py`, because that is the artefact that matters and it is not the
one that was edited. `TRUE` and `FALSE` are **tokens**, `&B9` and `&A3`, so
`gcheck%=FALSE` never appears as text in a tokenised build and a grep for it
finds nothing whether the patch worked or not — a check that passes while being
wrong, which is worse than no check. `quietck.py` compares the token bytes
instead, and was confirmed to fail on an unpatched build before being trusted
on a patched one.

`RES*` output is not kept there at all any more. It is written by a run,
archived into `results/` when it says something, and deleted; a share full of
old `RES*` files is how a stale one gets read as a fresh one.

The tokenised builds carry their driver's name, not the engine's, because
`--tok` and the text path both write `share/NAME` from different sources and
whichever ran last wins. `PTERMRUN` is `CHAIN`ed, never `*EXEC`ed; `FBVDU` and
`PTERM` are the `*EXEC` pair that builds the same program the slow way.

### 9.1 Emulator notes

b-em was chosen over MAME (rejected) and BeebEm/BeebJIT: best Master 128
accuracy on Linux, actively maintained, and it emulates **Tube co-processors**,
which matters for Step 0b.

Four things that cost time and are easy to hit again:

- **VDFS must be enabled** with `vdfsenable=true` in `~/.config/b-em/b-em.cfg`.
  `-vroot` only sets the root directory; it does not turn VDFS on. Symptom:
  `*CAT` reports `Disc fault 18`.
- **BBC text files need CR (&0D) line endings**, not LF. `*EXEC` on an
  LF-terminated file reads it as one unterminated line and silently does
  nothing.
- **Filenames must be 7 characters or fewer** or DFS reports `Bad name`.
- **b-em never flushes the `-printfile` buffer** and loses it on SIGTERM, so
  captured output under 4096 bytes disappears. `beeb-test.sh` pads past the
  buffer to force a flush.

b-em also finds its data under `XDG_DATA_HOME/b-em`, not its install prefix -
`run-beeb.sh` sets this. CMOS images are looked up in the *config* directory
(`~/.config/b-em/`), not the data directory.

### 9.2 SOCKSTUB - the development stub

`src/stub.asm` is a sideways ROM that claims OSWORD &C0 and returns canned
responses, so client code can be developed with no hardware present. It
implements `Socket_Creat` (returns socket 1), `Socket_Connect`, `Socket_Send`,
`Socket_Close`, `Socket_Ioctl`, `Resolver_GetHostByName`, and a scripted
`Socket_Recv` that delivers three chunks then reports no data. Unknown commands
return an error.

Verified working via `tools/beeb-test.sh test/stubtest.bas`:

```
Creat   r=0 ret=1
Connect r=0 ret=0
recv    r=0 n=16 [SOCKSTUB ready<D><A>]
recv    r=0 n=41 [*** FAKE module - responses are guesses<D><A>]
recv    r=0 n=7 [login: ]
recv    r=0 n=0 []
Close   r=0 ret=0
```

**SOCKSTUB now models the exact-count receive behaviour of §5.5a**: it
satisfies the requested byte count in full or returns `&1E`. Verified - it
delivers one byte per call when asked for one. Without this the emulator gave
false confidence about the single most surprising hardware behaviour.

**The stub's remaining conventions follow §4.1's documented API.**
Passing against SOCKSTUB proves the client is *self-consistent*; it does **not**
prove the client will work against the real module. Correct this ROM once Step
0a reports the truth, then re-run the client against it.

It also establishes the workspace-claiming pattern `BEEBNET` will need: service
call &01 takes a page and records it in `ROMTAB` (&0DF0 + slot).

### 9.3b Modelling the parser without the emulator

b-em has no 80x64 mode, so a 64-row capture cannot be replayed faithfully. What
*can* be done is to model the parser's rules — immediate wrap, swallowed LF,
cursor addressing — in a few lines of Python against a real capture, and count
where the cursor is forced past the last row. That is how the bottom-right
scroll was found: three scrolls in three seconds, each reported with the byte
offset and the sixty bytes before it, which named the cause outright.

A model is not the implementation and can only disprove, never prove. But it
costs seconds, needs no hardware, and answers "where exactly" rather than
"something is wrong" — which the screen alone could not.

### 9.3a Replaying a real session offline

The emulator has no socket module, so `BEEBTERM` cannot talk to a shell there —
but the parser and renderer do not care where the bytes came from.

```sh
tools/ptycap.py emu/vdfs/TOPCAP 32 79 4 top -d 1
```

captures what `top` actually sends at a **fixed pty size**, and `replay$` in
`beebterm` reads that file instead of the socket. `dump%` then walks the
finished screen with **OSBYTE 135** and prints every row bracketed with `|`, so
blank rows, stale text and wrapping are visible in a text capture rather than in
a photograph of a monitor.

Two things this must get right or it tests the wrong thing: the capture size has
to match the geometry the Beeb will use, since the whole question is where lines
wrap; and the screen must be read **completely before any of it is printed**,
because printing scrolls the thing being read.

**Use `mode%=128`, shadow MODE 0, under the emulator.** `BEEBTERM` has outgrown
every non-shadow 80-column mode: `TOP` now sits above MODE 0's `HIMEM` of
`&3000` and MODE 3's `&4000`, and BASIC reports that as `Bad MODE` at the `MODE`
line — which reads like an invalid mode number, not a memory problem. Shadow
MODE 0 keeps the screen out of main RAM and gives the same 80 columns. On the
co-processor the question does not arise.

**Result, 2026-08-19:** `top` replays correctly at 79 columns — columns aligned,
no double spacing, no stale rows, no runaway scrolling. The finished screen is
offset by one line only because `top`'s *exit* sequence deliberately scrolls its
display away, which a real terminal does too.

### 9.3 BEEBTERM - the terminal client

`src/beebterm.bas` calls OSWORD &C0 directly and **runs in either place** — on
the host, or on the ARM co-processor. There is no host-side ROM to move to:
§5.5c cancelled `BEEBNET`. Two configuration lines pick the environment:

| | ARM native (15) | 6502 co-pro (2 / 24) | Host / emulator |
|---|---|---|---|
| `mode%` | 21 | 21 | 3 |
| `vdu%` | 1 — `*PIVDU` | 2 — `CALL &300` | 0 — leave alone |

**The framebuffer call differs by core and there is no way to ask**, so it is
configuration rather than detection. `*PIVDU` exists **only** on native ARM;
the 6502 co-processors use `CALL &300` and answer `*PIVDU` with `Bad command`,
error 254. Getting this wrong is the first thing that happens after a core
switch, and the error points at the routing line rather than at the mismatch.

It must be applied **before** `MODE`, because mode 21 does not exist until
output is routed to the Pi and the host MOS would refuse it.

Implemented:

- Socket open / connect / recv / send / close, non-blocking via FIONBIO
- **Telnet IAC negotiation** - refuses all options except server ECHO and
  suppress-go-ahead, skips subnegotiation blocks
- **VT/ANSI CSI parsing** - cursor position (`H`/`f`), cursor movement
  (`A`/`B`/`C`/`D`), erase display (`J`), erase to end of line (`K`),
  parameter collection; SGR (`m`) parsed and ignored
- **All five string sequences swallowed**, not just OSC. `ESC ]` (OSC),
  `ESC P` (DCS), `ESC X` (SOS), `ESC ^` (PM) and `ESC _` (APC) all run until
  `BEL` or `ST`, and a parser that knows only `ESC [` and `ESC ]` prints the
  payload of the other four. Seen on hardware 2026-08-19 as
  `3008;start=...;user=user;pid=...;type=shell;cwd=/home/user` at the top of a
  login — shell integration, emitted before the first prompt.

  **That string turned out to be OSC, not DCS or APC**, captured from bash on
  the Linux box: `ESC ] 3008;… ESC \` — an OSC terminated by ST. SOCKSTUB now
  covers OSC+BEL, OSC+ST, DCS+ST and APC+BEL, and the parser swallows all four.
  So if that payload still appears on hardware it is **data loss corrupting the
  introducer** — the `ESC` or the `]` goes missing and everything after it is
  then just text — not a parsing gap. The four extra introducers are worth
  handling, but they were not the cause.
- **OSC and charset escapes swallowed.** `ESC ] ... BEL` (or `ESC \`) is how
  bash sets the window title, on **every prompt**; `ESC ( B` selects a
  character set. Neither is CSI, and a parser that only knows `ESC [` prints
  their payload. Measured against the stub, old parser then new:
  `0;user@box: ~BE` becomes `E`. This was the source of the spurious
  characters seen on hardware 2026-08-19
- Keyboard input with `*FX4,1` so cursor keys report 136-139 and are sent as
  `ESC[A`-`ESC[D`; `*FX229,1` so ESC is deliverable; CTRL-] quits

Verified against the extended stub script:

| Stub sends | Client displays | Meaning |
|---|---|---|
| `IAC WILL ECHO`, `IAC WILL SGA`, `A` | `A` | negotiation consumed |
| `ESC[2J` `B` | `^L` `B` | erase mapped to CLS |
| `ESC[5;20H` `C` | `C` | CSI consumed, not printed |
| `ESC[1;32m` `D` `ESC[0m` | `D` | SGR ignored, not printed |

**Limits of that verification.** The printer capture is a character *stream*,
not a screen, so it proves escape sequences are consumed rather than printed
literally - it does **not** prove the cursor landed in the right place. Cursor
positioning needs checking on the actual display. And the whole thing runs
against SOCKSTUB's guessed conventions (§9.2).

**Two things dominate interactive smoothness, and neither is the read size.**
Reported from hardware 2026-08-19: `ll` arrives correct but in visible steps,
while `*CAT` on the share — same screen, same rendering path — is slower but
smooth. So the stutter is in the receive loop, not the display.

- **Keyboard polled only between drains.** While a full-screen program is
  repainting, the socket is never empty, so a keypress waited for the whole
  backlog before being sent — `q` to leave `top` took seconds. `PROCpump` now
  polls the keyboard every `keyev%` bytes *during* the drain. The backlog still
  has to render, but the keystroke reaches the far end at once and stops it
  sending more.
- **One read per pass round the main loop.** Every pass also calls `PROCkeys`,
  and on a co-processor `INKEY` is an OSBYTE across the Tube, so a keyboard
  round trip was being paid for every 128 bytes. `PROCpump` now drains until the
  socket is empty, capped at `drain%` bytes so `CTRL-]` still answers during a
  long listing.
- **`PROCzero` on every poll.** It zeroes 28 bytes in a BASIC `FOR` loop, and
  **98% of polls return `&1E`** (1348 of 1368 measured), so that loop was most of
  the cost of discovering there was nothing to read. `FNnet_recv` now sets only
  the fields the call actually reads.

**`FNnet_recv` uses adaptive read sizing** (§5.5c) rather than one byte per
call: double the requested count on success, and **drop straight back to 1** on
`&1E`.

Not halve. `tput3` halved and measured well, but it measured a *saturated*
burst, where the requested size rarely overshoots what is waiting. Interactive
output is the opposite: at the end of every command's output the pipe runs dry,
and halving from 128 spends 128/64/32/16/8 as **failed** calls — five Tube round
trips that deliver nothing — before reading a byte. On hardware that is a
visible stutter at the end of each command. Dropping to 1 costs one wasted call
instead of five, and the ramp back up consists entirely of successful reads, so
it is free. **A throughput benchmark will not show this; only interactive use
does.** Idle polling
settles at one byte per call and costs no more than before; a burst ramps to the
128-byte cap within a few iterations. That lifts the ceiling from 72 bytes/sec
to the 3082 measured in §5.5c, and is why no host-side batching layer is needed.
Verified against SOCKSTUB, which models the exact-count behaviour (§9.2).

**CONFIRMED ON HARDWARE 2026-08-19: `ll` renders cleanly, no lost characters.**
Copro 2, MODE 21 via `CALL &300`, logged into the socat shim on the Linux box.
That is the first end-to-end run with the transport actually correct — the
`+2`, `+4`-range and short-read handling all in place.

**Full-screen support added 2026-08-19** — the three things every TUI assumes:

- **Scrolling regions** (`ESC[t;br`). A BBC **text window is** a scrolling
  region: text scrolls inside it and leaves the rest of the screen alone, so
  `VDU 28` maps this onto the hardware instead of emulating it. The catch is
  that ANSI counts rows from the top of the *screen* while `VDU 31` inside a
  window counts from the top of the *window*, so `PROCgoto` subtracts the region
  origin and clamps. Miss that and every cursor address inside a region is wrong
  by the region's top.
- **Alternate screen** (`ESC[?1049h/l`, and the older `?47`). The BBC has no
  second screen buffer and no way to read the current one back, so **the
  previous contents cannot be restored** on exit. Clearing on both transitions
  is still far better than ignoring it, which is what left `top` painting over
  the shell and leaving debris behind.
- **Cursor save/restore** (`ESC7`/`ESC8` and `CSI s`/`CSI u`).
- **Deferred wrap, emulated in software.** The BBC has a full 80 columns, 0–79,
  so `cols 80` is arithmetically correct — the difference is *when* it wraps. A
  VT filling the last column leaves the cursor **pending** and only moves on the
  next character; the BBC moves at once. So a full-width line is already on the
  next row when the host's `CR LF` arrives, and the `LF` costs a second row.
  That is the line overflow and the apparent double spacing.

  **Deferring the LF is not sufficient on the bottom row.** The BBC performs the
  *wrap* itself, immediately, and on the bottom row a wrap is a **scroll**.
  Modelled against a real 64x80 `top` capture: every frame ends with a
  full-width bottom line, giving **one scroll per refresh** — the display
  marches up a row each time it repaints. A VT sets pending-wrap there and
  scrolls nothing, because `top` repositions with `ESC[H` for the next frame.
  `PROCput` therefore **drops the bottom-right cell**, which costs one character
  that full-screen programs pad with a space. Re-modelled with that in place:
  zero scrolls.

  Alongside it, `PROCvt` tracks whether a printable character left `POS=0` and
  **swallows exactly one following `LF`**, which restores VT behaviour and gets the 80th
  column back. **Confirmed on hardware 2026-08-19** at `cols 80`: the
  full-width ruler through `PROCvt` fits, and an ordinary session is clean.
  `top` itself has **not** been run since the change. `stty cols 79` also avoids the fault, by never
  filling the last column, but it throws a column away and is no longer needed.
- **Scroll protection** — `VDU 23,16,1,254,0,0,0,0,0,0`. Without it, a
  character written in the **last column scrolls the screen immediately**, and
  no full-screen program survives that: `top` writes full-width lines
  constantly. Bit 0 of the cursor-movement flags makes going off the right edge
  generate a *pending* newline instead — the Master's equivalent of VT deferred
  wrap, and the reason the last column can be blanked at all. `x=1, y=254` sets
  bit 0 and leaves the other flags alone.
- **ED and EL in full** (`ESC[0J/1J/2J`, `ESC[0K/1K/2K`). Only `ESC[2J` was
  handled, and `ESC[0J` — erase from the cursor to the end of the screen — is
  the one full-screen programs actually use, so everything below the cursor was
  being left on screen.

Screen size is **measured, not assumed** — `PROCgeom` walks the cursor out along
each axis, the technique from `vdutest.bas`, because mode 3 on the host and mode
21 on the co-processor are different shapes. `PROCeol` uses that width; it
previously blanked to a hardcoded column 78.

**Colour implemented and CONFIRMED ON HARDWARE 2026-08-19.** Rather than hunting for which GCOL numbers
happen to resemble ANSI colours, `PROCpal` **defines** logical 0–15 as the
xterm ANSI 16 with `VDU 19,l,16,r,g,b` — which §2.3 established is exactly what
those 16 palette entries are for — and addresses them directly with `VDU 17,n`
for foreground and `VDU 17,128+n` for background. So the mapping is chosen, not
discovered.

`PROCsgr` handles 0, 1/22 (bold as the bright half), 7/27 (reverse), 30–37,
90–97, 39, 40–47, 100–107, 49, and `38;5;n` / `48;5;n` reduced to the 16 by
`FNx256`: 0–15 pass through, 16–231 is the 6×6×6 cube thresholded to a colour
plus a bright bit, 232–255 is the grey ramp. Nearest-ish rather than exact,
which §2.3 says is all this mode can offer anyway.

Not yet implemented: DNS (`Resolver_GetHostByName` - use a dotted quad),
character sets beyond swallowing the escape, window size reporting.

`idle%` in the configuration block exits after 8 seconds of silence purely so
automated emulator tests terminate. **A real terminal wants `idle%=0`.**

### 9.4 Gotchas found while building the stub and client

- **Only &A8-&AF is zero page scratch for paged ROMs.** &A0-&A7 belongs to MOS;
  using it corrupts the OS. State that must outlive a call belongs in the
  claimed workspace page.
- **The Master has BASIC IV, not BASIC V.** `REPORT$` is a BASIC V (Archimedes)
  function; on BASIC IV it parses as an undefined string variable and raises
  error 26, "No such variable". Use the **`REPORT` statement** instead. This bit
  every error handler written here, and the emulator never caught it because the
  error paths were never exercised. `CASE`/`OF` and `WHILE`/`ENDWHILE` are
  likewise BASIC V only.
- **Undefined variables raise error 26**, they do not default to zero. Anything
  an error handler touches must be initialised before the first line that can
  fail, or the handler dies masking the real error.
- **BBC BASIC `FOR` loops always execute at least once** - the test is at
  `NEXT`. `FOR i%=0 TO n%-1` with `n%=0` runs one iteration and reads garbage.
  Guard zero-length loops explicitly.
- **`*HELP` hangs under b-em's `-paste`**, with or without a ROM fitted -
  it appears to wait for a keypress. Not a ROM bug; avoid `*HELP` in automated
  tests.
- **`tools/b-em` is a LOCAL BUILD patched to `fflush` the printer file** after
  every character (`src/uservia.c`). Stock b-em never flushes and dies on
  SIGTERM, so captures were silently truncated to 4096-byte boundaries - which
  repeatedly looked like programs hanging when they had in fact completed.
  Re-apply that patch if b-em is ever rebuilt from clean sources.
- `-sp9` runs the emulation at 500%. The default speed 4 is real BBC speed.

### 9.5 What the emulator cannot test

No BBC emulator implements the Sprow module, so OSWORD &C0 goes unclaimed.
`nettest.bas` correctly reports `*** NOTHING CLAIMED OSWORD &C0` there. **Step
0a must run on real hardware.** The emulator's value is validating that the
BASIC runs, and hosting a stub ROM (not yet written) for offline client
development.

### 9.6 What 2026-08-28 cost, and what it taught

Every one of these was self-inflicted, and each cost a hardware run or an
hour. They are recorded because the next person to write C for this machine
will meet all five.

**A fixed memory map shared between C and BASIC needs a machine checking it.**
`PARAM` sat at `&4108000`, chosen when the only blob was ARMSPIKE's 131 bytes.
The SSH blob is 48KB, so BASIC wrote its arguments 32,768 bytes **into the
blob's own code**; the session reached "connected" and wedged when execution
reached a corrupted instruction. `tools/sshbuild.sh` now fails the build if
the blob reaches `PARAM`. Addresses chosen for a spike do not survive the
thing the spike was for.

**BBC BASIC's `$` terminates with CR, not NUL.** `$nm%="user"` stores
`p a u l &0D`, so C's `strlen` ran past the name. The whole key exchange
succeeded and authentication failed; `sshd` logged
`Invalid user user\rUTQE\027UU...`. Never hand a `$`-written string to C
without stripping it — and note that the far end's log was the debugger here,
which is an argument for keeping a server you control on the same LAN.

**A variable read before assignment STOPS the program.** BBC BASIC does not
default to zero on read; it raises "No such variable". A heartbeat timer
assigned later on the same line as its first read killed two runs, and the log
simply ended at the previous statement — indistinguishable from a hang.
`baslint.py` now catches this.

**`PROCef` does a `BPUT` per character**, and at LANManFS speeds a 32KB
`RESPROF` is minutes of writing. That is what made `CTRL-]` appear to hang.
`PROCrlsave` had carried the answer since it was written and its comment says
it in one line: *one OSFILE, not a BPUT per byte*.

**A driver CAN be renumbered — in bands.** "This file cannot be renumbered"
was said four times here while fumbling line numbers, and it was an
overstatement that became an excuse. The real constraint is that a driver
shares a file with the engine by line number, so it must be renumbered in
bands rather than as one sequence: `basrenum.py --bands 0:10:3 1000:10000:10`.
There was room all along.

**And one that was not a mistake but a method.** Twice, a wrong number was more
informative than a right one. A signature that failed **half** the time pointed
at a condition true for half of all inputs — an `mpint` gains a leading zero
when its top bit is set, and the buffer was one byte short. A read that
returned **exactly five** words every time pointed at a FIFO drain rate rather
than broken silicon. A deterministic wrong answer is evidence; reading the code
that looked guilty would have found neither, because in both cases that code
was correct.

---

## 10. Sources

- [Sprow Master 10/100 Ethernet module](https://www.sprow.co.uk/bbc/masternet.htm)
- [OSWORD &C0 sockets API](https://mdfs.net/Docs/Comp/BBC/Network/Sockets)
- [PiTubeDirect](https://github.com/hoglet67/PiTubeDirect)
- [PiTubeDirect Pi VDU driver](https://github.com/hoglet67/PiTubeDirect/wiki/Pi-VDU-Driver)
- [Serial ULA reference](https://beebwiki.mdfs.net/Serial_ULA) (superseded design)
