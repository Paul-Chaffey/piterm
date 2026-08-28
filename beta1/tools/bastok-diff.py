#!/usr/bin/env python3
"""Compare tools/bastok.py's output against the machine's own tokenisation.

    tools/bastok-diff.py src.bas REF

REF is what the machine produced for the same source: *EXEC it once, SAVE,
and the file the emulator wrote is ground truth. Any difference is a bug in
the tokeniser, located at the exact line and byte - which beats probing
keywords one at a time, because the context-dependent ones (ELSE inline
versus ELSE starting a statement, PAGE as a value versus as an assignment
target) only show up in real code.
"""
import importlib.util, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("bastok", os.path.join(HERE, "bastok.py"))
bastok = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bastok)


def split(prog):
    """-> [(line number, body bytes)]"""
    out, i = [], 0
    while i + 3 < len(prog) and prog[i] == 0x0D and prog[i + 1] != 0xFF:
        num = (prog[i + 1] << 8) | prog[i + 2]
        ln = prog[i + 3]
        out.append((num, prog[i + 4:i + ln]))
        i += ln
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src, ref = sys.argv[1], sys.argv[2]
    mine = split(bastok.tokenise(src))
    theirs = split(open(ref, "rb").read())
    text = {}
    import re
    for raw in open(src, encoding="latin-1"):
        m = re.match(r"\s*(\d+)\s?(.*)$", raw.rstrip("\r\n"))
        if m:
            text[int(m.group(1))] = m.group(2)

    mm, tt = dict(mine), dict(theirs)
    bad = 0
    if set(mm) != set(tt):
        only_mine, only_theirs = sorted(set(mm) - set(tt)), sorted(set(tt) - set(mm))
        if only_mine:
            print(f"  lines only in bastok: {only_mine[:8]}")
        if only_theirs:
            print(f"  lines only in the machine's: {only_theirs[:8]}")
        bad += 1
    for num in sorted(set(mm) & set(tt)):
        if mm[num] != tt[num]:
            bad += 1
            if bad <= 12:
                print(f"  line {num}: {text.get(num, '')!r}")
                print(f"    bastok  {mm[num].hex(' ').upper()}")
                print(f"    machine {tt[num].hex(' ').upper()}")
                for a, b in zip(mm[num], tt[num]):
                    if a != b:
                        print(f"    first difference: &{a:02X} where the machine has &{b:02X}")
                        break
    total = len(set(mm) | set(tt))
    if bad:
        print(f"\n  {bad} of {total} lines differ")
        return 1
    print(f"  all {total} lines byte-identical to the machine's own tokenisation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
