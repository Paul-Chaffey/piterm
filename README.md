# PiTerm

A VT102 terminal for a **BBC Master 128 from 1986**, rendered by BBC BASIC on a
Raspberry Pi co-processor, with an SSH client written from scratch in C.

It logs into modern machines over SSH, at 80x64, in colour.

```
CTRL-BREAK
*ARMBASIC
*MOUNT \\deskbox\BEEBOS       ... or *ADFS, if you would rather not
*DIR Pi-TERM
CHAIN "SSH"
```

It loads over a Samba share or off an ADFS volume, unchanged either way:
nothing in the terminal knows which filing system it came from. See
`beta1/docs/getting-started.md`.

## What is interesting about it

**The bandwidth ceiling turned out to be an encoding problem, not a hardware
one.** The Sprow network module hands over about 56 bytes per 1.31 cs read and
offers no `select()` and no timeout, which caps the link at **4,268 bytes/sec**
measured. An earlier document concluded that a full-screen application at 80x64
needs roughly 25 KB/sec to feel alive and that this machine therefore could not
run one.

Turning on `zlib@openssh.com` — server-to-client only, so the client needs
inflate and never deflate — moved **25,295 bytes/sec** onto the screen through
the same module. A controlled A/B over ten identical screen redraws:

| | uncompressed | compressed | factor |
|---|---|---|---|
| wire bytes | 41,780 | 3,140 | **13.3x** |
| seconds | 19.59 | 1.62 | **12.1x** |

Real sessions do better still — 58,000 to 67,000 bytes/sec to the glass, at
compression floors of 19x to 26x — because terminal output is extremely
redundant. `btop`, previously unusable on two independent counts, now runs and
quits instantly.

A Linux model predicted 44,178 wire bytes for one of these runs. The Beeb
produced 44,070: **0.24% apart**.

**The font is 1,353 glyphs, and almost none of them were drawn.** Braille, the
block elements, sextants and octants are computed — the shape *is* the
codepoint. Double box-drawing comes from one measured rule. Accented Latin-1 is
composed at boot from the machine's own harvested font, so an accented letter
matches the unaccented one beside it. The legacy diagonals are derived from
Unicode's own character *names*, because no font on the build machine had them.
The result covers **every non-ASCII character in all 539 builtin `fastfetch`
logos** — 14,041 of 14,041.

**The SSH client is sans-IO.** `beta1/src/ssh/ssh.c` performs no I/O
whatsoever: BASIC owns the socket and feeds it bytes. The same source compiles
natively — where it is tested against real `sshd` — and cross-compiles for ARM.
curve25519-sha256, ssh-ed25519, chacha20-poly1305, `kex-strict-c-v00` for
Terrapin (CVE-2023-48795), publickey and password auth, and host keys checked
against a `KNOWNHST` file with fingerprints in `ssh-keygen`'s exact format.

## Layout

| | |
|---|---|
| `beta1/src/fbvdu.bas` | the display engine — owns the framebuffer, blits its own font |
| `beta1/src/pterm.bas` | the terminal — VT parsing, telnet and SSH |
| `beta1/src/ssh/` | the sans-IO SSH client |
| `beta1/docs/` | the design documents |
| `beta1/specification.md` | the measurement record, ~4,000 lines |
| `beta1/test/` | 69 probe programs, one hardware question each |
| `beta1/tools/` | build, lint, mirror, glyph generation, analysis |
| `beta1/results/` | what the hardware actually reported |

## Building

```sh
beta1/tools/sshbuild.sh          # the SSH blob, native and ARM, with its checks
beta1/tools/fbbuild.sh src/pterm.bas > PTERMRUN.bas
beta1/tools/sshterm.sh           # the quiet build, no instrumentation
beta1/tools/baslint.py src/*.bas # the BASIC linter
```

`beta1/tools/setup-samba.sh` sets up the share the Beeb mounts. **Read its
warning first** — it deliberately re-enables SMB1, NTLMv1 and LANMAN because
the 2009 network module speaks nothing else. That is a real weakening of the
host it runs on. Trusted LAN only, and undo it when finished.

## What is not here

No Acorn manuals, schematics, disc images or commercial software: none of it is
ours to publish. Where the documentation depends on one — Sprow's
`netprogapi.pdf` above all — it is cited by name. See `NOTICE`.

The addresses and hostnames throughout are from RFC 5737's documentation range
and are not real machines.

## Licence

MIT, see `LICENSE`. Vendored Monocypher and miniz keep their own terms, and the
glyph provenance is set out in `NOTICE`.
