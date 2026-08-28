# Running a `.ssd` disc image on the real machine

**Why this file exists:** the Master has no disc drive, so a `.ssd` is inert. It
is also unnecessary. A DFS image is only a container; what the machine actually
needs is the file inside it plus the two numbers DFS stores next to it — the
**load address** and the **execution address**. Both are absolute, so once the
file is loose, any filing system that can deliver bytes will do. Here that is
LANMANFS over the Samba share (`tools/setup-samba.sh`), and the whole conversion
is a `*LOAD` to the right address.

---

## 1. Unpack the image

```sh
tools/ssd-extract.py "share/Arcadians (1982)(Acornsoft).ssd" share/
```

```
title "ARCADIANS"  boot option 3  2 files
  $.!BOOT   load &FFFFFF  exec &FFFFFF  length &000D
  $.Arcade  load &1900    exec &3F00    length &4C00 (19456 bytes)
```

Write the addresses down — on the real machine they are the only part of the
catalogue that survives. A `.inf` is written alongside each file for b-em's
VDFS, which does read them; LANMANFS has nowhere to keep them, so `*RUN` over
the share will not work and the addresses must be supplied by hand.

`!BOOT` is worth reading (`*B.` then `*/ARCADE` here) — it is the disc's own
instructions for starting itself, and occasionally does more than one `*RUN`.

---

## 2. Run it

```
MODE 7:OSCLI("LOAD ARCADE 1900"):CALL &3F00
```

One immediate-mode line, deliberately: nothing scrolls between the load and the
call. Three things have to be true first.

| Requirement | Why |
|---|---|
| **Tube off** | `*CONFIGURE NoTube` + CTRL-BREAK (see `cmos-config.md` §3). With a co-processor active, `*LOAD` and `CALL` land in *its* RAM; a game that pokes the 6845 and screen memory then runs blind and the machine looks hung. |
| **MODE 7** | The load must not collide with screen memory — see below. |
| **No shadow mode** | `MODE 135` frees all of &3000–&7FFF and looks like the tidier answer, but games plot straight into their screen. In shadow RAM those writes go nowhere visible. |

---

## 3. The mode trap

A file loaded at `&1900` with length `&4C00` occupies **&1900–&64FF**. Screen
memory starts at:

| Mode | Screen base | Clash with &1900–&64FF? |
|---|---|---|
| 0, 1, 2 | &3000 | yes, badly |
| 3 | &4000 | yes |
| 4, 5 | &5800 | yes |
| 6 | &6000 | yes |
| **7** | **&7C00** | **no** |

In anything but MODE 7 the tail of the file lands in screen RAM. The load itself
completes — screen memory is ordinary RAM — but the cursor, and the scroll from
the next thing typed, overwrite it before the program is ever entered. The
symptom is a screenful of garbage during the load, then a crash or a hang.

MODE 7 is also what the original disc boot ran in: SHIFT-BREAK leaves the
machine in the configured mode and `!BOOT` starts from there.

---

## 4. Why a big file fits at all

Arcadians is 19K and runs on a 32K Model B, which does not add up until you look
at the entry point. `&3F00` is `JMP &60D0`, and `&60D0` is a relocator:

```
JSR &5DB1      ; *TAPE, then OSBYTE 202 (keyboard), STA &D8
LDY #0
LDA &1900,Y    ; 256 bytes  &1900 -> &0C00   (soft characters)
STA &0C00,Y
DEY : BNE
...            ; pages &1B00-&64FF -> &0E00-&57FF
LDX #&58       ; stop when the destination page reaches &58
JMP &49DA
```

So `&1900` is a staging area, not where the program runs. It moves itself down
to **&0C00 and &0E00–&57FF** and takes a 20K screen at &5800 (MODE 4/5 layout).
Two consequences:

- The `*TAPE` is the game deselecting the filing system so it can use the RAM
  the filing system was holding. That is why LANMANFS workspace is not a problem
  here: the program drops it before it moves down.
