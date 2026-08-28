> # WITHDRAWN 2026-08-26 — DO NOT SEND AS WRITTEN
>
> The measurement this rests on was wrong. The 1.75 cs per scroll and the
> ~18.4 MB/sec derived from it were not the framebuffer: `trace%` was left on
> in `pterm.bas`, and it ORs a scroll mark into `ops%` cell by cell, replacing
> the model and shadow block moves with **5,040 interpreted BASIC passes on
> every scroll**.
>
> With `trace%=FALSE` the same scroll costs **0.20 cs**. That is 368,000 bytes
> moved — glass, the newly-exposed row cleared, model and shadow — at about
> **184 MB/sec**, which is cached-memory behaviour, not the uncached
> framebuffer this document argues for.
>
> Scrolling is now **0.8% of session time**, and the break-even against the
> network is 8.5 bytes per line rather than 46. **Panning would save almost
> nothing.** Section 7, the missing bulk capacitor, still stands and is worth
> sending on its own.
>
> Kept as written because it is a good example of the failure that has run
> through this whole project: a careful measurement of an instrument rather
> than of the machine.

# Question for hoglet: hardware scroll / panning for the Pi framebuffer

**Context in one line:** we have a VT102 terminal running on Copro 15 that
writes the Pi framebuffer directly, and screen scrolling is now its single
largest cost — we would like to know whether a pannable framebuffer is
feasible, or whether there is a better answer we have missed.

---

## 1. What we are running

| | |
|---|---|
| Host | BBC Master 128, MOS 3.20 |
| Interface | Internal PiTubeDirect kit ("Issue 4"), Pi 3A+ |
| Firmware | Indigo Beta1, `PiTubeDirect_20260412_1231`, git `58b5713` |
| `cmdline.txt` | `copro=15 copro1_speed=3 copro3_speed=4 tube_delay=0 elk_mode=0 vdu=1` |
| Co-processor | 15, ARM native, BBC BASIC V |
| Screen mode | **MODE 21** — 640×512, 256 colours, 8bpp |

The application is a telnet client presenting an **80×64 terminal on an 8×8
cell**, i.e. the whole 640×512 framebuffer. It is written in BBC BASIC with a
small amount of assembled ARM for the inner loops.

## 2. What we do, and why we bypass the VDU driver

We get the framebuffer address and pitch from `OS_ReadVduVariables` and **write
pixels directly**, rather than going through the VDU driver. That was a
deliberate decision made on measurement: the terminal maintains its own cell
model and a shadow of what is on the glass, so a flush paints only the cells
that actually changed — typically 120–150 cells out of 5,120. Going through
OSWRCH per character was far slower and could not do damage tracking.

This part works well. **Painting costs 0.17 ms per cell** and is not the
problem.

## 3. The measurement

Scrolling the terminal by one text line means moving 63 of 64 rows of 8-pixel
cells:

```
(64 - 1) rows x 8 pixels x 640 bytes = 322,560 bytes per scrolled line
```

Measured on hardware, consistently across five separate profiling runs:

| | |
|---|---|
| **cost per scrolled line** | **1.75 centiseconds** |
| implied throughput | **~18.4 MB/sec** |

Our move is currently BASIC-assembled ARM, `LDMIA`/`STMIA` with four registers
(16 bytes per iteration). **We have noticed that your `_fast_scroll` in
`armc-start.S` uses eight registers and unrolls to 64 bytes per iteration, and
we are going to match that first** — so please read the 18.4 MB/sec as our
current figure, not as a claim about what the hardware can do.

**Why it matters:** for a typical `ls -la` screenful the break-even is about 46
bytes per line. Below that, scrolling costs more than the network does:

| workload | wire | scroll | scroll share |
|---|---|---|---|
| real `ls -la`, 64 lines (1,465 bytes) | 0.56 s | **1.12 s** | **67%** |
| full 80-column screen (5,120 bytes) | 1.96 s | 1.12 s | 36% |
| a 281-line listing (19,400 bytes) | 7.42 s | 4.92 s | 40% |

The network side is already at 87% of what the Sprow Ethernet module can
deliver (2,616 bytes/sec against a 2,994 ceiling), so scrolling is the only
remaining lever of any size.

## 4. What we think we would need

Reading `screen_modes.c`, the framebuffer is allocated with virtual size equal
to physical size:

```c
RPI_PropertyAddTag(TAG_SET_PHYSICAL_SIZE, screen->width, screen->height);
RPI_PropertyAddTag(TAG_SET_VIRTUAL_SIZE,  screen->width, screen->height);
```

so there is no off-screen area to scroll into, and we could not find any call to
`TAG_SET_VIRTUAL_OFFSET`. If the virtual height were larger than the physical
height and the Y offset could be set, a text scroll becomes a register write
instead of a 322 KB memmove.

## 5. The actual questions

**(a) Is the framebuffer mapped uncached / device memory, or is it cacheable or
write-combining?** If it is uncached and could reasonably be made
write-combining, that alone might make the memmove fast enough and none of the
rest of this would be needed. This is the question we would most like answered
first.

**(b) Would a taller virtual framebuffer plus a settable Y offset be feasible?**
For MODE 21 that is 640×512 = 320 KB physical, so doubling is 640 KB against the
8 MB the memory map in `config.txt` reserves for the framebuffer. We do not know
what the equivalent looks like for the largest modes or the smallest Pis, and
whether that is the constraint that made virtual == physical in the first place.

**(c) If it is feasible, what interface would suit you?** We can call anything
reachable from ARM BASIC on Copro 15 — a SWI, a `VDU 23,...` sequence, an
`OSBYTE`. We have no preference and would rather fit your design than propose
one.

**(d) `F_HARDWARE_SCROLL_DISABLE` is defined in `screen_modes.h` but we could
not find any reference to it in the source.** Was hardware scrolling planned or
prototyped at some point? If there is a reason it was not pursued, that would
probably answer the whole question.

**(e) Would this help your own driver too?** `default_scroll_screen` calls
`_fast_scroll` for the full-screen case, so the driver's own text scrolling is
paying the same memmove. If panning were available it would presumably speed up
scrolling in every mode, not just our use case.

## 6. What we are not asking

We are not asking you to support our direct-framebuffer approach, and we are not
asking for anything urgent. If the answer is "not worth it" or "here is why that
cannot work", that is genuinely useful — it stops us building on a wrong
assumption. We are happy to test any experimental build on real hardware and
report measurements back in this level of detail.

## 7. Unrelated, but you may want to know

While chasing a different fault on the same machine we found that our interface
board carries **no bulk decoupling capacitor at all**. With a Pi 3A+ at
`force_turbo=1`, the Tube was silently losing one byte per ~874,000 — measured
as a Poisson process, uniformly distributed, always exactly one byte, invisible
to any test that does not checksum the transfer. Adding 1000 µF plus 100 nF
across 5V and GND took it to zero in 200 × 64 KB passes (p = 5.5e-4 against the
prior rate). Your reference HAT fits 22 µF, so this may be specific to our
board — but the symptom presents as random crashes and lock-ups minutes later,
which is a horrible thing to diagnose, and it may be worth a note somewhere.
