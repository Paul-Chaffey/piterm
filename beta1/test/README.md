# Step 0a — host-only OSWORD &C0 probe

`nettest.bas` establishes a known-good baseline: **does the Sprow module make an
outbound TCP connection at all, driven from BASIC on the host?**

No Tube. No ROM. If this fails, nothing further in the plan is worth attempting.
If it succeeds, Step 0b can introduce the Tube as the only new variable.

## On the Linux side

Something to connect to that sends a banner immediately, then echoes:

```sh
socat TCP-LISTEN:2323,reuseaddr,fork SYSTEM:'echo BEEB OK; date; cat'
```

Check the firewall allows 2323 from the BBC's address.

## On the BBC

1. Confirm the module has an address (LANManager, or however it is configured).
2. Edit lines 160/170 of `nettest.bas` — `ip$` is the **Linux box**, `port%` 2323.
3. `RUN`.

## What to look for

The program dumps control block offsets 0–19 before and after every call, in
hex, grouped in fours. Read the conventions off the screen rather than trusting
the assumptions baked into the program:

| Observation | Meaning |
|---|---|
| `+3` non-zero after `Socket_Creat` | calling convention wrong, or module not ready |
| `+4` plausible small integer after Creat | that is the socket number — convention confirmed |
| `+4` negative after any call | error; the doc says failures return negative values |
| `Connect` fails but `Creat` worked | **most likely the `sockaddr` guess** — see below |
| `BEEB OK` and a date appear | full path works; the baseline is established |

## The sockaddr guess

The API mirrors RISC OS `Socket_` SWIs, but neither the structure layout nor the
`AF_`/`SOCK_` constants are documented anywhere I could find. The program
therefore assumes:

- BSD 4.4 `sockaddr_in`: length byte at +0, family at +1, port big-endian at
  +2, IPv4 address at +4, total 16 bytes
- `AF_INET` = 2, `SOCK_STREAM` = 1

**If `Connect` fails, change line 200 to `sa44%=FALSE`** and retry. That
switches to the BSD 4.3 layout (16-bit family at +0, no length byte), which is
the other likely candidate. The `sockaddr:` line printed before each attempt
shows exactly what was built.

If neither works, the constants are the next suspects — try `SOCK_STREAM%=2`.

## Non-blocking

The program attempts `Socket_Ioctl` with `FIONBIO` (`&8004667E`, the BSD value)
so `Socket_Recv` can be polled. If that call reports an error it prints a
warning and continues — in which case `Recv` may block and the machine may
appear to hang. That outcome is itself informative: it means `BEEBNET` will need
to handle blocking behaviour, which matters for the read-ahead design in §5.3.

## Recording results

Whatever happens, note it against specification.md §7 open question 1 and §5.6.
The dumps answer several undocumented things at once: where the return value
lands, whether `+3` is really the result byte, and whether the block is modified
in place.