- &0D00–&0DFF is deliberately skipped — it is the extended vector table. A
  pre-relocated single-file version of a program that does this is therefore not
  possible without splitting it in two.

Expect this shape from any tape-era game: **the load address is temporary and the
run address is somewhere else entirely.** Read the entry point before assuming a
clash is fatal, and before trying to "fix" a load address.

---

## 5. If it does not start

| Symptom | Look at |
|---|---|
| Garbage on screen during the load | Not MODE 7. §3. |
| Silence, no output at all | Tube still enabled. §2. |
| Starts, then dies | Filing system workspace, if the program does not `*TAPE` itself. Check `PRINT ~PAGE` — a Model B game assumes &0E00. |
| Wrong colours, keys dead | Genuine MOS 3.20 vs OS 1.2 incompatibility. Boot the original image in b-em to confirm it is the machine and not the transfer: `tools/run-beeb.sh -disc "<image>.ssd" -autoboot` |

---

## 6. The games menu (`share/GAMES/START`)

```
*DIR GAMES
CHAIN "START"
```

Source `src/start.bas`, built with `tools/gamesmenu.sh`. It lists the games it
can actually find and runs the right start sequence for the one chosen.

**It moves itself to `&6500` and re-chains.** That is the whole design, and §2's
"one immediate-mode line, deliberately" is why. `ARCADE` loads at `&1900` and is
`&4C00` long, so it lands on `&1900`-`&64FF` — straight over a BASIC program at
a normal `PAGE`, **including the line holding the `CALL` that comes next**. An
immediate-mode line escapes that because it lives in the input buffer; a menu
cannot, so it gets out of the way instead. Above `&64FF` and below MODE 7's
`HIMEM` of `&7C00` leaves 5888 bytes, and the tokenised menu is 3110.

That is not a new trick — it is what the discs themselves do. `LOADER` and
`SNAPPER` both set `PAGE=&4000` before chaining `SNAP1`, because `SNAP2` loads
at `&1900` and reaches `&3F23`.

Proved under b-em before it went near the machine: a program relocated to
`&6500` runs `MODE 7`, `*LOAD ARCADE 1900`, `CALL &3F00`, and control passes to
the game and never comes back — no error, and the line after the `CALL` never
executes.

### Choosing with the cursor keys

A `*` marks the current game; up and down move it, wrapping at both ends;
RETURN starts it; `Q` or `0` quits. The number keys still work as a shortcut and
start the game at once.

There is no instruction line — `Q to Quit` rides on the right of the heading, in
its own colour, and the marker explains itself. Both rows of a double-height
line have to be identical, so the whole heading including `Q to Quit` is printed
twice; it comes to 33 of MODE 7's 40 columns, counting the three control codes
that each occupy a cell.

**The cursor is turned off** with `VDU 23,1,0;0;0;0;`. It parks on the marker
cell and flashes there, which on a menu reads as the marker itself flickering.
It is turned back on before quitting to BASIC — a game will set whatever it
wants, but a person at a prompt needs to see it.

`*FX4,1` is what makes this possible — it stops the cursor keys editing the
screen and has them return codes instead: `&88` left, `&89` right, `&8A` down,
`&8B` up. **It must be put back with `*FX4,0` before a game starts.** Meteors
sets it itself, but a game that does not would find its cursor keys rearranging
the display instead of playing.

**Only the marker is redrawn, never the list.** Reprinting five lines per
keypress flickers, and in MODE 7 it would also have to rewrite the colour
control code that occupies column 2 of each line. The marker sits in column 1,
clear of it. The first item's row comes from `VPOS` after the heading rather
than being counted by hand, so the layout can change without breaking the
arithmetic.

### BREAK returns to the menu

`START` defines the BREAK key when it runs:

```
*KEY 10 *DIR GAMES|MCHAIN"START"|M
```

`*KEY 10` **is** the BREAK key, and this is the key that matters here, because
a game ends by being broken out of — and Arcadians has done `*TAPE` by then, so
the filing system needs re-selecting whatever happens. `|M` is RETURN.

