#!/usr/bin/env python3
"""BEEBLINK host side - command channel to a real BBC Master.

The BBC connects OUT to us (test/beeblink.bas), so start this first.

  tools/beeblink.py                      interactive, reads commands from stdin
  tools/beeblink.py --fifo /tmp/bbc.in   read commands from a FIFO (scriptable)

Commands sent to the Beeb:
  *cmd    run as OSCLI on the BBC
  $expr   evaluate as a string expression, result returned
  expr    evaluate as a numeric expression, result returned

Development tool: plaintext, LAN only, and it executes what it is sent.
"""
import argparse
import os
import socket
import sys
import threading

CR = b"\r\n"   # CR alone leaves the BBC cursor on the same line


def reader(sock, logf):
    """Print everything the Beeb sends back."""
    buf = b""
    while True:
        try:
            data = sock.recv(256)
        except OSError:
            break
        if not data:
            break
        buf += data
        while b"\n" in buf or b"\r" in buf:
            i = min((buf.index(c) for c in (b"\n", b"\r") if c in buf))
            line, buf = buf[:i], buf[i + 1:].lstrip(b"\r\n")
            text = line.decode("latin-1").rstrip()
            if text:
                print(f"<< {text}", flush=True)
                if logf:
                    logf.write(text + "\n")
                    logf.flush()
    print("-- beeb closed the connection", flush=True)


def commands(path):
    """Yield command lines from a FIFO (reopened each time) or stdin."""
    if not path:
        for line in sys.stdin:
            yield line.rstrip("\n")
        return
    if not os.path.exists(path):
        os.mkfifo(path)
    print(f"-- reading commands from {path}", flush=True)
    while True:
        with open(path) as f:
            for line in f:
                yield line.rstrip("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=6502)
    ap.add_argument("--fifo")
    ap.add_argument("--log")
    args = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.bind, args.port))
    srv.listen(1)
    print(f"-- listening on {args.bind}:{args.port}, waiting for the Beeb",
          flush=True)

    logf = open(args.log, "a") if args.log else None

    # Accept repeatedly: the Beeb will be re-RUN many times during
    # development, and a one-shot accept made every reconnect fail silently.
    holder = {"sock": None, "queue": []}

    def acceptor():
        while True:
            sock, addr = srv.accept()
            print(f"-- connected from {addr[0]}:{addr[1]}", flush=True)
            old = holder["sock"]
            holder["sock"] = sock
            # Flush anything queued while nothing was connected. This lets a
            # BLOCKING Socket_Recv on the Beeb return immediately instead of
            # hanging with the escape key disabled.
            for q in holder["queue"]:
                print(f">> {q}  (queued)", flush=True)
                try:
                    sock.sendall(q.encode("latin-1") + CR)
                except OSError:
                    pass
            holder["queue"] = []
            if old:
                try:
                    old.close()
                except OSError:
                    pass
            threading.Thread(target=reader, args=(sock, logf),
                             daemon=True).start()

    threading.Thread(target=acceptor, daemon=True).start()

    try:
        for cmd in commands(args.fifo):
            if not cmd:
                continue
            sock = holder["sock"]
            if sock is None:
                holder["queue"].append(cmd)
                print(f"-- queued until the beeb connects: {cmd}", flush=True)
                continue
            print(f">> {cmd}", flush=True)
            try:
                sock.sendall(cmd.encode("latin-1") + CR)
            except OSError as e:
                # Drop the dead socket so later commands queue for the next
                # connection instead of vanishing into a broken pipe.
                print(f"-- send failed ({e}); queueing instead", flush=True)
                holder["sock"] = None
                holder["queue"].append(cmd)
    except KeyboardInterrupt:
        pass
    finally:
        if logf:
            logf.close()


if __name__ == "__main__":
    main()
