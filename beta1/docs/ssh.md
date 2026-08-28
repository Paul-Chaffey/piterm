# Adding SSH to PiTerm

**The short version:** the reason SSH was excluded — "modern SSH key
exchange on a 2MHz 6502 is not viable" (§3.5) — was true and is now
about the wrong processor. The terminal does not run on the 6502. It
runs on copro 15, a Cortex-A53 at 1.2 GHz with 200 MB of application
space, where X25519 costs under a millisecond. The crypto is free here.
What costs is the toolchain and the protocol.

And the arithmetic came out the other way round from the expectation.
SSH is not a bandwidth cost on this machine. Measured against this
project's own captures, it is **the largest bandwidth win available**,
worth more than the sideways ROM by a factor of five.

---

## Three different things hide behind "add SSH"

Worth separating before costing anything, because they have different
answers and only one of them is expensive:

| goal | what it needs |
|---|---|
| **Reach** — log in to machines that will not run telnet or the shim | a gateway, or a real client |
| **Confidentiality** — stop typing passwords onto a cleartext LAN | a gateway is enough |
| **Bandwidth** — `zlib@openssh.com` | a real client, or a shim that compresses |

The third was not a goal when §3.5 was written. It should be, because
it is worth more than either of the others.

---

## The measurement: SSH pays for its own framing four times over

`tools/sshzlib.py` models both halves exactly as OpenSSH does them —
`chacha20-poly1305@openssh.com` framing (4-byte encrypted length,
padding-length byte, 9-byte `SSH_MSG_CHANNEL_DATA` header, pad to 8 with
a minimum of 4, 16-byte Poly1305 tag) and `zlib@openssh.com`, which is
streaming deflate with a `Z_SYNC_FLUSH` at every packet boundary. Not
one-shot compression of the whole file, which would flatter it wildly:
the win has to survive being flushed every few hundred bytes.

Against `captures/`, at 1 KB packets:

| capture | bytes | SSH, no compression | SSH + zlib |
|---|---|---|---|
| `BTOPDEF` | 153,743 | 1.03x | **0.11x** |
| `BTOPTTY` | 42,617 | 1.03x | **0.13x** |
| `TOP` | 23,725 | 1.03x | **0.14x** |
| `LIVE` | 12,868 | 1.03x | **0.16x** |
| `RXH` | 38,314 | 1.03x | **0.25x** |
| `LIVE4` | 14,412 | 1.04x | **0.30x** |

The packet size is not ours to choose — it is however much the far
end's pty had buffered when sshd read from it — so the tool sweeps it.
At a pessimistic 256 bytes the same rows land between 0.24x and 0.45x.
**Even the worst case is better than three to one.**

Two consequences:

- The 34.9% of the stream that is SGR colour (`full-screen-apps.md`)
  stops being expensive. It is the most compressible thing in the
  capture — repeated byte-for-byte every frame — and deflate's 32 KB
  window spans several frames of an 80x64 screen.
- **Default `btop` comes back into range.** It measured 12,812 bytes/sec
  against a 4,268 ceiling, 3.0x over. At `BTOPDEF`'s 0.11x that is
  ~1,400 bytes/sec, a third of the ceiling, with the braille still
  unrenderable but the bandwidth no longer the reason.

For scale: §5.5b-ter costed a host-side sideways ROM at "realistically
1.3-1.8x, and it needs a 6502 assembler ROM plus a handover protocol".
This is 4-9x and needs no 6502 at all.

**The honest caveat.** These captures are full-screen redraws, which is
deflate's best case. `LIVE4` at 0.30x is the closest thing here to
ordinary interactive traffic and is the number to plan against. Nothing
in the set does worse than 0.45x at any packet size.

**And a real cost, in the other direction.** Every keystroke becomes a
36-byte packet, and the client must send `SSH_MSG_CHANNEL_WINDOW_ADJUST`
as it consumes its window. Upstream is not modelled above. At human
typing rates against a 3.28ms send call it does not matter, but it is
not free and `PROCnet_send`'s retry budget (30, deliberately) may want
revisiting.

---

## The other structural win: flow control that ncurses cannot disable

`full-screen-apps.md` rules out XOFF/XON, correctly: "ncurses puts the
pty into raw mode and clears `IXON` precisely so applications can bind
Ctrl-S, so flow control is disabled during exactly the full-screen apps
that need it."

SSH channel windows are not in the pty. They are in the protocol, below
the application, and nothing running on the target can turn them off.
Advertise an 8 KB window and the far end **blocks** rather than
buffering: the module's 76 KB packet buffer never fills, and the
18-second wait after pressing `q` — which is that buffer draining at
4.3 KB/sec — stops being possible.

That is a fix for the worst interactive defect this project has, and it
is not available any other way.

---

## The option ladder

| | work | reach | confidentiality | bandwidth |
|---|---|---|---|---|
| **0** telnet + `ssh` onward by hand (§3.5) | none | yes | no | no |
| **1** key-auth gateway — **implemented, below** | done | yes | yes | no |
| **2** compressing telnet shim | ~1 week | no change | no | yes |
| **3** SSH client on copro 15 | 4-6 weeks | yes | yes | yes |
| **4** fold 3 into the purpose-built core (§8 Step 3) | — | yes | yes | yes |

Options 2, 3 and 4 share one prerequisite: running compiled C on copro
15. That spike is the gate on all of them and it is a day's work.