A **soft** BREAK keeps everything this needs:

| | survives a soft BREAK? | why |
|---|---|---|
| the key definition | yes | memory is not cleared on BREAK unless `*FX200` says so |
| the mounted share | yes | the module's manual: only *"a hard or power-on reset"* disconnects |
| the current directory | **no** | hence the `*DIR GAMES` in the definition |

**CTRL-BREAK clears the lot** — share disconnected, soft keys gone. That is the
way out if the definition ever gets in the way, and the reason it is safe to
hand BREAK over to the menu at all.

It goes out through `OSCLI` rather than as a `*KEY` line in the program, so the
quotes are plainly BASIC's own doubled quotes and nothing has to guess whether
`CHAIN` inside a `*` line is a keyword or eleven characters of text. Checked in
the tokenised build: the string is stored as text, with no `&D7`.

**f1 gets the same string.** `*KEY 10` fires on BREAK with no keypress and f1
needs one, but a key that works beats a key that does not — and defining both is
how to find out which this machine actually does.

**When `*KEY 10` does not fire**, these are the things it can be, in the order
worth checking:

1. **CTRL-BREAK rather than BREAK.** A hard break clears every definition —
   *"function key definitions are normally preserved other than following a hard
   break"* (NAUG 14.9.6). This session has asked for CTRL-BREAK repeatedly for
   configuration changes, so it is an easy habit to be in.
2. **The definition never got set** — `START` has to have been run since the
   definition was added to it.
3. **MOS 3.20 not expanding key 10 at reset.** `*KEY 10` programming the BREAK
   key is documented in the Advanced User Guide for the BBC Micro; the New
   Advanced User Guide mentions `*KEY` exactly once and says nothing about key
   10, so the Master inheriting the behaviour is an assumption, not a citation.

**One test separates all three**, and it needs no files:

```
*KEY 1 HELLO|M
```

press **BREAK alone**, then press **f1**.

- `HELLO` appears → definitions survive a soft BREAK on this machine, so the
  fault is specific to key 10 being expanded at reset, and f1 is the answer.
- nothing appears → definitions are not surviving, which almost always means the
  break was a hard one.

### The menu is built stripped

`tools/gamesmenu.sh` runs `basstrip.py` before `bastok.py`. At `&6500` with
MODE 7's `HIMEM` of `&7C00` there are **5888 bytes for the program, its
variables and the BASIC stack**, and the commented build was 4740 of them.
Stripped it is 1807, leaving 4081. The build prints the figure and warns below
1500.

The comments stay in `src/start.bas`, which is the point of `basstrip.py`: the
reasoning is the expensive part to reconstruct, and the machine does not need
it.

### Adding a game

One `DATA` line at 9000:

```
DATA <name>,<kind>,<file>,<load>,<exec>        load and exec in hex
```

| kind | what it does | for |
|---|---|---|
| 1 | `CHAIN <file>` | a disc that brought its own loader |
| 2 | `*LOAD <file> <load>` then `CALL <exec>` | a bare binary, §1's two numbers |

Only games whose `<file>` is actually present are listed — `FNhere` asks
`OSFile` A=5 — so the menu describes the directory rather than the table, and an
entry for a game that is not there costs nothing.

Present:

| game | kind | from | sequence |
|---|---|---|---|
| Arcadians | 2 | its own disc | `*LOAD ARCADE 1900` : `CALL &3F00` |
| Chuckie Egg | 1 | `Disc043.dsd` s0 | `PAGE=&3800` : `CHAIN "CHUCKIE"` → `*LOAD CH_EGG 1100`, `CALL &29AB` |
| Donkey Kong | 1 | `Orig001.dsd` s0 | `CHAIN "DONKEY"` → `*LOAD KONG 1D00`, `CALL &4900` |
| Meteors | 1 | `Disc001.dsd` s2 | `CHAIN "METEORS"` → `PAGE=&5000`, `CHAIN "Meteor1"` → `*LOAD Meteor2 1E00`, `CALL &4000`, `CALL &E00` |
| Snapper | 1 | its own disc | `CHAIN "LOADER"` → `*LOAD INTSCRN 7C00`, `PAGE=&4000`, `CHAIN "SNAP1"` → `*LOAD Snap2 1900`, `CALL &3F00` |

