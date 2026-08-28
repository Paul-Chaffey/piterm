#!/usr/bin/env python3
"""Capture what a full-screen program actually sends, at a fixed size.

  tools/ptycap.py emu/vdfs/TOPCAP 32 79 4 top -d 1

Arguments: outfile rows cols seconds command...

Why this exists: the emulator has no socket module, so BEEBTERM cannot talk to
a real shell there - but the parser and renderer do not care where the bytes
came from. Capture a real session once, replay it in b-em with replay$ set, and
a rendering fault can be found without the hardware and without photographing a
monitor. Set the same rows/cols the Beeb will use, or the wrapping under test
is not the wrapping that happens.
"""
import fcntl, os, pty, signal, struct, sys, termios, time

if len(sys.argv) < 6:
    sys.exit(__doc__)
out, rows, cols, secs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
cmd = sys.argv[5:]

pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["LINES"], os.environ["COLUMNS"] = str(rows), str(cols)
    os.execvp(cmd[0], cmd)

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
buf = b""
end = time.time() + secs
while time.time() < end:
    try:
        r = os.read(fd, 4096)
    except OSError:
        break
    if not r:
        break
    buf += r
os.write(fd, b"q")
time.sleep(0.5)
try:
    buf += os.read(fd, 65536)
except OSError:
    pass
os.kill(pid, signal.SIGTERM)
os.waitpid(pid, 0)
open(out, "wb").write(buf)
print(f"{len(buf)} bytes -> {out}  ({rows}x{cols}, {secs}s of {' '.join(cmd)})")
