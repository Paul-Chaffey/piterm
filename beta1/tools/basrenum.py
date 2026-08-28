#!/usr/bin/env python3
"""Renumber a BBC BASIC listing in place.

  tools/basrenum.py src/fbvdu.bas [start] [step]

Editing a BASIC source by inserting lines is otherwise a choice between
fractional line numbers and renumbering the whole file by hand. This does
the second, and rewrites the line-number references that renumbering would
otherwise break: GOTO, GOSUB, RESTORE, THEN/ELSE followed by a number, and
ON ... GOTO/GOSUB lists.

Lines whose number is missing are given the next one, so an insertion can
be written with any placeholder in the number column.

It refuses to renumber a file whose references do not all resolve, because
a silently retargeted GOTO is worse than an error.
"""
import re, sys

def renum(path, start=1000, step=10, bands=None):
    """bands: [(from_original, new_start, new_step), ...], lowest first.

    A DRIVER SHARES A FILE WITH THE ENGINE BY LINE NUMBER. src/fbvdu.bas holds
    1000-9990 and a driver holds 10-990 plus 10000 up; on the Beeb they are
    loaded separately and BASIC files them by number, and tools/fbbuild.sh
    merges them with sort -n for the linter. Renumbering such a driver as ONE
    sequence would run its 1,257 lines straight through the engine's range and
    interleave the two programs.

    That is a reason to renumber IN BANDS, not a reason not to renumber - and
    calling it "this file cannot be renumbered" was wrong. With bands, each
    group keeps its lane:

        tools/basrenum.py src/pterm.bas --bands 0:10:3 1000:10000:10

    reads as: original lines from 0 up become 10 step 3, original lines from
    1000 up become 10000 step 10.
    """
    raw = open(path).read().replace('\r\n', '\n').replace('\r', '\n')
    lines = [l for l in raw.split('\n') if l.strip() != '']
    old, text = [], []
    for l in lines:
        m = re.match(r'\s*(\d+)\s?(.*)$', l)
        if m:
            old.append(int(m.group(1))); text.append(m.group(2))
        else:
            old.append(None); text.append(l.strip())
    if bands:
        new, counts = [], {b[0]: 0 for b in bands}
        for o in old:
            key = max((b[0] for b in bands if o is not None and o >= b[0]),
                      default=bands[0][0])
            b = [x for x in bands if x[0] == key][0]
            new.append(b[1] + counts[key] * b[2])
            counts[key] += 1
    else:
        new = [start + i * step for i in range(len(lines))]
    tbl = {o: n for o, n in zip(old, new) if o is not None}

    ref = re.compile(r'\b(GOTO|GOSUB|RESTORE|THEN|ELSE)\s+(\d+)')
    bad = []
    def fix(m):
        kw, num = m.group(1), int(m.group(2))
        if num not in tbl:
            bad.append((kw, num)); return m.group(0)
        return "%s %d" % (kw, tbl[num])
    text = [ref.sub(fix, t) for t in text]
    if bad:
        raise SystemExit("%s: unresolved line references: %s" % (path, bad))

    out = "\n".join("%5d %s" % (n, t) for n, t in zip(new, text)) + "\n"
    open(path, 'w').write(out)
    return len(lines), new[-1]

if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    p = sys.argv[1]
    if '--bands' in sys.argv:
        i = sys.argv.index('--bands')
        spec = sorted(tuple(int(x) for x in a.split(':')) for a in sys.argv[i + 1:])
        if not spec:
            raise SystemExit("--bands needs at least one from:start:step")
        n, last = renum(p, bands=spec)
        print("%s: %d lines in %d bands, ending %d" % (p, n, len(spec), last))
    else:
        a = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
        b = int(sys.argv[3]) if len(sys.argv) > 3 else 10
        n, last = renum(p, a, b)
        print("%s: %d lines, %d to %d" % (p, n, a, last))
