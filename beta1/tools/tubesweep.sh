#!/bin/sh
# tubesweep.sh - set tube_delay on the PiTubeDirect card for the next point.
#
# tube_delay is read once at boot and handed to the VideoCore, and NO * command
# exposes it (see specification.md 2.5), so every sweep point costs a card swap
# and a reboot. This exists so that swap does not also cost a decision.
#
#   tools/tubesweep.sh          advance to the next value in the coarse sweep
#   tools/tubesweep.sh 25       set a specific value
#   tools/tubesweep.sh -s       show the current value and stop
#
# Only the tube_delay token is touched. copro=15 and vdu=1 are left alone -
# vdu=1 is NOT the default and FBVDU cannot work without it.

set -e
LABEL=IB1_M
SWEEP="0 5 10 15 20 25 30 35 40"

dev=$(lsblk -rno NAME,LABEL | awk -v l="$LABEL" '$2==l{print "/dev/"$1; exit}')
[ -n "$dev" ] || { echo "no partition labelled $LABEL - is the card in?" >&2; exit 1; }

mnt=$(findmnt -rno TARGET "$dev" 2>/dev/null || true)
if [ -z "$mnt" ]; then
    udisksctl mount -b "$dev" >/dev/null
    mnt=$(findmnt -rno TARGET "$dev")
    weMounted=1
fi
f="$mnt/cmdline.txt"
[ -f "$f" ] || { echo "no cmdline.txt on $mnt" >&2; exit 1; }

cur=$(tr ' ' '\n' < "$f" | sed -n 's/^tube_delay=//p')
[ -n "$cur" ] || { echo "no tube_delay in cmdline.txt" >&2; exit 1; }

if [ "$1" = "-s" ]; then
    echo "tube_delay=$cur"
    cat "$f"; echo
    [ -n "$weMounted" ] && udisksctl unmount -b "$dev" >/dev/null
    exit 0
fi

if [ -n "$1" ]; then
    next=$1
else
    # first sweep value strictly greater than the current one; wrap to the first
    next=$(for v in $SWEEP; do [ "$v" -gt "$cur" ] && { echo "$v"; break; }; done)
    [ -n "$next" ] || next=$(echo $SWEEP | cut -d' ' -f1)
fi

case "$next" in *[!0-9]*) echo "tube_delay must be a number, got '$next'" >&2; exit 1;; esac
[ "$next" -le 40 ] || { echo "tube_delay is clamped to 40 in tube-client.c" >&2; exit 1; }

sed -i "s/tube_delay=$cur/tube_delay=$next/" "$f"
sync
echo "tube_delay $cur -> $next"
cat "$f"; echo
sync
udisksctl unmount -b "$dev" >/dev/null
echo
# printf with a single-quoted format, because echo eats the backslashes in the
# UNC path and hands the operator a command that cannot work.
printf '%s\n' 'Card is safe to remove. On the Beeb:'
printf '%s\n' '  CTRL-BREAK'
printf '%s\n' '  *ARMBASIC'
printf '%s\n' '  *MOUNT \\192.0.2.10\beeb'
printf '%s\n' '  *DIR Pi-TERM'
printf '%s%s\n' '  CHAIN "TUBECRC"   and answer ' "$next"
