# BBC Master CMOS configuration — restore list

**Why this file exists:** the CMOS backup battery on this machine is dead. A
replacement CMOS chip with a cell battery on top is on order (expected within a
couple of days of 2026-08-18). Until it is fitted, **every power-off loses the
configuration** and the machine comes up on defaults.

A soft **BREAK** does *not* lose CMOS — only powering off does. `*CONFIGURE`
changes need **CTRL-BREAK** to take effect.

---

## 1. Baseline captured 2026-08-18

Full `*STATUS` output while the machine was known-good:

```
Configuration status:
Baud        1
No Boot
Shift Caps
Data        0
Delay       0
Directory
Internal Tube
FDrive      0
File        0
Hard
Ignore      0
Lang        0
Mode        0
No Tube
Quiet
Print       0
Repeat      0
Scroll
TV          0,0
EMLink      Auto
EMAdvertise 10 Half Full 100 Half Full
EMAddr      Auto
EMMask      Auto
Gateway     Unset
DNS         Unset
```

---

## 2. Valid `*CONFIGURE` keywords on this machine

Confirmed by typing `*CONFIGURE` with no arguments (`*HELP CONFIGURE` returns
nothing — it is not the right form):

```
Baud <D>      Boot          Caps          Data <D>      Delay <D>
Dir           ExTube        FDrive <D>    File <D>      Floppy
Hard          Ignore [<D>]  InTube        Lang <D>      Loud
Mode <D>      NoBoot        NoCaps        NoDir         NoScroll
NoTube        Print <D>     Quiet         Repeat <D>    Scroll
ShCaps        Tube          TV [<D>[,<D>]]
EMLink <Auto>|<10|100 [Half|Full]>
EMAdvertise [10 [Half] [Full]] [100 [Half] [Full]]
EMAddr <Auto>|<D.D.D.D>      EMMask <Auto>|<D.D.D.D>
Gateway [D.D.D.D]            DNS [D.D.D.D] [D.D.D.D]
```

Note `InTube` / `ExTube` select *which* Tube; `Tube` / `NoTube` enable or
disable it. They are independent settings.

---

## 3. To use the Raspberry Pi co-processor

Currently `Internal Tube` (correct — the Pi kit plugs into the motherboard Tube
connectors) but `No Tube` (disabled).

```
*CONFIGURE Tube
```

then **CTRL-BREAK**.

`InTube` is already correct and should not need setting unless CMOS has been
lost.

> **Warning:** CTRL-BREAK destroys any BASIC program in host RAM. With the Tube
> enabled, BASIC runs on the co-processor and the host program is unreachable.

---

## 4. Keyboard auto-repeat is OFF

`Delay 0` **disables keyboard auto-repeat entirely** (OSBYTE 11 with zero turns
it off). This is why the COPY key does not repeat when held, which makes cursor
editing far more laborious than it should be.

**Both** OSBYTEs are needed - they control different things:

| Call | Controls | Configured here |
|---|---|---|
| `*FX11,<n>` | delay before the FIRST repeat; `n=0` disables repeat entirely | `Delay 0` |
| `*FX12,<n>` | period BETWEEN subsequent repeats | `Repeat 0` |

Symptom of fixing only the first: the key repeats once, then stops.

Immediate fix (no reset needed):

```
*FX11,50
*FX12,8
```

Persistent (needs CTRL-BREAK, and lost on power-off until the battery is
replaced):

```
*CONFIGURE Delay 50
*CONFIGURE Repeat 8
```

Beware: `*FX12,0` resets the delay and rate to the **configured** values, not to
factory defaults. With `Delay 0` configured, that leaves auto-repeat off.

---

## 5. Network settings

`EMAddr`, `EMMask`, `EMLink`, `Gateway` and `DNS` appear in `*STATUS`, so they
live in the **BBC's CMOS** and will be lost with everything else. Earlier
speculation that they lived only in the module's own NVRAM was wrong.

Current values are `Auto` for address and mask, which means DHCP — and DHCP has
been working (the module holds 192.0.2.20). So after a power cycle the
defaults should still give a working address without intervention.

**`Gateway` and `DNS` are both `Unset`.** Consequences:

- No name resolution, so `Resolver_GetHostByName` (&40) will not work. Use
  dotted-quad addresses, as `beeblink.bas` and `beebterm.bas` already do.
- No off-subnet routing. Only hosts on 192.168.86.x are reachable.

If either is needed later:

