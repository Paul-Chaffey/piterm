#!/usr/bin/env python3
"""Assert a tokenised PTERM build has every instrument off.

  tools/quietck.py share/Pi-TERM/SSH tools/bastok-table.json

Run by tools/sshterm.sh against the file the Beeb will actually load, because
that is the only artefact that matters and it is not the one that was edited.

TRUE and FALSE ARE TOKENS, &B9 and &A3, so "gcheck%=FALSE" never appears as
text in a tokenised file. A grep for it finds nothing whether the patch worked
or not - a check that passes while being wrong, which is worse than no check.
"""
import json, sys

blob = open(sys.argv[1], "rb").read()
tab = json.load(open(sys.argv[2]))
TRUE, FALSE = bytes(tab["TRUE"]), bytes(tab["FALSE"])

bad = []
for var in (b"gcheck%=", b"banner%="):
    if var + TRUE in blob:      bad.append(var.decode() + "TRUE is still in the build")
    if var + FALSE not in blob: bad.append(var.decode() + "FALSE is not in the build")
for s in (b'dump$="RESGLAS"', b'rlog$="RXL"', b'prof$="RESPROF"'):
    if s in blob: bad.append(s.decode() + " is still in the build")
if b'err$="RESERR"' not in blob:
    bad.append("err$ was lost - a crash would leave nothing behind")

i = n = 0
while i + 1 < len(blob) and blob[i] == 0x0D and blob[i + 1] != 0xFF:
    n += 1
    i += blob[i + 3]
if blob[i:i + 2] != bytes([0x0D, 0xFF]) or i + 2 != len(blob):
    bad.append("the tokenised file does not end cleanly")

if bad:
    for b in bad:
        print("quietck: " + b, file=sys.stderr)
    sys.exit(1)
print(f"quietck: {n} lines, every instrument off, err$ kept")
