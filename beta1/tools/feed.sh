#!/bin/bash
# Feeder for FBCOST: a lot to say, and a definite end.
#
# Called as socat's EXEC: target. It is a FILE rather than an inline
# SYSTEM: address on purpose - two socat commands in this project have
# already failed with "exactly 2 addresses required" because the shell
# split a quoted address before socat ever saw it. A path has no spaces
# and needs no quotes, and the shebang supplies the shell that EXEC:
# does not (specification.md 3.5).
#
# yes' stderr is dropped because head closing the pipe makes it print
# "Broken pipe", which is correct behaviour that reads like a fault.
yes ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 2>/dev/null | head -c 900000
