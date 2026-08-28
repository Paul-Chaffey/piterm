#!/usr/bin/env python3
"""What SSH would do to the byte count of a captured session.

docs/ssh.md turns on one number: whether wrapping the terminal stream in
SSH costs bandwidth or saves it. The framing costs bytes and the
compression saves them, and neither is worth guessing at when there are
real captures in captures/ to measure.

Two things are modelled, both exactly as OpenSSH does them:

  FRAMING. chacha20-poly1305@openssh.com, which is the AEAD a client
  built for this machine would implement (docs/ssh.md). Per packet: a
  4-byte encrypted length, a padding-length byte, the SSH_MSG_CHANNEL_DATA
  header of 9 bytes, padding to an 8-byte boundary with a minimum of 4,
  and a 16-byte Poly1305 tag. The length field is outside the padded
  block for this cipher, which is why the padding is computed on
  1 + payload alone.

  COMPRESSION. zlib@openssh.com is streaming deflate with a
  Z_SYNC_FLUSH at every packet boundary - NOT one-shot compression of
  the whole file, which would flatter it enormously. The 32 KB history
  window carries across packets, which is where the win comes from on a
  full-screen redraw: the second frame is mostly a reference to the
  first.

The packet size is the variable that matters and it is not ours to
choose - it is however much the far end's pty had buffered when sshd
read from it. So the table sweeps it rather than picking one, and the
smallest column is the honest worst case: a server that flushes every
few hundred bytes gets much less out of deflate than one that hands
over a whole frame.

  tools/sshzlib.py                    every capture
  tools/sshzlib.py captures/LIVE      just that one

Upstream traffic is not modelled. Keystrokes pay the framing in full -
36 bytes on the wire for one key - and the client must also send
SSH_MSG_CHANNEL_WINDOW_ADJUST as it consumes its window. Both are
irrelevant at human typing rates and neither competes with the
downstream flow that this measures.
"""

import glob
import os
import sys
import zlib

# The ceiling from docs/full-screen-apps.md, measured while data flows.
CEILING = 4268

CHUNKS = (256, 1024, 4096)


def framed(payload, packets):
    """Wire bytes for `packets` packets carrying `payload` bytes in total.

    Padding is charged at its average of 4 bytes over the 4..11 range a
    uniform payload length produces, rather than computed per packet:
    the per-packet payload is not knowable from a byte stream, only its
    total, and 4 is what the average of a min-4 pad to 8 comes to.
    """
    per = 4 + 1 + 9 + 4 + 16     # length, padlen, CHANNEL_DATA, pad, tag
    return payload + packets * per


def sim(data, chunk):
    """Stream `data` through deflate in `chunk`-sized packets."""
    co = zlib.compressobj(6, zlib.DEFLATED, 15, 8)
    out = 0
    packets = 0
    for i in range(0, len(data), chunk):
        out += len(co.compress(data[i:i + chunk]))
        out += len(co.flush(zlib.Z_SYNC_FLUSH))
        packets += 1
    return out, packets


def report(path):
    with open(path, "rb") as f:
        data = f.read()
    if not data:
        print(f"{os.path.basename(path)}: empty")
        return

    raw = len(data)
    print(f"{os.path.basename(path)}  {raw} bytes  "
          f"{raw / CEILING:.1f}s at the {CEILING} byte/sec ceiling")
    print("  packet   telnet    SSH plain      SSH + zlib      seconds saved")
    for chunk in CHUNKS:
        comp, packets = sim(data, chunk)
        plain = framed(raw, packets)
        small = framed(comp, packets)
        print(f"  {chunk:6d}  {raw:7d}  {plain:7d} {plain / raw:5.2f}x  "
              f"{small:7d} {small / raw:5.2f}x  "
              f"{(raw - small) / CEILING:12.1f}")
    print()


def main(argv):
    paths = argv[1:]
    if not paths:
        # .grid files are rendered screens, not byte streams - they are
        # not what crosses the wire and compressing them means nothing.
        paths = sorted(p for p in glob.glob("captures/*")
                       if not p.endswith(".grid"))
    if not paths:
        print("no captures found", file=sys.stderr)
        return 1
    for path in paths:
        report(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