Every sequence was read out of the disc's own loader, never guessed.

### `*RUN` is the one thing that cannot survive the trip

**All three new games' loaders ended in `*RUN`** — `*RUN"CH_EGG"`, `*RUN KONG`,
`*R.Meteor2`. `*RUN` works on DFS because the catalogue holds the load and exec
addresses beside the file, and those are exactly the two numbers LANManFS has
nowhere to keep (§1).

The loaders are worth keeping — they define envelopes, redefine characters, draw
title screens and set up keys — so the fix is to patch **one line** in each:

```
*RUN KONG        ->     *LOAD KONG 1D00
                        CALL &4900
```

The addresses come from the disc catalogue, which is the same place `*RUN` would
have read them.

**Patched at the byte level, not by detokenising and re-tokenising.** A 1982
program round-tripped through a tokeniser risks every line in it; BASIC's line
records are self-contained and `GOTO` targets are encoded line *numbers* rather
than offsets, so splicing a line out and two in disturbs nothing else. Checked
afterwards: 109, 16 and 24 lines respectively byte-identical to the originals,
one line replaced, one added.

### A kind 1 loader needs to fit above its own game

The menu sits at `&6500`, and a loader it chains inherits that `PAGE` unless
told otherwise — so the loader must sit **above the binary it is about to load**
and **below the `HIMEM` of the mode it selects**:

| loader | binary occupies | its MODE | HIMEM | PAGE |
|---|---|---|---|---|
| `DONKEY` | `&1D00`-`&493F` | 7 | `&7C00` | `&6500`, inherited |
| `Meteor1` | `&1E00`-`&407F` | 7 | `&7C00` | `&5000`, set by `METEORS` |
| `CHUCKIE` | `&1100`-`&37FF` | **5** | **`&5800`** | **`&3800`, set by the menu** |

Chuckie Egg is the awkward one: `MODE 5` puts `HIMEM` at `&5800`, so its loader
cannot live at `&6500` at all, and `CH_EGG` reaching `&37FF` means it cannot go
lower than `&3800`. That single window is why kind 1 entries carry a `PAGE` in
the `<load>` column, `0` meaning leave it alone.

### Finding more

`tools/dfs-find.py` searches the archive by title or filename, prints a
catalogue with addresses, and unpacks a side:

```
tools/dfs-find.py chuckie kong meteor
tools/dfs-find.py --cat Disc043.dsd 0
tools/dfs-find.py --get Disc043.dsd 0 /tmp/out
```

**`.dsd` images hold both sides interleaved a track at a time** — ten sectors
from side 0, ten from side 2, repeating. Meteors is on side 2, and a tool that
reads only the first 512 bytes of the file would report the disc as not having
it.

### `MODE` cannot be used inside a PROC or FN

The launch runs at **top level**, and must. `MODE` is illegal whenever anything
is on the BASIC stack, and one PROC call is enough: BASIC answers **error 25,
`Bad MODE`** — *even when the mode asked for is the one already selected and
`HIMEM` does not move.* The first version of this menu did the load and call
inside `PROCgo` and failed on the machine at exactly that line.

The first b-em test did not catch it because it ran `MODE 7` at top level, which
is legal — **the test exercised the recipe, not the code that would run it.**
Reproduced afterwards in three lines, and the fix verified by driving the real
program with the choice forced.

So `FNask` returns the number and the main body does the work. A game needing a
mode other than 7 can therefore have one, which would have been impossible in
the original shape.

### It checks for a co-processor

`HIMEM > &8000` means BASIC is running across the Tube, and these games poke the
6845 and screen memory directly. The menu says so and stops, rather than
loading into the co-processor's RAM and hanging (§2, §5).