```
*CONFIGURE Gateway 192.0.2.1
*CONFIGURE DNS 192.0.2.1
```

(substituting the real router address).

---

## 6. ROM enablement

`*UNPLUG` / `*INSERT` state is **also stored in CMOS** and will be lost.

```
*ROMS
```

Check LANMANAGER is present and not marked unplugged. If it is:

```
*INSERT <n>
```

using the slot number `*ROMS` reports. The socket API (OSWORD &C0) lives in
LANMANAGER — nothing network-related works without it.

---

## 7. One-time setup when the new CMOS chip arrives

The replacement chip has its own cell battery, so settings will finally stick.
Apply these **once**, then CTRL-BREAK.

Values below were verified live with `*FX` before being committed to CMOS, so
they are known-good on this machine rather than assumed.

### Required

```
*CONFIGURE Delay 50
*CONFIGURE Repeat 8
```

Keyboard auto-repeat. Currently `Delay 0` / `Repeat 0`, which disables it and
makes the COPY key useless for cursor editing. Verified working as `*FX11,50`
and `*FX12,8` on 2026-08-18.

### Required if using the Raspberry Pi co-processor

```
*CONFIGURE Tube
```

`InTube` is already correct and only needs setting if CMOS was lost:

```
*CONFIGURE InTube
```

### Optional — only if off-subnet access or hostnames are wanted

```
*CONFIGURE Gateway <router address>
*CONFIGURE DNS <dns address>
```

Both are currently `Unset`. Without them, only 192.168.86.x is reachable and
`Resolver_GetHostByName` cannot work. Not needed for the current design, which
uses dotted quads throughout.

### Leave alone

Everything else in the §1 baseline is fine as it stands. In particular
`EMAddr Auto` / `EMMask Auto` means DHCP, which has been working reliably.

### Then verify

```
*STATUS
```

Confirm `Delay 50`, `Repeat 8`, and `Tube` if set. **Power cycle** (not just
BREAK — only a genuine power-off tests the battery) and run `*STATUS` again.
If the values survive, the new chip is doing its job and this file becomes
historical.

Also re-check:

```
*ROMS
```

LANMANAGER must still be present and not unplugged — see §6.

---

## 8. Booting straight to the share (2026-08-21)

Goal: power on, get Acorn MOS and BASIC, with LANManFS selected and
`\\192.0.2.10\beeb` mounted, without typing anything.

### 8.1 `FILE` and `LANG` take ROM numbers, not filing system ids

The New Advanced User Guide's CMOS map gives byte 5 as **"Default filing system
ROM number"** (d0-3) and **"Default language ROM number"** (d4-7). Both are ROM
numbers. Confirmed against the machine rather than a manual: b-em's Master
defaults read `File 9` / `Lang 12` in `*STATUS`, and its `*ROMS` reports **ROM 9
= DFS** and **ROM C = BASIC**. It is also why the usual advice for a Master is
`*CONFIGURE FILE 9` for DFS.

**This is what makes the whole thing possible.** LANManFS's *filing system id*
is 102 and would never fit in a nibble — but its **ROM number** will, so
LANManFS can be the boot filing system like any other.

Run `*ROMS` and read the two numbers off this machine; `FBBOOT` captures it.

```
*CONFIGURE LANG <BASIC's ROM number>       Acorn MOS then BASIC at power on
*CONFIGURE FILE <LANMANFS's ROM number>    LANManFS selected at power on
```

### 8.2 What CMOS cannot do

- **Mount.** `*MOUNT` is a command, not a setting. Selecting the filing system
  does not connect it to anything.
- **Run a `!BOOT` off the share.** The module's manual is explicit: *"The only
  valid boot option for shared discs is zero (off)."* So the usual
  `*CONFIGURE BOOT` + `!BOOT` trick is unavailable here, and `NoBoot` should
  stay set — with `Boot` configured and LANManFS selected, a reset would only
  produce a failed boot attempt.

### 8.3 Three routes to an automatic mount

1. **The module's own `Choices:Internet.Startup`.** Four sections: interface,
   network, **CIFS** (defaults that let `*MOUNT` be used in shorthand) and
   **Hosts**. It lives in the module, not in the Beeb's CMOS, so it has quietly
   survived every power cycle of this project. **Nobody has ever read it** —
   that is the first thing to do, and it may already offer more than shorthand.
   Edit with `*EDIT Choices:Internet.Startup`, save with `F3-COPY-RETURN`, then
   CTRL-BREAK.
