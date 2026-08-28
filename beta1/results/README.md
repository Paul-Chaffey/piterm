# Results off the hardware

Raw output from probes run on the real machine, kept because it cannot be
regenerated without the Beeb in front of you. `tools/fbres.py` reads most of
them; `tools/vtdiff.py` reads `PGRID`.

| file | what it settled |
|---|---|
| `RESPAL`, `RESPAL2` | 256 palette entries are individually programmable, so `xterm-256color` is exact |
| `RESFONT` | the driver's font harvests byte-exact, and bit 7 is the leftmost pixel |
| `RESBENC` | the blitter carries a full repaint in 9 cs |
| `RESSAVE` | `SAVE`/`LOAD` over LANManFS is byte-clean at 14 KB/sec |
| `RESVDU` | the renderer at 16,960 cells/sec, and all ten visual checks |
| `RESPTR`, `RESPTR2` | OSWORD &C0 buffer pointers cross the Tube on copro 15, both directions |
| `RESSIZE` | a read above about 64 bytes is refused, and the refusal consumes the bytes anyway |
| `RESPEEK` | `MSG_PEEK` is non-destructive and an over-asked peek reports rather than refusing, so a read can be sized exactly |
| `RESHW`, `PGRID` | the parser drives the renderer at 124,868 bytes/sec, and 250 bytes lost to over-asking |

The share itself is not in the repository. It is the LANManFS mount the Beeb
sees, it is regenerated with `tools/mirror.sh` and `tools/bastok.py`, and it is
kept small on purpose - see `.gitignore`.