---

## Option 1 — the key-auth gateway (implemented)

```sh
tools/sshgate.sh
```

Replaces §3.5's `socat ... SYSTEM:'exec /bin/bash -l'`. Same transport;
what is served is `tools/gate.sh`, a menu of destinations read from
`tools/gate.hosts`. Pick one and the **gateway** reaches it with **its
own ssh key**.

The security property is one line in `gate.sh` and must not be relaxed:

```
-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no
```

Without those, a target that refuses the key falls back to asking for a
password, the prompt appears on the Beeb, and the credential goes onto
the cleartext LAN silently — at the exact moment nobody is watching for
it. With them, a target that will not take the key fails and says so.

So: the Beeb chooses **who** to talk to. It never proves **who it is**.
Nothing it types is a credential, and §3.5's "credentials typed at the
BBC cross the LAN in the clear" stops being true.

**What the listener is, stated plainly.** Anyone who reaches it gets a
shell — here, or through the key on a machine in `gate.hosts`. There is
no authentication on the near side and there cannot be, because
authentication is the thing being kept off the wire. Two restrictions
stand in for it, both on by default:

| | |
|---|---|
| `bind=` | the address that routes to the Beeb, asked of the routing table. This machine has a tailnet address (100.x.y.z) and an unqualified listener answers on it — an unauthenticated shell reachable from the far side of the internet. §3.5 already warns about this; here it also carries a key. |
| `range=` | one source address, the Beeb's 192.0.2.20. Without it every machine on the LAN can use the gateway's key. |

`--any` removes the range restriction and prints a warning. It is a
decision, not a convenience.

**The log earns its place on one line.** A range rejection serves nothing
and says nothing to the client, so from the Beeb it is indistinguishable
from a dead listener — and the Beeb is on DHCP, so its address *will*
move one day. `results/RESGATE` tells the two apart:

```
N accepting connection from AF=2 192.0.2.20:...
W refusing connection from AF=2 <addr> due to range option
```

It is socat's log, not the session's: it records that the Beeb connected
and for how long, not which destination was picked. `gate.sh` would have
to write that itself.

Neither restriction replaces shutting it down afterwards. §3.5's
"neither form should outlive the session it was started for" applies to
this one too.

### Verified on loopback, 2026-08-27

| | |
|---|---|
| menu renders, `q` quits | yes |
| local shell entry (`-`) | `GATEOK-42` returned through the pty |
| unknown answer | menu redrawn, no crash |
| unreachable target | fails in 10s (`ConnectTimeout`), not ssh's default 2+ minutes |
| ssh's own error text | reaches the client — socat's `stderr` option carries it |
| after a failed hop | returns to the menu, so a second machine costs a keypress, not a reconnect |
| source outside `range=` | connection accepted and dropped, no menu, nothing served |
| **it records itself** | `results/RESGATE`, appended across runs, on by default |
| **a real ssh hop** | `self  user@localhost`, key-only auth, `HOP-OK on deskbox tty=/dev/pts/4` |
| pty on the target | allocated — `-tt` does what it is there for |
| **window size across both legs** | `stty size` on the target answers **64 80** |
| logout | `exit 0`, back to the menu, no reconnect |

That last row is the one worth keeping. The size set on socat's pty
propagates through ssh to the target's pty, so §3.5's `stty rows 64 cols
80` ritual is not needed on the far end of the second leg either — the
gateway carries it. PTERM's NAWS is still unanswered on the *first* leg,
because socat is not a telnet server, which is why `gate.sh` sets it.

Verified against `openssh-server` 10.2p1 on the same machine. A hop to a
different host is not materially different — the key, the two `-o`
flags and the pty all behave the same — but it has not been run.

### Before it works

Every target in `gate.hosts` must already accept this machine's public
key (`ssh-copy-id user@target`) and must already be in this machine's
`known_hosts`. Otherwise the first connection stops to ask about a host
key over the Beeb's link — not a credential, so not dangerous, but a
confusing thing to meet at 80x64. One ordinary ssh from a normal
session settles it.

---

## Option 3 — an SSH client on copro 15

### The loading mechanism exists, and is confirmed in the firmware source

`tube_CLI` in PiTubeDirect's `src/tube-swi.c` handles `*RUN <file>`: it
passes the command to the host filing system, which loads the file
across the Tube into the copro's memory, and then calls
`user_exec_raw(tube_address)`. A cross-compiled AArch32 binary with the
right load and exec addresses in its `.inf` runs natively — delivered
over LANManFS, the way everything else in this project is.

`copro-armnative.c` sets `MEMORY_LIMIT_HANDLER` and
`APPLICATION_SPACE_HANDLER` to **200 MB**. §5.5b-unvicies already
observed `HIMEM = &4000000` from the machine. Memory is not a
constraint here and will not become one.

I/O is the RISC OS-style SWI set: `OS_Word` (&07) for OSWORD &C0 — the
same control block `FNnet_recv` builds today — plus `OS_File`,
`OS_Byte`, `OS_CLI`, and `OS_EnterOS` (&16), which matters for entropy
below.

### The crypto is off the shelf

