#!/usr/bin/env python3
"""Tokenise a BBC BASIC listing into the form LOAD and CHAIN expect.

    tools/bastok.py src/fbvdu.bas share/FBVDU
    tools/bastok.py --inf src/fbvdu.bas emu/vdfs/FBVDU    (VDFS wants a .inf)

Why this exists: `*EXEC` feeds a text file through the input stream one
character at a time and BASIC tokenises each line as it arrives. It works,
but it is the slowest part of every edit-test cycle - minutes under the
emulator for a 60K source, where a CHAIN of the same program is seconds
(14 KB/sec over LANManFS, specification.md 6.4). Tokenising on this side
removes *EXEC from the loop entirely.

THE TABLE IS NOT HAND-WRITTEN. It was dumped out of ARM BASIC V itself by
typing keywords in and reading PAGE..TOP back. Note the second probe it
needed: PTR, PAGE, TIME, LOMEM and HIMEM have one token as a value and
another as an assignment target, and a keyword ALONE ON A LINE is read as a
statement - so the first probe measured PAGE as &D0, the assignment form,
and every ~PAGE in a program came out as "Unknown or missing variable".
They are probed as "X=PAGE" and "PAGE=1" - see
tools/bastok-table.json and the note in docs/. Guessing it would have been
wrong: in BASIC V the command keywords LOAD, SAVE, LIST, NEW, DELETE,
RENUMBER, AUTO, OLD and EDIT are TWO-byte C7 xx tokens rather than the
single bytes BASIC IV uses, and SYS is C8 99.

What is deliberately not done: line numbers after GOTO, GOSUB, RESTORE and
THEN are left as plain digits rather than encoded as 8D plus three bytes.
Both forms run - the argument is an expression either way - and the encoded
form exists so that RENUMBER can find them. We renumber on this side with
tools/basrenum.py, so nothing on the machine needs to.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, "bastok-table.json")


def load_table():
    with open(TABLE) as f:
        raw = json.load(f)
    # Longest first, so ENDPROC wins over END and INSTR( over INT. This is
    # what the machine does: it matches greedily at each position, which is
    # also why PRINTER tokenises as PRINT followed by ER.
    kws = sorted((k for k in raw if not k.endswith("=") and "@" not in k),
                 key=lambda k: (-len(k), k))
    lv = {k[:-1]: bytes(raw[k]) for k in raw if k.endswith("=")}
    return [(k, bytes(raw[k])) for k in kws], lv


# The machine encodes a line number after GOTO, GOSUB, RESTORE, THEN and
# ELSE as &8D and three bytes, so that RENUMBER can find it. Derived from
# the machine's own output rather than a book: RESTORE 2140 came back as
# 8D 44 5C 48 and RESTORE 7345 as 8D 74 71 5C, and two samples pin it down.
REFKW = ("GOTO", "GOSUB", "RESTORE", "THEN", "ELSE")


def linenum(n):
    lo, hi = n & 0xFF, n >> 8
    return bytes((0x8D,
                  (((lo & 0xC0) >> 2) | ((hi & 0xC0) >> 4)) ^ 0x54,
                  (lo & 0x3F) | 0x40,
                  (hi & 0x3F) | 0x40))


def tokenise_line(text, kws, lv, stmt_else=None):
    out = bytearray()
    i, n = 0, len(text)
    seen_then = False
    # A statement beginning with * is an operating system command and is
    # passed through untouched - *FX4,0 must not acquire a token.
    if text.lstrip().startswith("*"):
        return text.encode("latin-1")
    while i < n:
        c = text[i]
        if c == '"':
            j = text.find('"', i + 1)
            j = n if j < 0 else j + 1
            out += text[i:j].encode("latin-1")
            i = j
            continue
        matched = False
        # A keyword is only a keyword at the START of a name. The machine's
        # tokeniser consumes a whole identifier once it has begun one, which
        # is why PRINTER is PRINT followed by ER - PRINT starts at a
        # boundary - while DONTWAIT% stays a variable. Matching at every
        # position instead turned DONTWAIT% into D, the token for ON, and
        # TWAIT%, and the machine answered "Mistake".
        # "" in "_%$" is True in Python, so an empty prev has to be tested
        # for explicitly or the first character of every line stops being a
        # boundary and nothing tokenises at all.
        prev = text[i - 1] if i else ""
        boundary = prev == "" or not (prev.isalnum() or prev in "_%$")
        if boundary and (c.isupper() or c in "$("):
            for k, tok in kws:
                if text.startswith(k, i):
                    # ELSE has two tokens: &8B inline after a THEN, &CC
                    # starting a statement in a multi-line IF. Probing it
                    # alone on a line gives the second, and putting that
                    # in a single-line IF is a syntax error.
                    if k == "ELSE" and not seen_then and stmt_else:
                        out += stmt_else
                        i += len(k)
                        matched = True
                        break
                    if k == "THEN":
                        seen_then = True
                    # PTR PAGE TIME LOMEM HIMEM have a second token for the
                    # assignment form, and the machine picks by looking at
                    # what follows.
                    if k in lv and text[i + len(k):i + len(k) + 1] == "=":
                        # The assignment token already carries the "=", so
                        # step over the source one too or the line gets two.
                        out += lv[k]
                        i += len(k) + 1
                    else:
                        out += tok
                        i += len(k)
                    # REM and DATA take the rest of the line literally.
                    if k in ("REM", "DATA"):
                        out += text[i:].encode("latin-1")
                        return bytes(out)
                    # A literal line number after one of these is encoded.
                    if k in REFKW:
                        j = i
                        while j < n and text[j] == " ":
                            j += 1
                        d = j
                        while d < n and text[d].isdigit():
                            d += 1
                        if d > j:
                            out += text[i:j].encode("latin-1")
                            out += linenum(int(text[j:d]))
                            i = d
                    matched = True
                    break
        if not matched:
            out += c.encode("latin-1")
            i += 1
    return bytes(out)


def tokenise(path):
    kws, lv = load_table()
    with open(TABLE) as f:
        stmt_else = bytes(json.load(f).get("ELSE@stmt", [0xCC]))
    prog = bytearray()
    for raw in open(path, encoding="latin-1"):
        raw = raw.rstrip("\r\n")
        if not raw.strip():
            continue
        # Everything after the digits is kept verbatim, the space
        # included - that is what the machine stores, and eating it put
        # a token where a space belonged on every line in the program.
        m = re.match(r"\s*(\d+)(.*)$", raw)
        if not m:
            raise SystemExit(f"{path}: line without a number: {raw[:40]!r}")
        num = int(m.group(1))
        if not 0 <= num <= 65279:
            raise SystemExit(f"{path}: line number {num} out of range")
        body = tokenise_line(m.group(2), kws, lv, stmt_else)
        length = len(body) + 4
        if length > 255:
            raise SystemExit(f"{path}: line {num} is {length} bytes, over 255")
        prog += bytes([0x0D, num >> 8, num & 0xFF, length]) + body
    prog += bytes([0x0D, 0xFF])
    return bytes(prog)


def main():
    args = [a for a in sys.argv[1:] if a != "--inf"]
    inf = "--inf" in sys.argv[1:]
    if len(args) != 2:
        raise SystemExit(__doc__)
    src, dst = args
    data = tokenise(src)
    # Written to a temporary file and renamed, so a reader never sees a
    # half-written program. The share is mounted by the Beeb and a CHAIN
    # that overlaps a rebuild reads whatever has landed so far - which
    # BASIC reports as "Bad program", a fault in the file rather than in
    # the machine, and one that has vanished by the time it is looked at.
    tmp = dst + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, dst)
    # The .inf gives VDFS the load and exec addresses, and is written ONLY
    # when asked for. It must never land on the LANManFS share: the name is
    # over eight characters, the filing system truncates, and PTERMRUN.inf
    # becomes a second PTERMRUN sitting on top of the program. The Beeb
    # answered that with "media changed" on *mount. mirror.sh has refused
    # long names since the beginning for exactly this reason; this did not.
    if inf:
        name = os.path.basename(dst)
        if len(name) > 8:
            raise SystemExit(f"{name}: over 8 characters, and the .inf would "
                             f"truncate onto another file")
        with open(dst + ".inf", "w") as f:
            f.write(f"$.{name}   000E00 000E00 {len(data):06X}\n")
    src_bytes = os.path.getsize(src)
    print(f"{dst}: {len(data)} bytes tokenised from {src_bytes} "
          f"({100 - 100 * len(data) // src_bytes}% smaller)")


SELFTEST = [
    # Verified against the machine's own SAVE. The boundary cases are the
    # point: PRINTER is PRINT followed by ER because PRINT starts at a
    # boundary, and DONTWAIT% is a variable because ON does not.
    ('PRINT "x"',        'F1 20 22 78 22'),
    ('PRINTER=1',        'F1 45 52 3D 31'),
    ('PEEK%=1:DONTWAIT%=8',
     '50 45 45 4B 25 3D 31 3A 44 4F 4E 54 57 41 49 54 25 3D 38'),
    ('FIONBIO%=1',       '46 49 4F 4E 42 49 4F 25 3D 31'),
    ('FOR i%=0 TO 15',   'E3 20 69 25 3D 30 20 B8 20 31 35'),
    ('IF a% THEN PROCx ELSE PROCy',
     'E7 20 61 25 20 8C 20 F2 78 20 8B 20 F2 79'),
    ('T=TIME',           '54 3D 91'),
    ('PAGE=&4000',       'D0 3D 26 34 30 30 30'),
    ('RESTORE 2140',     'F7 20 8D 44 5C 48'),
    ('SYS "OS_Word"',    'C8 99 20 22 4F 53 5F 57 6F 72 64 22'),
]


def selftest():
    kws, lv = load_table()
    with open(TABLE) as f:
        stmt = bytes(json.load(f).get("ELSE@stmt", [0xCC]))
    bad = 0
    for src, want in SELFTEST:
        got = tokenise_line(src, kws, lv, stmt).hex(" ").upper()
        if got != want:
            bad += 1
            print(f"  BAD {src!r}\n      got  {got}\n      want {want}")
    print(f"  {len(SELFTEST) - bad} of {len(SELFTEST)} cases pass")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    main()
