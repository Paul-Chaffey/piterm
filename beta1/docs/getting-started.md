# Getting started

Build once, then choose how the files reach the Beeb: over a **Samba share**,
or on an **ADFS volume**. The built files are identical either way — nothing in
the terminal knows or cares which filing system it is loaded from.

## 1. Build

```sh
tools/sshbuild.sh                       # the SSH blob, both targets, with its checks
tools/mirror.sh --dir Pi-TERM src/fbvdu.bas src/pterm.bas test/fbvt.bas
tools/fbbuild.sh src/pterm.bas > build/PTERMRUN.bas
tools/fbbuild.sh test/fbvt.bas   > build/FBRUN.bas
tools/mirror.sh --dir Pi-TERM --tok build/PTERMRUN.bas build/FBRUN.bas
tools/sshterm.sh                        # the quiet build, CHAIN "SSH"
tools/sshkey.sh                         # the Beeb's own SSH key
cp tools/HOSTS.example share/Pi-TERM/HOSTS
python3 -c "p='share/Pi-TERM/HOSTS';d=open(p,'rb').read();open(p,'wb').write(d.replace(b'\n',b'\r'))"
```

That leaves eight files in `share/Pi-TERM/`:

| | |
|---|---|
| `SSH` | the terminal, tokenised — `CHAIN` it |
| `PTERMRUN` | the same, with the instruments on |
| `FBVDU` `PTERM` `FBVT` | the sources, for `*EXEC` instead of `CHAIN` |
| `FBRUN` | the display engine's own test driver |
| `SSHBLOB` | the SSH core, an ARM binary |
| `HOSTS` | names to addresses |

`tools/sshkey.sh` also writes `SSHKEY` there, and prints a public key line for
`authorized_keys` on whatever you want to reach. Keep the `restrict,pty`
prefix: it allows an interactive shell and nothing else — no forwarding, no
agent, no tunnelling. It makes a key **separate from your everyday one**,
because its private half has to live wherever the Beeb can read it.

**`HOSTS` starts out full of RFC 5737 documentation addresses that reach
nothing.** Edit it before the Beeb tries to use it.

---

## 2a. Over a Samba share

The Beeb mounts a directory on your machine. Nothing is copied; rebuild and
the Beeb sees the new files immediately.

```sh
sudo bash tools/setup-samba.sh          # read its warning first
tools/mirrorck.sh                       # is the share current with src/?
```

**`setup-samba.sh` deliberately re-enables SMB1, NTLMv1 and LANMAN**, because
the 2009-era Sprow module speaks nothing newer. That is a real weakening of the
machine it runs on. Trusted LAN only; the file ends with how to undo it.

It also **truncates and rewrites** `/etc/samba/smb.conf` rather than appending,
so anything you add by hand is lost on the next run. Add stanzas inside its
heredoc.

Then on the Beeb:

```
CTRL-BREAK
*ARMBASIC
*MOUNT \\deskbox\BEEBOS
*DIR Pi-TERM
CHAIN "SSH"
```

**Mount after the BREAK, never before.** CTRL-BREAK is a hard reset: it clears
sideways ROM private workspace, and LANManFS loses the mount with it. `*MOUNT`
works from the co-processor because it is a `*` command and the host's ROM runs
it. A *soft* BREAK keeps the mount but loses the current directory, which is
what `*KEY 10 *DIR Pi-TERM|MCHAIN"SSH"|M` is for.

---

## 2b. On an ADFS volume

Use this if the machine has ADFS storage — a hard disc, a CF or MMC card, a
floppy or a floppy emulator — and you would rather not put it on a network, or
have no network at all.

**Nothing needs rebuilding.** Copy the same eight files. The terminal opens
them by name with `OPENIN`, `OPENUP` and `OSCLI "LOAD"`, always supplying the
load address itself, so it carries no dependency on the filing system: no path
separators, no catalogue load/exec addresses, nothing LANManFS-specific.

**The names already suit ADFS.** `tools/mirror.sh` produces uppercase names of
eight characters or fewer, and ADFS allows ten. It has already converted the
line endings to CR, which matters as much here as on the share.

Two ADFS rules to respect if you rename anything:

- **A dot is the directory separator**, so it cannot appear in a filename.
- Avoid `: * # $ & @ ^ %` and spaces. Letters, digits and `-` are safe.

Put them in a directory so `*DIR` reaches them, exactly as on the share:

```
*ADFS
*DIR PiTerm
CHAIN "SSH"
```

`*ARMBASIC` first if you are not already on the co-processor. There is no
`*MOUNT` and no BREAK ordering to observe — that whole hazard belongs to
LANManFS, and this is the main practical reason to prefer ADFS.

### Getting the files onto the volume

Whichever route your hardware supports:

- **Copy them on the machine itself**, if you already have the share working:
  mount it, then `*COPY` or a `LOAD`/`SAVE` pair per file across to ADFS. The
  simplest route if you are moving *from* the share *to* a card.
- **Write an ADFS image** and put it on a floppy emulator (Gotek, HxC) or an
  MMC/CF card, using whatever tool your setup already uses for ADFS images.
  This repository ships no image builder.
- **BeebLink**, if you have the USB adapter — `tools/beeblink.py` is here for
  a different purpose but the transfer is the same idea.

### Two things to know before you do

**The volume must be writable, or host keys are not remembered.** `KNOWNHST`
is created and appended when a new host is trusted. On a read-only medium the
terminal still runs and still checks any key it already knows — it prints
`(could not write KNOWNHST)` and asks again next time. `PTERMRUN` wants more
write access still, since it saves `RESPROF`, `RESGLAS` and `RXL` at exit;
`CHAIN "SSH"` writes nothing unless it fails.

**This path is documented, not measured.** Every Beeb-side result in this
repository was taken over LANManFS. The reasoning above is drawn from what the
code actually does rather than from a run, and the one thing that could
surprise you is `SSHBLOB`: it is a 50 KB binary loaded to a co-processor
address, and slow media will make startup slower than the 1.4 seconds measured
on the share.

---

## 3. Which build to run

| | |
|---|---|
| `CHAIN "SSH"` | the terminal. No profiler, no wire log, no glass check, no banner. |
| `CHAIN "PTERMRUN"` | the same program with the instruments on, when you want a measurement. `RESPROF`, `RESGLAS` and `RXL` appear beside it. |

`RESERR` is written by both, but only after a failure — turning it off would
trade a diagnosable crash for a blank screen.

## 4. Names, and the two things that fail silently

`HOSTS` maps names to addresses, `/etc/hosts`-style and **CR-terminated**. It
is tried before the module's DNS, the way a Unix box tries the file first.

Two rules that fail *without saying anything* on the machine:

- **Eight characters or fewer on LANManFS**, files and folders alike. A longer
  name is truncated, so `PTERMRUN.inf` arrives as a second `PTERMRUN` sitting
  on top of the program and `*MOUNT` answers "media changed". ADFS is more
  generous at ten, but a name that suits LANManFS suits both.
- **CR line endings, not LF.** `*EXEC` on an LF-terminated file finds no line
  terminator at all, pours the whole file into a 238-byte input buffer, and
  locks the machine up.

`tools/mirror.sh` enforces both and verifies afterwards, which is why files
reach the share through it rather than through `cp`. `HOSTS` is the exception,
because you edit it by hand — hence the line-ending fix in step 1.