2. **A small sideways ROM** that issues `*LANMAN` and `*MOUNT` at reset. The
   only route that is certainly sufficient, and it needs an EPROM or a flash
   cartridge. It can be proved first in **sideways RAM** with `*SRLOAD`, which
   burns nothing — the image is lost at power-off, so that tests the ROM without
   committing to it.
3. **Type two commands.** `*LANMAN` then `*MOUNT \\192.0.2.10\beeb`.

**MOUNT AFTER THE BREAK, NEVER BEFORE.** CTRL-BREAK is a hard reset and clears
sideways ROM private workspace, so LANManFS loses the mount with it. Mounting on
the host and then breaking to the co-processor throws the mount away and the
share is simply gone. `*MOUNT` works from the parasite — it is a `*` command and
the host's ROM executes it — so the order is: break to the co-processor first,
select the language, then mount.

```
(power on)                       host MOS, LANManFS, BASIC
CTRL-BREAK                       to the co-processor
*ARMBASIC                        with copro=15 in cmdline.txt
*MOUNT \\192.0.2.10\beeb
*DIR Pi-TERM
CHAIN "PTERMRUN"
```

### 8.4 `\\deskbox\beeb`

The **Hosts** section of `Choices:Internet.Startup` is a name table consulted
**before** the DNS:

```
192.0.2.10 deskbox      # the Linux box
```

That makes `\\deskbox\beeb` work whether or not the router's DNS knows the
name, and it removes the dependency on `*CONFIGURE DNS` being right. Worth
having even with DNS configured, since it is one fewer thing between the machine
and its files.

### 8.5 The settings to apply, once the numbers are known

```
*CONFIGURE LANG <BASIC ROM>          *CONFIGURE Delay 50
*CONFIGURE FILE <LANMANFS ROM>       *CONFIGURE Repeat 8
*CONFIGURE NoBoot                    *CONFIGURE Tube        (if the Pi is wanted)
*CONFIGURE Gateway 192.0.2.1      *CONFIGURE InTube
*CONFIGURE DNS <router>
```

then CTRL-BREAK, then `*STATUS` to confirm. §7's list still applies; this
extends it.

### 8.6 The numbers, off the machine (`RESBOOT`, 2026-08-21 23:10)

```
ROM F TERMINAL 01     ROM B Edit 01        ROM 7..0  ?
ROM E VIEW 04         ROM A ViewSheet 02
ROM D Acorn ADFS 50   ROM 9 DFS 79
ROM C BASIC 04        ROM 8 LANMANAGER 03
```

**BASIC is ROM 12 (C). The network ROM is ROM 8.** `*ROMS` names only
`LANMANAGER` there, but `*HELP LANMANFS` answers `LANMANFS 0.37` and no second
ROM appears — **both live in ROM 8**, so that is the number `*CONFIGURE FILE`
wants.

**Observed 2026-08-21 23:5x: with `Lang 0` / `File 0` a CTRL-BREAK lands in
ADFS and not in BASIC.** Both settings point at ROM 0, which is empty, so the
MOS falls back — and ADFS (ROM 13) outranks DFS (9) and the network ROM (8).
Worth fixing now even with a flat battery: **CMOS survives a soft BREAK and only
power-off loses it**, so this holds for the rest of a session.

**IT SURVIVED A POWER CYCLE (2026-08-22).** With `LANG 12` and `FILE 8` the
machine came up from **cold** in Acorn MOS with BASIC and LANManFS selected.
That is the wanted startup, less the mount, which is typed.

**The battery is NOT fixed — measured, 2026-08-22 00:11.** `FBRTC` run straight
after that cold start reads **`VRT FIRST READ == D 0`**: backup power was not
maintained across it. What carried the configuration was the **100µF capacitor**
across the clock chip's supply, which exists to bridge exactly such a brief
disconnection. So a short power cycle proves nothing, and the replacement chip
is still needed.

The clock itself came through correctly — `hour 0 min 5 sec 51, dow 7, date 22,
month 8, year 26` — so `FBRTCW`'s write holds and the oscillator runs. That is
the capacitor too, not the cell.

`VRT FIRST READ` is the whole test, and every power loss re-arms it.

**There is no undocumented auto-mount directive.** A speculative
`Mount \\192.0.2.10\beeb` line was written into the module's Choices file
(`FBNETW` with `mount%=TRUE`) and ignored, as the CIFS section's single `Logon`
directive predicted. The file accepts any line and acts only on the ones it
knows.

