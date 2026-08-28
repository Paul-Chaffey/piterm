#!/bin/bash
# Login shell for PTERM, served over socat's pty.
#
# A FILE, not an inline SYSTEM: address, for the same reason as feed.sh:
# three socat commands in this project have died with "exactly 2
# addresses required" because the shell split a quoted address before
# socat ever saw it. A path has no spaces and needs no quotes.
#
# stty is needed because socat is a raw TCP-to-pty bridge, not a telnet
# server - it never negotiates, so PTERM's NAWS is not answered and the
# far end would otherwise assume 80x24 (specification.md 3.5).
stty rows 64 cols 80
export TERM=xterm-256color
exec /bin/bash -l
