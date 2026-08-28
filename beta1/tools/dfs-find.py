#!/usr/bin/env python3
"""Search a pile of DFS disc images by title or filename, and unpack one.

    tools/dfs-find.py chuckie kong meteor      search bbcmicro.co.uk/
    tools/dfs-find.py --cat Disc043.dsd 0      one catalogue, with addresses
    tools/dfs-find.py --get Disc043.dsd 0 out  unpack that side

The archive is 3000 discs and its only index is archive.org's own S3
metadata, which does not list titles - so the catalogues themselves are the
index. Each is 512 bytes at the front of a side, so scanning the lot costs
almost nothing.

.dsd images hold BOTH sides, interleaved a track at a time: ten sectors of
256 bytes from side 0, then ten from side 2, and so on. Side 2 is where
half of these games live, and a tool that reads only the first 512 bytes
finds nothing there.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib.machinery import SourceFileLoader

_ssd = SourceFileLoader(
    "ssd_extract",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "ssd-extract.py"),
).load_module()
catalogue = _ssd.catalogue

TRACK = 2560
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                    "bbcmicro.co.uk")


def side(path, s):
    d = open(path, "rb").read()
    if not path.lower().endswith(".dsd"):
        return d
    off = 0 if str(s) == "0" else TRACK
    return b"".join(d[i + off:i + off + TRACK]
                    for i in range(0, len(d), 2 * TRACK))


def sides(path):
    return ["0", "2"] if path.lower().endswith(".dsd") else ["0"]


def read(d):
    title = (d[0:8] + d[256:260]).decode("latin-1").rstrip("\0 ")
    return title, (d[0x106] >> 4) & 3, list(catalogue(d))


def show(path, s):
    d = side(path, s)
    title, opt, files = read(d)
    print('%s side %s  title "%s"  boot option %d  %d files'
          % (os.path.basename(path), s, title, opt, len(files)))
    for dirc, name, load, exec_, length, start, locked in files:
        print("  %s.%-8s load &%06X  exec &%06X  len &%05X (%d)"
              % (dirc, name, load, exec_, length, length))


def get(path, s, out):
    d = side(path, s)
    os.makedirs(out, exist_ok=True)
    for dirc, name, load, exec_, length, start, locked in read(d)[2]:
        open(os.path.join(out, name), "wb").write(d[start:start + length])
    print("unpacked %d files to %s" % (len(read(d)[2]), out))


def search(pats):
    pats = [re.compile(p, re.I) for p in pats]
    hits = 0
    for name in sorted(os.listdir(ROOT)):
        if not name.lower().endswith((".ssd", ".dsd")):
            continue
        path = os.path.join(ROOT, name)
        for s in sides(path):
            try:
                d = side(path, s)
                if len(d) < 512:
                    continue
                title, opt, files = read(d)
            except Exception:
                continue
            names = [n for _, n, *rest in files]
            if any(p.search(title + " " + " ".join(names)) for p in pats):
                hits += 1
                print("%-16s s%s %-14s %s"
                      % (name, s, '"' + title + '"', " ".join(names)[:60]))
    print("---", hits, "discs")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "--cat":
        show(a[1] if os.path.exists(a[1]) else os.path.join(ROOT, a[1]),
             a[2] if len(a) > 2 else "0")
    elif a[0] == "--get":
        get(a[1] if os.path.exists(a[1]) else os.path.join(ROOT, a[1]),
            a[2], a[3])
    else:
        search(a)