**SETTLED, 2026-08-22: `LANG 12` and `FILE 8`, and both are ROM numbers.**
With those two set, a CTRL-BREAK — and a cold start — bring the machine up in
**Acorn MOS, LANManFS and BASIC**. That is the whole of the wanted startup
except the mount, which is typed.

Confirmed against the chip rather than inferred: `FBRTC`'s dump has register 19
(CMOS offset 5) reading **`&C8`**.

```
d4-7 language ROM   = 12    BASIC is ROM 12
d0-3 filing sys ROM = 8     the network ROM is ROM 8
```

Which agrees with both manuals — the New Advanced User Guide's CMOS map
(*"default filing system **ROM** number"*) and the Advanced Master Reference
Manual's Appendix Two (`FILE <ROM>`). A detour through "`FILE 9` selects
LANManFS", and a theory invented to explain it, came from a typo at the
keyboard; there was never anything to explain.

```
*CONFIGURE LANG 12        BASIC          (was Lang 0, and ROM 0 is empty)
*CONFIGURE FILE 8         LANManFS       (was File 0, likewise empty)
*CONFIGURE Delay 50       (was 25, the default)
*CONFIGURE Repeat 8       (was 9, the default)
*CONFIGURE NoBoot         see below
*CONFIGURE Tube           only if the Pi co-processor is wanted (currently No Tube)
```

`Lang 0` and `File 0` both point at an empty socket, which is why the machine
was reaching BASIC by fallback rather than by configuration — and why a reset
landed in ADFS, the highest-priority filing system ROM.

Both values are ROM numbers, so `*ROMS` is the only lookup needed.

**`Boot` is currently configured, and should not be.** With `File 8` the MOS
would try to boot from a filing system that has nothing mounted, at every
power-on, for nothing. Revisit only if a boot ROM is written — service call &03
is issued on an autoboot, so a ROM that hooks it needs `Boot` back on.

### 8.7 The network needs nothing from CMOS

`*STATUS` reads `EMLink`, `EMAdvertise`, `EMAddr`, `EMMask`, `Gateway` and `DNS`
**all Unset**, while `*EMINFO` in the same run reports a fully working stack:

```
Net address : 192.0.2.20      Gateway     : 192.0.2.1
Net mask    : 255.255.255.0      Primary DNS : 192.0.2.1
```

**All of it is coming from DHCP.** So the six `EM*`/`Gateway`/`DNS` settings can
stay `Unset` for good, and their being lost with the CMOS battery has never
mattered. Do not spend effort restoring them. (A `*CONFIGURE DNS` made earlier
in the day is not in CMOS — but DHCP is supplying a DNS anyway, so **there is a
real chance `*MOUNT \\deskbox\beeb` already works**: the Linux box's hostname
*is* `deskbox`, and Samba has NetBIOS enabled as a second route to the name.)

### 8.8 Reading `Choices:Internet.Startup` — OSFile only

**`*TYPE` and `*EDIT` both answer "Bad name", and the manual's own
`*EDIT Choices:Internet.Startup` instruction does not work on this machine.**
The reason is in the same manual, under "Startup configuration file": the pseudo
file is *"held inside a non volatile memory chip on the network module"*, and
*"LANMANFS will divert a limited subset of OSFile operations (only)"* to it.

`*TYPE` opens the file with OSFind and reads it with OSBGet. `*EDIT` does the
same. **Neither is an OSFile call**, so both are asking the *share* for a file
whose name it cannot even parse — hence Bad name rather than Not found.

What is diverted:

| OSFile | |
|---|---|
| A=5 | read cat info — gives the length |
| A=255 | load named file, **using the given address only** (so the exec address low byte must be zero; the module has no load address to offer) |
| A=0 | save — replaces the configuration; each line is checked to be ≤80 bytes including the CR, though the syntax is not checked |
| A=1,2,3,4 | return the object type only |
| A=6,7 | delete and create are **ignored** |

So the file is perfectly reachable, just not by anything that treats it as a
stream. `test/fbnet.bas` reads it: OSFile 5 for the length, OSFile 255 into a
buffer, then both a spooled listing (`RESNET`) and a byte-exact `*SAVE`
(`RESSTRT`), because a listing is a rendering and the bytes are the evidence.

Writing it back is OSFile 0 with the same block — the route for adding a Hosts
line — and the 80-byte line limit is enforced by the module, not by us.
