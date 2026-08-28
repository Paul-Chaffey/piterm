#!/usr/bin/env python3
"""Strip comment lines from a numbered BBC BASIC source.

    tools/basstrip.py src/fbvdu.bas > small.bas

The comments in this project's sources are heavy on purpose - they carry
the reasoning, and the reasoning is the part that is expensive to
reconstruct. But they are also tokenised bytes on a machine with 30K of
BASIC space, and FBVDU stopped fitting on an emulated 6502 co-processor
while the source was still being written.

So: the repository keeps the commented source, and anything memory-bound
runs a stripped build. Only whole REM lines and bare : separators are
removed, never the line numbers of the lines that remain, so nothing that
refers to a line number can break. Nothing in this project does - it is
all named procedures - but that is a property worth not relying on.

Inline comments after a statement are left alone: distinguishing a REM
from the same characters inside a string needs a tokeniser, and getting
that wrong would corrupt a program rather than shrink it.
"""
import re, sys


def strip(path):
    kept, dropped, bytes_out, bytes_in = [], 0, 0, 0
    for line in open(path):
        text = line.rstrip('\n')
        bytes_in += len(text) + 1
        body = re.sub(r'^\s*\d+\s?', '', text)
        if re.match(r'^\s*REM\b', body) or body.strip() == ':' or not body.strip():
            dropped += 1
            continue
        kept.append(text)
        bytes_out += len(text) + 1
    return kept, dropped, bytes_in, bytes_out


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    kept, dropped, bin_, bout = strip(sys.argv[1])
    print("\n".join(kept))
    print(f"{sys.argv[1]}: kept {len(kept)} lines, dropped {dropped} comment lines, "
          f"{bin_} -> {bout} bytes ({100 - bout * 100 // bin_}% smaller)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
