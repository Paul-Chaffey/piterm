#!/usr/bin/env python3
"""Generate TUBEDATA, the fixed block TUBECRC drags across the Tube.

Deterministic, so the reference checksum is stable for ever and a mismatch
means the Tube, not a changed file. Do NOT put a real program here: a file
that mirror.sh rewrites would silently invalidate every recorded run.

The checksum is a plain byte sum, which is what BBC BASIC can compute quickly
enough to keep the loop dominated by the transfer rather than the maths. Any
single corrupted byte changes it, and a lost byte shifts everything after it,
so both of the failure modes tube_delay is suspected of are caught.
"""
import sys, pathlib

SIZE = 65536
OUT = pathlib.Path("share/Pi-TERM/TUBEDATA")

# xorshift32, written out rather than imported, so the sequence cannot drift
# with a library version. Seed is arbitrary but fixed.
def gen(n):
    x = 0x2A6B1D53
    out = bytearray(n)
    for i in range(n):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        out[i] = x & 0xFF
    return bytes(out)

data = gen(SIZE)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(data)
print(f"{OUT}  {len(data)} bytes")
print(f"byte sum = {sum(data)}  (&{sum(data):X})")
print(f"first 8  = {' '.join(f'{b:02X}' for b in data[:8])}")
print(f"last 8   = {' '.join(f'{b:02X}' for b in data[-8:])}")
