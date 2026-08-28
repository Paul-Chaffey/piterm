# Getting started

What you need, in the order you need it.

## On the Linux side

```sh
tools/sshbuild.sh                       # the SSH blob, both targets, with its checks
tools/mirror.sh --dir Pi-TERM src/fbvdu.bas src/pterm.bas test/fbvt.bas
tools/fbbuild.sh src/pterm.bas > build/PTERMRUN.bas
tools/fbbuild.sh test/fbvt.bas   > build/FBRUN.bas
tools/mirror.sh --dir Pi-TERM --tok build/PTERMRUN.bas build/FBRUN.bas
tools/sshterm.sh                        # the quiet build, CHAIN "SSH"
tools/sshkey.sh                         # the Beeb's own SSH key
cp tools/HOSTS.example share/Pi-TERM/HOSTS      # then edit it - see below
unix2dos share/Pi-TERM/HOSTS 2>/dev/null || \
    python3 -c "import sys;p='share/Pi-TERM/HOSTS';d=open(p,'rb').read();open(p,'wb').write(d.replace(b'\n',b'\r'))"
sudo bash tools/setup-samba.sh          # read its warning first
tools/mirrorck.sh                       # is the share current with src/?
```

`tools/sshkey.sh` makes a key **separate from your everyday one**, because its
private half has to sit on a share that a 40-year-old computer mounts with no
authentication worth the name. Install it with

```
restrict,pty ssh-ed25519 AAAA... piterm
```

in `authorized_keys` on whatever you want to reach — `restrict,pty` gives an
interactive shell and nothing else: no forwarding, no agent, no tunnelling.

**`setup-samba.sh` deliberately re-enables SMB1, NTLMv1 and LANMAN**, because
the 2009-era Sprow module speaks nothing newer. That is a real weakening of the
machine it runs on. Trusted LAN only, and the file ends with how to undo it.

## On the Beeb

```
CTRL-BREAK
*ARMBASIC
*MOUNT \\deskbox\BEEBOS
*DIR Pi-TERM
CHAIN "SSH"
```

**Mount after the BREAK, never before.** CTRL-BREAK is a hard reset: it clears
sideways ROM private workspace, and LANManFS loses the mount with it. `*MOUNT`
works from the co-processor because it is a `*` command and the host's ROM
runs it.

A *soft* BREAK keeps the mount but loses the current directory, which is what
`*KEY 10 *DIR Pi-TERM|MCHAIN"SSH"|M` is for.

## Which build to run

| | |
|---|---|
| `CHAIN "SSH"` | the terminal. No profiler, no wire log, no glass check, no banner. |
| `CHAIN "PTERMRUN"` | the same program with the instruments on, when you want a measurement. `RESPROF`, `RESGLAS` and `RXL` appear on the share. |

`RESERR` is written by both, but only after a failure — turning it off would
trade a diagnosable crash for a blank screen.

## Names, and the two things that fail silently

`HOSTS` on the share maps names to addresses, `/etc/hosts`-style and
**CR-terminated** — which is why the copy above translates the line endings;
`tools/mirror.sh` does that for everything it writes, but `HOSTS` is edited by
hand and does not go through it. The addresses in `HOSTS.example` are RFC 5737
documentation ones and will not reach anything: replace them with yours. It is tried before the module's DNS, the way a Unix box
tries the file first.

Two LANManFS rules, both of which fail *silently* on the machine:

- **Eight characters or fewer, for files and folders alike.** A longer name is
  truncated, so `PTERMRUN.inf` arrives as a second `PTERMRUN` sitting on top of
  the program and `*MOUNT` answers "media changed".
- **CR line endings, not LF.** `*EXEC` on an LF-terminated file finds no line
  terminator at all, pours the whole file into a 238-byte input buffer, and
  locks the machine up.

`tools/mirror.sh` enforces both and verifies afterwards, which is why files
reach the share through it rather than through `cp`.
