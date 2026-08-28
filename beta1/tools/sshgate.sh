#!/bin/bash
# The listener PTERM connects to: a destination picker, not a login.
#
#   tools/sshgate.sh                    the Beeb only, on the LAN address
#   tools/sshgate.sh --allow 192.0.2.0/24
#   tools/sshgate.sh --port 2324 --hosts /path/to/list
#   tools/sshgate.sh --log FILE | --no-log   (default: results/RESGATE)
#
# This replaces the bare "socat ... SYSTEM:'exec /bin/bash -l'" of
# specification.md 3.5. Same transport, but what is served is
# tools/gate.sh, which offers a list of machines and reaches the chosen
# one with THIS machine's ssh key. Nothing the Beeb types is a
# credential, so nothing that crosses the LAN in the clear is one.
#
# WHAT THIS LISTENER IS. Anyone who connects to it gets a shell -
# either here or, through the key, on a machine in gate.hosts. There is
# no authentication on the near side and there cannot be, because
# authentication is the thing being kept off the wire. Two restrictions
# stand in for it and both are on by default:
#
#   bind=   one interface, chosen by which one reaches the Beeb. The
#           machine has a tailnet address (100.x.y.z) and an
#           unqualified listener would answer on it, which would put an
#           unauthenticated shell on the far side of the internet.
#   range=  one source address, the Beeb's. Without it every machine on
#           the LAN can use the gateway's key.
#
# --any removes the range restriction. It is a real decision, not a
# convenience, and it is why it has to be typed.
#
# Neither restriction is a substitute for shutting the listener down
# afterwards: "neither form should outlive the session it was started
# for" (specification.md 3.5) applies to this one too.
#
# IT LOGS, to results/RESGATE, and that is on by default for the reason
# ARMSPIKE grew a log on 2026-08-27: a run that records nothing cannot be
# committed as a finding, and opt-in recording does not get opted into.
# socat -d -d gives a timestamped line per connection, appended across
# runs, and two of its lines are worth the whole thing:
#
#   N accepting connection from AF=2 192.0.2.20:...
#   W refusing connection from AF=2 <addr> due to range option
#
# The second is the one to remember. A range rejection serves nothing and
# says nothing to the client, so from the Beeb it is indistinguishable
# from a dead listener - and the Beeb is on DHCP, so it WILL move one day.
# The log is what tells the two apart.
#
# It is socat's log, not the session's: it records that the Beeb
# connected and for how long, not which destination was chosen. gate.sh
# would have to write that itself.

set -eu

# The Beeb, as recorded in specification.md 5.6. DHCP, so it can move -
# if the connection is refused, check the address with *EMINFO on the
# Beeb before assuming the listener is broken.
BEEB=192.0.2.20

port=2323
allow="$BEEB/32"
bind=""
hosts=""
anyone=0

here="$(cd "$(dirname "$0")" && pwd)"
gate="$here/gate.sh"
# Beside the RES* files the Beeb writes, because it is the same kind of
# record: results/ is where a run goes to be kept.
logfile="$(dirname "$here")/results/RESGATE"

die() { echo "sshgate: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --port)  port="$2"; shift 2 ;;
        --bind)  bind="$2"; shift 2 ;;
        --allow) allow="$2"; shift 2 ;;
        --hosts) hosts="$2"; shift 2 ;;
        --any)   anyone=1; shift ;;
        --log)   logfile="$2"; shift 2 ;;
        --no-log) logfile=""; shift ;;
        -h|--help)
            sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die "unknown option $1" ;;
    esac
done

# socat splits its address string on commas and colons, so a path with a
# space in it becomes two options and the error names neither.
case "$gate" in
    *[[:space:]]*) die "path contains a space, which socat cannot parse: $gate" ;;
esac
[ -x "$gate" ] || die "$gate is not executable (chmod +x)"

# /bin/login is what needs root (specification.md 3.5) and this serves a
# picker instead, so root buys nothing and would hand every connection a
# root shell through the "-" entry.
[ "$(id -u)" -ne 0 ] || die "do not run this as root - it serves a shell"

# The key is the whole mechanism. Failing here beats failing per
# connection, where the message goes to the Beeb and looks like a
# network fault.
ls "$HOME"/.ssh/id_* >/dev/null 2>&1 \
    || echo "sshgate: WARNING - no key in ~/.ssh, every ssh destination will fail" >&2

if [ -z "$bind" ]; then
    # Ask the routing table which address reaches the Beeb rather than
    # picking the first global one: that is what keeps the tailnet
    # address out of it without having to name the interface.
    probe="${allow%%/*}"
    [ "$anyone" -eq 0 ] || probe="$BEEB"
    bind="$(ip -4 route get "$probe" 2>/dev/null \
            | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)"
    [ -n "$bind" ] || die "cannot work out which address reaches $probe - pass --bind"
fi

listen="TCP4-LISTEN:$port,reuseaddr,fork,bind=$bind"
if [ "$anyone" -eq 1 ]; then
    echo "sshgate: WARNING - --any: every host that can reach $bind:$port"
    echo "sshgate:           gets a shell, and this machine's key with it."
else
    listen="$listen,range=$allow"
fi

[ -z "$hosts" ] || export PITERM_HOSTS="$hosts"

sock=()
if [ -n "$logfile" ]; then
    mkdir -p "$(dirname "$logfile")" || die "cannot create the log directory"
    : >> "$logfile" || die "cannot write $logfile"
    # -d -d is notice level, which is where the accepting/refusing lines
    # live. -lf appends, so runs accumulate rather than overwrite.
    sock=(-d -d -lf "$logfile")
fi

echo "sshgate: listening on $bind:$port"
[ "$anyone" -eq 1 ] || echo "sshgate: accepting only $allow"
echo "sshgate: serving $gate (destinations: ${hosts:-$here/gate.hosts})"
[ -z "$logfile" ] || echo "sshgate: logging to $logfile"
[ -n "$logfile" ] || echo "sshgate: NOT logging - a run here will leave no trace"
echo "sshgate: ctrl-C to stop - do not leave it running"

exec socat "${sock[@]}" "$listen" "SYSTEM:$gate,pty,stderr,setsid,ctty"