[Monocypher](https://monocypher.org/) is one public-domain `.c`/`.h`
pair, no libc, no allocation, and covers X25519, Ed25519 with SHA-512,
ChaCha20 and Poly1305 — the whole `curve25519-sha256` +
`ssh-ed25519` + `chacha20-poly1305@openssh.com` suite. The only gap is
SHA-256 for the KEX hash, about 150 lines. Roughly 2,500 lines not
written.

### The protocol is what gets written

Version exchange, binary packet protocol, KEXINIT, ECDH init and reply,
host-key verification against a `known_hosts` on the share, NEWKEYS,
service request, userauth (publickey, signing with the same Ed25519
code that verifies), channel open, `pty-req`, `shell`,
`window-change`, window adjust, and rekey. 2,000-3,000 lines. Add
streaming inflate for `zlib@openssh.com`; deflate for the upstream
direction is optional and barely worth it at typing rates.

### The seam in PTERM is four procedures wide

This is what makes it tractable. PTERM already separates transport from
terminal, and the SSH layer replaces exactly:

| | |
|---|---|
| `src/pterm.bas:584` `FNnet_recv` | returns *decrypted* bytes into `rx%` |
| `src/pterm.bas:686` `PROCnet_send` | encrypts from `tx%` |
| `src/pterm.bas:444` `PROCtelnet` / `PROCiac` | deleted |
| `src/pterm.bas:487` `PROCnaws` | becomes a `window-change` channel request |
| `src/pterm.bas:538` `PROCnet_open` | handshake and auth |

FBVDU, `FNv_uni`, the blitter, `PROCemit`, the drain loop, the
profiler, `PROCglasscheck` and the replay harness are all untouched.
The C is a transport, not a rewrite, and the BASIC edit-test loop
survives above it — the same argument §8 Step 3 made for owning the
renderer.

Note the direction the load moves: compression means **fewer wire bytes
for the same screen**, so `Socket_Recv` calls go *down* — the ~30% of
session time `full-screen-apps.md` attributes to socket reads is what
shrinks. The BASIC parse loop (1.2%) and render (3.1%) take the
extra traffic, and have four times the headroom they need.

---

## Building it: the transport, against a real server

**Decided: sans-IO.** The core does no I/O — not a socket, not a clock, not
an allocation. Bytes in through `ssh_input`, bytes out through
`ssh_output`. BASIC keeps the socket, so PTERM's pump survives intact: the
adaptive sizing, the escalating backoff, the 64-byte cap, the short-read
handling of §5.5a. None of it is rewritten in C.

The consequence that matters is not elegance. It is that the same source
compiles natively and runs against the `sshd` on the deskbox box, so
protocol bugs are found with a debugger and `sshd -ddd`, not on a Beeb
through a Tube with a monitor for output. `tools/sshbuild.sh` builds for
**both** targets on every run, with `-Werror`, so libc creep is a build
failure the day it is written rather than a surprise weeks later.

**First milestone reached 2026-08-28** — version exchange, binary packet
framing and algorithm negotiation, against OpenSSH 10.2p1:

```
client  SSH-2.0-PiTerm_0.1
server  SSH-2.0-OpenSSH_10.2p1 Ubuntu-2ubuntu3.5

  kex            curve25519-sha256
  host key       ssh-ed25519
  cipher c->s    chacha20-poly1305@openssh.com
  compress s->c  zlib@openssh.com
  strict kex     yes - Terrapin mitigation in force
```

4,194 bytes of ARM text. Three things came out of that run that were
assumptions before it:

**1. `zlib@openssh.com` needs no server configuration.** Stock sshd offers
`none,zlib@openssh.com` out of the box, and since negotiation takes the
*client's* first preference, listing zlib first wins it. The 4-9x in this
document rested on compression being available; it is, with nothing to
enable.

**2. Strict KEX is not optional for this client.** The server advertises
`kex-strict-s-v00@openssh.com`, OpenSSH's Terrapin mitigation
(CVE-2023-48795) — and Terrapin is a prefix-truncation attack against
precisely the cipher chosen here, `chacha20-poly1305@openssh.com` being the
worst affected. The client half is now advertised, which takes on two
obligations that land with NEWKEYS: reset both sequence numbers to zero at
every NEWKEYS, and treat IGNORE, DEBUG and UNIMPLEMENTED during the initial
KEX as fatal. `s->strict_kex` records the debt.

**3. The post-quantum caveat, seen live.** The server's *first* preference
is `mlkem768x25519-sha256`; we negotiate down to `curve25519-sha256`. That
works and is what the warning at the end of this document describes.

**Second milestone, same day: the full key exchange.** Against the same
server, `PASS - encrypted, service accepted`:

```
kex            curve25519-sha256      strict kex  yes
host key       ssh-ed25519            SHA256:<example>
cipher         chacha20-poly1305@openssh.com (both directions)
compress       zlib@openssh.com (both directions)
```

Reaching `SERVICE_ACCEPT` is what makes that a real result rather than a
hopeful one. It is the first message the client **sends encrypted** and the
first it **receives encrypted**, so it can only arrive if X25519, the
exchange hash, the Ed25519 verification, the key derivation, the
chacha20-poly1305 construction and the strict-KEX sequence reset are *all*
right. Any one of them wrong and the server hangs up.

The fingerprint above was checked against `ssh-keygen -lf` on the server's
own key file and matches byte for byte, which independently confirms the host
key blob is parsed and hashed the way every other SSH tool does it.

| | |
|---|---|
| crypto | Monocypher 4.0.2, vendored — X25519, Ed25519, ChaCha20, Poly1305 |
| SHA-256 | written here, ~150 lines; Monocypher has SHA-512 but not this |
| primitives tested | NIST vectors including the million-`a` case, on every build |
| size | 72 KB of ARM text before `--gc-sections`, Monocypher dominating |

**What the core does not decide.** It verifies the host key *signature*,
which proves the server holds the private half of the key it presented. It
does not judge whether that is the key you meant to reach — that is
`known_hosts`, and it belongs to the caller, so the blob and its fingerprint
are exposed rather than ruled on.

Three details that would each have cost a day, recorded because none is
obvious from the RFCs alone:

- **The AEAD padding rule is different.** With chacha20-poly1305 the 4-byte
  length is encrypted separately and is *not* part of the padded block, so
  the multiple of 8 covers `padding_length + payload + padding` alone.
  Using the plaintext rule produces packets the server rejects.
- **`mpint` is signed.** The shared secret is stripped of leading zero bytes
  and gains one when the top bit is set. Get it wrong and the exchange hash
  differs from the server's — and the only symptom is "bad signature", which
  sends you hunting in the signature code.
- **An all-zero X25519 result must be refused.** It means a low-order point
  was supplied and the exchange has no secrecy. Monocypher does not refuse
  it for you in this API.

**Third milestone: a shell.** Public-key authentication, a session channel,
`pty-req` at 80x64, `shell`, and a command run with its output read back —
`PASS - a shell ran a command and the answer came back`, twelve runs out of
twelve.

`ssh_write` and `ssh_read` are the seam PTERM will use, and the pump in
`tools/sshtry.c` is deliberately the shape PTERM's will be: drain what the
core wants sent, feed it what arrived.

**The window is 8 KB on purpose.** This is the flow control
`full-screen-apps.md` wanted and could not have — it lives below the
application, so nothing on the target can switch it off the way ncurses
switches off `IXON`. A small window makes the server *block* rather than
fill the module's 76 KB buffer, so the 18-second wait after `q` cannot
form. Refills are lazy, one adjust per 4 KB rather than one per packet,
because every adjust is a 3.28 ms send on the Beeb.

**Compression is asked for in one direction only**, and that is a design
decision rather than a shortcut. The directions negotiate separately, and
every byte that matters here is server-to-client. Downstream-only means the
client needs **inflate and never deflate** — half the code, and the simpler
half. Keystrokes go uncompressed and lose nothing.

### Two bugs worth keeping

**The intermittent one, and how it was found.** After the channel worked, the
handshake began failing about half the time with "host key signature does not
verify". Half is not a hint, it is a measurement: ten runs gave six failures
and four passes, and a probability of one half points at a condition that is
true for half of all inputs. **An `mpint` gains a leading zero byte when its
top bit is set** — true for half of all shared secrets — and the buffer was
`kmp[36]` where the worst case needs 37. The extra byte landed in `kmp_len`,
which the very next statement overwrote, so the exchange hash used a byte of
its own length field instead of the last byte of K. Twelve for twelve after
widening it.

Chasing that by reading the signature code would have failed, because the
signature code was right. The rate was the evidence.

**The one the server diagnosed.** Authentication was refused with no reason
given, and the client could only report that the connection closed. `sshd`'s
log said `userauth_pubkey: parse signature packet: unexpected bytes remain
after decoding` — the signature field is a **string containing** the
signature blob, not the blob appended. One `put_string` call. Worth
remembering that the far end's log is part of the debugger here, and is the
thing the Beeb will not have.

### Fourth milestone: compression, and the simulation was right

`zlib@openssh.com` works, server-to-client. **The 4-9x is no longer a
simulation** — these are wire bytes counted by `sshtry` against the real
server, on the same workload run twice:

| workload | screen bytes | wire, plain | wire, zlib | | Tube time |
|---|---|---|---|---|---|
| `ls -la /usr/bin` | 223,208 | 229,726 (1.029x) | **40,934 (0.183x)** | **5.6x** | 54s → 9.6s |
| ten full redraws | 49,763 | 53,518 (1.075x) | **5,990 (0.120x)** | **8.9x** | 12.5s → 1.4s |

The uncompressed column is worth as much as the compressed one:
`tools/sshzlib.py` predicted 1.03x for SSH framing and the wire says 1.029x.
The model in that tool was right, so the numbers it produced for the
`captures/` files stand.

The redraw case is the one that matters for a terminal, and 8.9x is at the
top of the predicted range — repeated screens are what deflate's 32 KB
window is for, and it spans several of them.

Implementation: miniz's `tinfl` vendored rather than a hand-written inflate.
Inflate is a well-known source of subtle bugs and a wrong one does not fail
loudly — it delivers plausible rubbish to a terminal. The dictionary is
written circularly, which is tinfl's native mode.

### The bug that only appeared at -O2

The native build began segfaulting the moment `nolibc.c` joined it —
`memcpy`, `memset`, `memmove` and `memcmp`, which a freestanding ARM link
needs because gcc emits calls to them whether or not the source names them.

At `-O2`, gcc recognised the loop inside my own `memcpy` and compiled it
into a call to `memcpy`. Itself. Infinite recursion, stack overflow,
SIGSEGV a long way from the cause — and invisible under `-O0`, which is why
it passed under the sanitiser and under gdb and failed only when run
plainly. That divergence was the clue.

Two fixes, both needed: `nolibc.c` is ARM-only, since glibc already has
these, and the ARM build carries `-fno-builtin` to stop the same thing
happening there.

**`tools/sshbuild.sh` now links the ARM objects**, not just compiles them.
Compiling proves each file parses; linking with `-nostdlib` proves nothing
reaches for a libc that is not there. It immediately earned its place by
finding `__aeabi_uidiv` and `__aeabi_uldivmod` — Monocypher divides, and ARM
without hardware divide gets those from libgcc, which ships with the
toolchain and is not a hosted dependency. An undefined symbol caught here is
a build failure on Linux; caught later it is a blob that loads onto the Beeb
and branches into nowhere.

### Fifth: the BASIC seam, built and waiting on the machine

`build/SSHBLOB` — **48,812 bytes**, entry at `&4100000`, the whole client
after `--gc-sections`. `test/sshbeeb.bas` drives it. Both are on the share,
along with `SSHKEY`.

**The ABI is deliberately the dullest available.** `A%` is an opcode, `USR`
returns `r0`, arguments live in a parameter block at `&4108000`. That is
possible only because `ARMSPIKE` proved on hardware that `A%` arrives in
`r0` under both `CALL` and `USR` — a convention nobody had tested before
that run.

| | |
|---|---|
| `&4100000` | the blob |
| `&4108000` | the parameter block, 16 words |
| `&4110000` | `struct ssh`, ~110 KB — **not** in `.bss`, so nothing depends on BSS arriving zeroed |

`*LOAD` writes only what is in the file, so whatever the compiler did put in
`.bss` arrives holding the last program's leavings. `beeb.ld` exports
`__bss_start__`/`__bss_end__` and `OP_INIT` clears it — a fault that would
otherwise reproduce only sometimes and look like anything but its cause.

**The blob seeds itself.** `OP_INIT` reads the SoC RNG directly rather than
accepting entropy from BASIC, because the only source BASIC could offer is
`RND`. Making a bad seed impossible is worth more than an option to supply a
good one.

**BASIC keeps the socket**, and `sshbeeb.bas` carries the hard-won rules
with it: reads capped at 64 bytes because above that the module refuses *and
consumes what it refuses*, sends bounded to 30 retries, and the blob's byte
sum checked before it is ever called — 48 KB across the Tube is exactly
where §5.5g's one-byte-in-874,000 would show, and a blob one byte short is
not a program.

**The key is its own.** `tools/sshkey.sh` generates `~/.ssh/piterm_ed25519`
rather than reusing an existing key, and writes the share form as 64 raw
bytes — 32 public, 32 seed. The private half has to sit on a Samba share a
40-year-old machine mounts, so it should be a key that can be revoked on its
own and that opens only what you choose. Parsing OpenSSH's base64 container
in BBC BASIC would be a page of code to no purpose.

```
CTRL-BREAK, *ARMBASIC, *MOUNT, *DIR Pi-TERM, CHAIN "SSHBEEB"
```

It runs one command and reads the answer, which is the smallest thing that
exercises every layer. It logs to `RESSSH` and reports wire bytes against
screen bytes, so the compression ratio gets measured on the real link rather
than on loopback.

### On hardware, 2026-08-28: the handshake works on the Beeb

`RESSSH`, second attempt:

```
blob sum 5797686 want 5797686
init ok, seeded from the SoC RNG
connected
state 1 kexinit    at  1cs
state 2 kex reply  at 41cs
state 3 newkeys    at 55cs
state 4 service    at 66cs
state 5 auth       at 77cs
```

**Everything up to authentication works on the real machine.** X25519, the
exchange hash, Ed25519 host key verification and chacha20-poly1305 in both
directions — reaching `service` means `SERVICE_ACCEPT` arrived *encrypted*
and was decrypted correctly. The whole exchange takes **0.89 seconds**, of
which the key exchange itself is 0.4.

48 KB of blob crossed the Tube with its byte sum intact, and the SoC RNG
seeded the session, so both spikes paid off in the same run.

### Two bugs on the way there, both mine, both instructive

**The lockup: the parameter block was inside the blob.** The first run
reached `connected` and wedged with no state line at all. `&4108000` is
32,768 bytes into a 48,812-byte blob, so BASIC was writing its arguments
into the blob's own code; the session survived until execution reached a
corrupted instruction. The addresses came from `ARMSPIKE`, where the blob
was 131 bytes, and were carried to one 370 times larger without being
re-checked. `PARAM` and `SESSION` now sit a megabyte clear at `&4200000`
and `&4210000`, and **`sshbuild.sh` fails the build if the blob ever reaches
them** — a fixed memory map shared between C and BASIC needs a machine
checking it, not a comment.

**The refusal: BBC BASIC's `$` terminates with CR, not NUL.** `$nm%="user"`
stores `p a u l &0D`, so C's `strlen` ran past the name. sshd said so
exactly:

```
Invalid user user\rUTQE\027UU\025]U]\250\301 from 192.0.2.20
```

The whole key exchange had succeeded and authentication failed for a user
name with a carriage return on the end. Fixed in both places: the BASIC
writes an explicit NUL, and `OP_AUTH` honours either terminator so a caller
using BASIC's native string form cannot get it wrong.

That log line is also the argument for having a server you control on the
same LAN. From the Beeb the failure was "the server refused our key" and
nothing more.

### PASS: the Beeb ran a command over SSH, 2026-08-28

`results/RESSSH_0828a`, twice:

```
state 1 kexinit    at   1cs
state 2 kex reply  at  31cs
state 3 newkeys    at  44cs
state 4 service    at  55cs
state 5 auth       at  66cs
state 6 channel    at  80cs
state 7 pty        at 113cs
state 8 shell      at 123cs
state 9 OPEN       at 135cs
PASS
```

**1.35 seconds from connect to a running shell**, and `SSHOK-42` came back
through the Sprow module and onto the Pi's framebuffer. Every layer on real
hardware: curve25519 key exchange, Ed25519 host key, publickey
authentication, the session channel, a pty at 80x64, and
chacha20-poly1305 in both directions.

**One number in that run is not a result.** It reported `wire 3198 app 1133`
— apparently 2.8x *more* traffic with compression on. That is the handshake,
not the compression: ~1,400 bytes of KEXINIT, host key and signature is a
fixed cost, and against a one-line `echo` it swamps everything. The
accounting now counts separately from the moment the shell opens, and the
workload is `ls -la /usr/bin` so there is something to compress. Set
`comp%=0` and run again for the A/B — uncompressed that listing is about 54
seconds of Sprow module.

### The number this project has been chasing since full-screen-apps.md

`results/RESSSH_0828d_zlib_redraws`, ten screen redraws, twice, identical:

```
session wire 3,140   screen 40,978   ratio 0.076   1.62s
total wire   5,406   (Linux said 5,382 - 0.4% apart)
```

**13.1x fewer bytes**, and in terms of what reaches the glass:

| | |
|---|---|
| screen data delivered | **25,295 bytes/sec** |
| module ceiling | 4,268 bytes/sec |
| | **5.9x the ceiling** |

`full-screen-apps.md` ends with: *"A full-screen app at 80x64 needs about
25 KB/sec to feel live. The module provides 4.3."* That figure was written
as the thing this machine could not have. It is now what it does — 25,295
against an estimate of 25,000, which is closer than the estimate deserves,
but the order of magnitude is the point.

The wire moved 1,938 bytes/sec, still under the module's 4,268, so **the
Sprow module is no longer the constraint** — for the first time in this
project, the limit is on our side of the Tube.

The Beeb and the Linux harness agreed to 0.4% on total wire bytes, which
says the core behaves identically over the module and over loopback.

### The A/B, on the machine, 2026-08-28

`results/RESSSH_0828e_plain_redraws` completes it. Same Beeb, same workload,
`comp%` the only difference:

| | uncompressed | zlib s→c | |
|---|---|---|---|
| wire bytes | 41,780 | 3,140 | **13.3x** |
| seconds | 19.59 | 1.62 | **12.1x** |
| screen bytes/sec | 2,092 | **25,295** | **12.1x** |
| ratio | 1.019 | 0.077 | |

Linux predicted 44,178 total wire bytes for the uncompressed leg; the Beeb
did it in 44,070 — **0.24% apart**. Both legs now agree with loopback to
better than half a percent, which retires any doubt that the module changes
how the core behaves.

**Where the time goes, from the progress log.** The uncompressed leg reports
every five seconds, and the rate is not steady:

```
 0.0- 5.0s   2,004 B/s
 5.0-10.2s   4,008 B/s      <- essentially the module's 4,268 ceiling
10.2-15.3s   1,032 B/s
15.3-20.5s   1,250 B/s
```

So the module **is** saturated in bursts and idle between them, exactly as
§5.5b-bis found: "delivery is bursty, not decaying". The 2,133 B/s average is
not a rate limit, it is a duty cycle. That matters for what to fix next —
there is no steady 2 KB/s wall to lift, there are gaps to fill.

Compression multiplies whatever the link delivers, which is why the screen
rate goes up by the same 12.1x that the byte count goes down.

Wiring it into PTERM proper is the four procedures listed above.

---

## Three unknowns, each a short spike

**1. A cross-compiled binary runs from BASIC. ANSWERED — PASSED ON
HARDWARE 2026-08-27.** `src/spike1.c`, `tools/armbuild.sh`,
`test/armspike.bas`; the log is `results/RESSPIKE_0827b`.

```
memory writable
byte sum 12624 want 12624
USR  stage 5 magic &5B1CE001 r0 &12345678 A% &12345678 in 7  out 15 want 15
CALL stage 5 magic &5B1CE001 r0 &BADCAFE  A% &BADCAFE  in 20 out 41 want 41
PASS
```

Every stage of it, first time. `&4100000` is real writable memory, so
the inference from `copro-armnative.c`'s 200 MB was right. The blob
crossed LANManFS and the Tube with its byte sum intact. It reached
stage 5, meaning all three SWIs worked and the epilogue returned. The
magic proves it was our code and not something already at that address.
`.rodata` resolved, so link address and load address agree.

**And the register question is settled on this machine: `A%` arrives in
`r0`, under both `CALL` and `USR`, and `USR` returns `r0`.** Both arms
ran with different values so neither answer could be a leftover from the
other. That is worth more than the spike itself — it is the calling
convention any future C on this core will use.

**One cosmetic anomaly.** `RESSPIKE` begins `FF 0D`, so `EXT#` was
already 1 when the first line was appended: LANManFS's `OPENOUT` leaves
a byte in a newly created file. Harmless, but a parser reading these
logs must skip it, and it is worth knowing before someone blames their
own code.

The host half had been verified before the run: 131 bytes, `_start` at
offset 0, A32 throughout, `svc 0x00`/`0x02`/`0x03` where `OS_WriteC`,
`OS_Write0` and `OS_NewLine` go, `.rodata` at the link address.

Two things it does NOT do, both settled by reading the repo rather than
guessing:

- **No `*RUN`, and no `.inf`.** `tools/ssd-extract.py` records that
  LANManFS ignores `.inf` files, so the share cannot carry a load or
  exec address; and `gamesmenu.sh` records the cost of writing one
  anyway — the name goes over eight characters, LANManFS truncates, and
  it arrives as a junk second file. `armspike.bas` uses `*LOAD` with an
  explicit address instead.
- **No `mirror.sh` for the blob.** It does `tr '\n' '\r'` on everything
  it writes, which would silently corrupt a binary. `armbuild.sh` copies
  it in and byte-compares, the way `mktubedata.py` generates TUBEDATA.

It links and loads at `&4100000`, 1 MB above `HIMEM` and inside the
200 MB the core grants. That address being real is an inference from
`copro-armnative.c`, not a measurement, so the BASIC writes and reads it
back before trusting it and stops with a message if it cannot.

It is the gate on options 2, 3 and 4, and on the purpose-built core in
§8 Step 3, so it is worth running whatever is decided about SSH.

**2. Entropy. ANSWERED — PASSED ON HARDWARE 2026-08-28.** The SoC's
hardware RNG is reachable, and this was the step with no fallback if it
failed. `src/rng.c`, `test/rngspike.bas`, log `results/RESRAND_0828b`.

```
stage 6 magic &5B1CE002 STATUS &40FFFFF CTRL &1 spins 301 count 8
words &E725BC9F &8EF4AAE7 &3F88FA3D &686751F1 &20BEE07 &8F419DA1 ...
```

| | |
|---|---|
| reachable **from user mode** | no data abort, no `OS_EnterOS`, no SVC mode needed |
| `CTRL &1` | already enabled by firmware, so the warm-up is skipped |
| `STATUS &040FFFFF` | top byte `04` — four words already in the FIFO on arrival |
| 32 bytes of seed | ~301 status polls, i.e. microseconds |

Two runs, 16 words, all 16 distinct, no zeros, no overlap between runs,
bit balance 0.508 over 512 bits. **That is a smoke test, not a
statistical endorsement** — 512 bits is far too small to say anything
about quality. What it does rule out is the failure that would have
looked like success: a disabled or unclocked block returning constants.

**Design consequence.** The seed is cheap enough to take directly, but
the client will still take 32 bytes once and expand them through a
ChaCha20 CSPRNG — the conventional arrangement, and the one that lets
the Linux-side harness seed deterministically and get reproducible
handshakes.

**A bug worth keeping, because it is the shape of this whole class.**
The first version broke out of the collection loop the moment `STATUS`
reported zero words, and stopped at five words on every run. The FIFO
held four on arrival and reading drains it faster than the block
refills; momentarily empty is the normal state of a generator being
read faster than it generates. Deterministic five was the signature of
a drain rate, not of broken silicon — and the test reported `FAIL` for
something that was working.

**3. `Socket_Recv` semantics become correctness-critical.** PTERM's own
notes record that a read above ~64 bytes can be *refused after
consuming the bytes*, and that 111 bytes went missing mid-stream once
and printed an escape sequence as text. Under telnet that is a glitch on
the glass. Under SSH it is a Poly1305 failure and a dead session, every
time. The existing rules — never ask for more than 64, always accept
short reads (§5.5a) — stop being performance tuning and become the
protocol's correctness condition.

The same goes for the Tube itself. The one-byte-in-874,000 loss traced
to the missing bulk capacitor (§5.5g, §5.5i) would have made SSH simply
not work. Worth knowing in both directions: it is a hazard, and it is
also the most sensitive regression detector this project could have for
that class of fault.

---

## What it costs

4-6 weeks of evenings for option 3. ~5,000-7,000 lines, of which ~2,500
is imported crypto. One week for option 2, which shares the same first
spike and delivers the bandwidth win alone.

**There is no prior art.** No SSH client has been written for a BBC
Micro. The RISC OS ones do not port: NettleSSH is SSHv1 and unmaintained,
and the PuTTY port needs GTK. This would be the first.

---

## Recommendation

1. **Option 1 is done and proved end to end**, including the ssh hop.
   What remains is to point it at the machines you actually want, and to
   run it once from the Beeb rather than from loopback.
2. ~~**Run spike 1.**~~ **Done, passed 2026-08-27.** Compiled C runs on
   copro 15 and the calling convention is known. Options 2, 3 and 4 are
   unblocked, and so is §8 Step 3's purpose-built core.
3. **Then decide by goal — this is now the open question.** For a faster
   terminal, option 2 gets the whole 4-9x for a week. For reaching
   machines that only speak SSH, option 3 is the only answer, and it now
   brings the bandwidth win and real flow control with it rather than
   costing anything.
4. **Do not do option 3 twice.** If §8 Step 3's purpose-built core is
   still the plan, SSH belongs inside it: C is that core's native
   language, and the toolchain question disappears rather than being
   answered twice.

One thing to record for later: OpenSSH 10.1 warns when the key exchange
is not post-quantum. It is client-side and advisory, servers still
accept `curve25519-sha256`, and no removal is scheduled — but a client
written here would be classical-only, and `mlkem768x25519` is the thing
it would eventually want. ML-KEM-768 is about 2,400 bytes of public key
across the wire and a few hundred lines more; not a problem at 1.2 GHz,
but not free either.

---

## Sources

- [PiTubeDirect](https://github.com/hoglet67/PiTubeDirect) —
  [`copro-armnative.c`](https://github.com/hoglet67/PiTubeDirect/blob/master/src/copro-armnative.c),
  [`tube-swi.c`](https://github.com/hoglet67/PiTubeDirect/blob/master/src/tube-swi.c)
- [Sprow ARM co-processor](http://www.sprow.co.uk/bbc/armcopro.htm) —
  the SWI environment PiTubeDirect's native ARM mode follows
- [Monocypher](https://monocypher.org/)
- [wolfSSH](https://github.com/wolfSSL/wolfssh) — 33 KB footprint,
  the commercial comparison
- [tinyssh](https://tinyssh.org/) and
  [zssh](https://github.com/TomCrypto/zssh) — minimal implementations
  of the same cipher suite
- [OpenSSH post-quantum](https://www.openssh.org/pq.html)
- [Nettle for RISC OS](https://github.com/dpt/Nettle) and
  [RISC OS SSH](https://www.riscos.info/index.php/SSH) — the prior art
  that does not port

## Host keys, 2026-08-28

`docs/ssh.md` closed its open-items list with *"host keys checked by eye"*.
They are checked by the terminal now.

**What the core always did, and what it never did.** `handle_ecdh_reply`
verifies the host key's signature, which proves the server holds the private
half of the key it presented. It says nothing about that being the right
host — any impostor's own key satisfies the same test. The comment in
`ssh.c` said so and left the decision to the caller, exposing `hostkey` and
`hostkey_fp` for exactly that purpose. Nothing consumed them.

**`SSH_ST_NEEDHOST`, built like `SSH_ST_NEEDPASS`.** The core stops after the
key exchange and will not send another byte until `ssh_accept_host` is called,
for the same reason it stops for a password: only the caller can answer.
Sans-IO makes the pause free — the core advances only when it is fed.

One thing did have to change. The server's `NEWKEYS` has usually arrived in
the same read as the key exchange reply and is sitting in `s->in` while the
caller decides, and nothing else would ever come to wake it. So the drain loop
was split out of `ssh_input`, and `ssh_accept_host` resumes it.

**The fingerprint is `ssh-keygen`'s, exactly.** `SHA256:` and 43 characters of
unpadded base64. Comparing what a person reads off two screens is the whole
mechanism, so the format has to be the one the other screen uses. Checked
against `ssh-keygen -lf` on two servers, character for character:

```
ours       SHA256:<example>
ssh-keygen SHA256:<example>
```

**`KNOWNHST` on the share**, `/etc/hosts` shaped and CR-terminated like
`HOSTS` beside it, appended rather than rewritten so a power cut cannot lose
the other hosts. Keyed on **the address**, not on what was typed —
`PROCname` replaces `host$` with the dotted quad it resolved to before the
handshake starts, so `archbox` and `192.0.2.30` are one entry rather than two.
`ssh` keys on both and warns when they disagree; this side cannot, because by
that point the name is gone. The cost is that a machine which changes address
looks like a new host, and one that inherits an address looks like a changed
key.

**Confirmed on the hardware, 2026-08-28**, `results/KNOWNHST_0828_first` — the
file the Beeb wrote for itself on its first connect, CR-terminated, and its
fingerprint equal to what `ssh-keygen -lf` says archbox's key really is:

```
192.0.2.30 SHA256:<example>
```

The connect after it did not prompt, which is the other half of it working.

**The whole loop, 19:24 the same evening**, `results/RESGLAS_0828_keyauth`:
archbox's sshd logged `Accepted publickey ... SHA256:gdNPFXoN...`, which is the
Beeb's own key, so no password was asked for; `KNOWNHST` was not rewritten, so
the host key matched and nothing prompted; and the session moved 166,141 bytes
over 25,652 cells with `stale_cells=0` and `short=0`. Silent on both counts is
what correct looks like here - the evidence for it is in the far end's journal
and in a file that did not change.

A changed key gets no prompt and no way to continue. It is either a rebuilt
machine or someone in the middle, this side cannot tell which, and the session
stops before a keystroke is sent.

**What it is worth.** Installing the Beeb's key on `archbox` the same day reduced
the exposure by itself — a public key is not a secret, so a fake server learns
nothing from a key attempt. The password was the thing worth stealing, and
that is what a first-connect prompt now stands in front of.

**The state numbers are asserted at build time.** `ssh.h` warned in a comment
that renumbering the enum "would silently change what test/sshbeeb.bas and
PTERM are testing". `tools/sshbuild.sh` now compiles the enum and greps
`src/pterm.bas` for each number it hardcodes, so that comment is a build
failure instead of a hope. It matters more than it looks: `A%=12` is a
fingerprint request and `st%=12` is a password prompt — one keystroke apart in
the source, unrelated in meaning.
