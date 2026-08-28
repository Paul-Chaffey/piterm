#!/usr/bin/env python3
"""Unpack a DFS .ssd disc image into loose files.

  tools/ssd-extract.py image.ssd outdir

The BBC has no disc drive in this setup, so a .ssd is useless as-is. What is
useful is the two things DFS keeps alongside each file: the load address and
the execution address. Those are absolute, so once a file is extracted it can
be *LOADed to the right place and CALLed from any filing system -- LANMANFS
over the Samba share, or b-em's VDFS.

Alongside each file this writes a .inf (name, load, exec, length in hex), the
format b-em's VDFS and most BBC tools expect. LANMANFS ignores .inf files, so
for the real machine read the addresses off the printed catalogue instead.
"""
import os
import sys


def catalogue(d):
    nfiles = d[0x105] // 8
    for i in range(nfiles):
        n = 8 + i * 8
        a = 0x108 + i * 8
        name = d[n:n + 7].decode("latin-1").rstrip()
        dirc = chr(d[n + 7] & 0x7F)
        locked = bool(d[n + 7] & 0x80)
        ext = d[a + 6]
        load = d[a] | d[a + 1] << 8 | ((ext >> 2) & 3) << 16
        exec_ = d[a + 2] | d[a + 3] << 8 | ((ext >> 6) & 3) << 16
        length = d[a + 4] | d[a + 5] << 8 | ((ext >> 4) & 3) << 16
        start = ((ext & 3) << 8 | d[a + 7]) * 256
        # &FFxxxx is how DFS spells "host address", the top bits are padding
        if load & 0x30000 == 0x30000:
            load |= 0xFF0000
        if exec_ & 0x30000 == 0x30000:
            exec_ |= 0xFF0000
        yield dirc, name, load, exec_, length, start, locked


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    img, outdir = sys.argv[1], sys.argv[2]
    d = open(img, "rb").read()
    title = (d[0:8] + d[256:260]).decode("latin-1").rstrip("\0 ")
    opt = (d[0x106] >> 4) & 3
    print(f'title "{title}"  boot option {opt}  {d[0x105] // 8} files')
    os.makedirs(outdir, exist_ok=True)
    for dirc, name, load, exec_, length, start, locked in catalogue(d):
        data = d[start:start + length]
        if len(data) < length:
            print(f"  {name}: TRUNCATED, image holds {len(data)} of {length}")
        path = os.path.join(outdir, name)
        with open(path, "wb") as f:
            f.write(data)
        with open(path + ".inf", "w") as f:
            f.write(f"{dirc}.{name:<7} {load:06X} {exec_:06X} {length:06X}"
                    f"{' Locked' if locked else ''}\n")
        print(f"  {dirc}.{name:<7} load &{load:04X}  exec &{exec_:04X}  "
              f"length &{length:04X} ({length} bytes)")

# Guarded so the catalogue parser can be imported. Without this, importing
# this file ran main(), printed the usage text and exited - which is how
# tools/dfs-find.py first "failed".
if __name__ == "__main__":
    main()
