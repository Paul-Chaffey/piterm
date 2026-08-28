#!/usr/bin/env python3
"""Analyse PTERM's RESPROF and say where the time went.

The counters are cumulative, so this differences consecutive snapshots. Each
row is one profcs% interval; the columns are centiseconds spent in each region
plus the work done, which together give cost per unit of work.
"""
import sys, pathlib
COLS = ("t where got pump parse flush keys nscroll tscroll nflush "
        "ncells reads e1e bursts bbytes bcs breads").split()
raw = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                   else "share/Pi-TERM/RESPROF").read_bytes()
rows, hdr = [], []
for l in raw.replace(b"\r\n", b"\r").split(b"\r"):
    l = l.decode("ascii", "replace").strip()
    if not l: continue
    if l.startswith("#"): hdr.append(l); continue
    f = l.split()
    if len(f) == len(COLS): rows.append([int(x) for x in f])
for h in hdr: print(h)
if len(rows) < 2:
    print(f"\nonly {len(rows)} snapshot(s) - nothing to difference"); sys.exit()
D = lambda i, c: rows[i][COLS.index(c)] - rows[i-1][COLS.index(c)]
tot = {c: rows[-1][COLS.index(c)] - rows[0][COLS.index(c)] for c in COLS}
span = tot["t"] or 1
print(f"\n{len(rows)} snapshots over {span/100:.1f}s\n")
print("WHERE THE TIME WENT (centiseconds, and % of elapsed)")
acct = 0
for c in ("pump", "parse", "flush", "keys"):
    acct += tot[c]
    print(f"  {c:>6}: {tot[c]:>8}  {tot[c]/span*100:5.1f}%")
print(f"  {'scroll':>6}: {tot['tscroll']:>8}  {tot['tscroll']/span*100:5.1f}%"
      f"   (inside flush)")
print(f"  {'idle':>6}: {span-acct:>8}  {(span-acct)/span*100:5.1f}%"
      f"   (waiting on the socket)")
print("\nWORK DONE")
print(f"  bytes received : {tot['got']:,}")
print(f"  socket reads   : {tot['reads']:,}"
      f"   ({tot['got']/max(tot['reads'],1):.1f} plaintext bytes per socket read)")
print(f"  would-blocks   : {tot['e1e']:,}")
print(f"  flushes        : {tot['nflush']:,}")
print(f"  cells painted  : {tot['ncells']:,}"
      f"   ({tot['ncells']/max(tot['nflush'],1):.0f} per flush)")
print(f"  scrolls        : {tot['nscroll']:,}")
print("\nUNIT COSTS")
if tot["got"]:    print(f"  throughput     : {tot['got']/(span/100):,.0f} bytes/sec")
if tot["nscroll"]:print(f"  per scroll     : {tot['tscroll']/tot['nscroll']:.2f} cs")
if tot["ncells"]: print(f"  per cell       : {tot['flush']/tot['ncells']*10:.3f} ms")
if tot["reads"]:  print(f"  per socket read: {tot['pump']/tot['reads']:.3f} cs")
# A burst is a drain of >=burstmin% bytes, so these count only the time in
# which data was ACTUALLY flowing. That separates "PTERM is slow" from "the
# far end is slow": the overall figure above is dominated by idle waiting.
if tot["bursts"]:
    print("\nWHILE DATA WAS ACTUALLY FLOWING (drains of 256+ bytes)")
    print(f"  bursts         : {tot['bursts']:,}")
    print(f"  bytes in bursts: {tot['bbytes']:,}"
          f"   ({tot['bbytes']/max(tot['got'],1)*100:.0f}% of all bytes)")
    print(f"  time in bursts : {tot['bcs']:,} cs")
    print(f"  BURST RATE     : {tot['bbytes']/max(tot['bcs'],1)*100:,.0f} bytes/sec")
    per = tot['bbytes'] / max(tot['breads'], 1)
    print(f"  reads in bursts: {tot['breads']:,}"
          f"   ({per:.1f} plaintext bytes per socket read,"
          f" {tot['bcs']/max(tot['breads'],1):.2f} cs per read)")
    ceil = 64 / (tot['bcs'] / max(tot['breads'], 1) / 100)
    print(f"  wire ceiling   : {ceil:,.0f} bytes/sec at 64 wire bytes per read")

    # TWO DIFFERENT CURRENCIES, and mixing them was silently wrong. got% is
    # counted AFTER decompression, in PROCemit; reads% counts ciphertext
    # reads off the module. Before SSH they were the same bytes and the
    # ratio was harmless. With zlib they are not: a 64-byte read can carry
    # several hundred bytes of screen, and the figure above is expansion,
    # not throughput. The module still caps a read at 64, so anything over
    # that is compression and can be reported as such.
    if per > 64:
        print(f"  compression    : at least {per/64:.1f}x"
              f"   (a read cannot exceed 64 wire bytes, and this carried {per:.0f})")
        print(f"  to the screen  : {tot['bbytes']/max(tot['bcs'],1)*100:,.0f} bytes/sec"
              f"   against a wire that moved at most {ceil:,.0f}")

print("\nWORST INTERVALS BY FLUSH TIME")
w = sorted(range(1, len(rows)), key=lambda i: -D(i, "flush"))[:5]
for i in w:
    print(f"  t={rows[i][0]/100:8.2f}s flush={D(i,'flush'):>5}cs "
          f"scroll={D(i,'tscroll'):>5}cs cells={D(i,'ncells'):>6} "
          f"pump={D(i,'pump'):>5}cs got={D(i,'got'):>6}")
