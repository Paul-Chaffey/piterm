#!/usr/bin/env python3
"""Analyse RESDIFF against TUBEDATA and say what the Tube actually did.

Every claim the Beeb makes is re-checked here against the real bytes: the
shift distance, which byte went missing, and whether the sum delta agrees.
The Beeb's own arithmetic crossed the same Tube it is measuring.
"""
import sys, pathlib, re, collections

ref = pathlib.Path("share/Pi-TERM/TUBEDATA").read_bytes()
S = sum(ref)
raw = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                   else "share/Pi-TERM/RESDIFF").read_bytes()
lines = [l.strip() for l in raw.replace(b"\r\n", b"\r").split(b"\r")]
lines = [l.decode("ascii", "replace") for l in lines if l]

# TUBEDIFF APPENDS, so one file holds several runs. Split on the header or
# every run after the first is silently merged into the first one's statistics.
runs, recs, cur, hist = [], [], None, {}
for l in lines:
    if l.startswith("# TUBEDIFF") and recs:
        runs.append(recs); recs = []
    if l.startswith("#  eor"):
        _, _, v, c = l.split(); hist[int(v, 16)] = int(c); continue
    if l.startswith("#"):
        print(l); continue
    if l.startswith("want "):
        cur["wdump"] = l.split()[1:]; continue
    if l.startswith("got "):
        # separate keys: "want"/"got" are the single bytes from the record
        # line, "wdump"/"gdump" the surrounding hex. Sharing them silently
        # replaced a hex string with a list.
        cur["gdump"] = l.split()[1:]; recs.append(cur); continue
    f = l.split()
    if len(f) == 7:
        cur = dict(zip("pass ndiff first want got shift sum".split(), f))

runs.append(recs)
recs = runs[int(sys.argv[2]) - 1] if len(sys.argv) > 2 else runs[-1]
print(f"\n{len(runs)} run(s) in file; showing run "
      f"{int(sys.argv[2]) if len(sys.argv)>2 else len(runs)}")
print(f"TUBEDATA {len(ref)} bytes, sum {S}\n")
print(f"{'pass':>5} {'first':>7} {'lost':>5} {'shift':>5} {'ndiff':>7} "
      f"{'expect':>7} {'sumd':>6} {'check'}")
kinds, losses, offs = collections.Counter(), [], []
for r in recs:
    first, k = int(r["first"]), int(r["shift"])
    nd, sd = int(r["ndiff"]), int(r["sum"]) - S
    # verify the shift from the logged bytes, not from the Beeb's claim
    o = int(r["gdump"][0])
    gb = bytes.fromhex(r["gdump"][1]); wb = bytes.fromhex(r["wdump"][1])
    real = None
    for cand in range(1, 9):
        if all(gb[i] == ref[o + i + cand] for i in range(first - o, len(gb))
               if o + i + cand < len(ref)):
            real = cand; break
    lost = ref[first] if k > 0 else None
    exp = len(ref) - first          # bytes damaged by a single loss at `first`
    ok = []
    ok.append("shift" if real == k else f"SHIFT?{real}")
    ok.append("ndiff" if abs(nd - exp) < exp * 0.02 + 300 else "NDIFF?")
    ok.append("sum" if lost is not None and sd == -lost else f"SUM?{sd}")
    kinds[k] += 1
    if lost is not None: losses.append(lost)
    offs.append(first)
    print(f"{r['pass']:>5} {first:>7} {(('&%02X' % lost) if lost is not None else '-'):>5} "
          f"{k:>5} {nd:>7} {exp:>7} {sd:>6}  {' '.join(ok)}")

# 0x55 is what an undriven bus reads on this hardware: config.txt pulls
# D6,D4,D2,D0 up and D7,D5,D3,D1 down. A got of exactly 0x55 with no shift
# means the Pi sampled while nobody was driving the Tube.
UNDRIVEN = 0x55
nod = [r for r in recs if int(r["shift"]) == 0]
if nod:
    print("\nno-shift faults (value changed, block intact):")
    for r in nod:
        w, g = int(r["want"], 16), int(r["got"], 16)
        tag = "  <-- UNDRIVEN BUS (&55)" if g == UNDRIVEN else ""
        print(f"  pass {r['pass']:>4} off {r['first']:>6} "
              f"want &{w:02X} got &{g:02X} eor &{w ^ g:02X}{tag}")

print(f"\nshift distances: {dict(kinds)}")
if offs:
    print(f"first-fault offsets: min {min(offs)} max {max(offs)} n {len(offs)}")
    for blk in (128, 256, 512, 1024, 4096):
        print(f"  mod {blk:>5}: {sorted(o % blk for o in offs)}")
if hist:
    tot = sum(hist.values())
    print(f"\neor histogram: {len(hist)} distinct patterns, {tot} events, "
          f"mean {tot/len(hist):.0f} per pattern")
