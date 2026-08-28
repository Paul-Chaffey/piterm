#!/bin/bash
# Destination picker for PTERM, served over socat's pty.
#
# The problem this solves is in specification.md 3.5: the BBC speaks
# cleartext telnet, so a password typed at the Beeb to log in to a
# further machine crosses the LAN in the clear. This moves the
# authentication to the gateway, which has a key. The Beeb chooses WHO
# to talk to; it never proves who it is.
#
#   -o PasswordAuthentication=no
#   -o KbdInteractiveAuthentication=no
#
# Those two are the whole point and must not be relaxed. Without them a
# target that refuses the key falls back to asking for a password, and
# the prompt appears on the Beeb - which puts the credential back on the
# wire, silently, at exactly the moment nobody is looking for it. With
# them, a target that will not take the key fails and says so.
#
# A FILE, not an inline SYSTEM: address, for the same reason as
# shell.sh and feed.sh: three socat commands in this project have died
# with "exactly 2 addresses required" because the shell split a quoted
# address before socat ever saw it.
#
# Host list: $PITERM_HOSTS, or gate.hosts beside this script. One
# destination per line, "label  target", where target is an ssh
# destination or "-" for a shell on the gateway itself.
#
# Started by tools/sshgate.sh, which owns the listener and the two
# restrictions that keep it off the rest of the network.

# socat is a raw TCP-to-pty bridge, not a telnet server - it never
# negotiates, so PTERM's NAWS is not answered and the far end would
# otherwise assume 80x24 (specification.md 3.5). ssh reads the size
# from this pty and passes it on, so setting it here covers both legs.
stty rows 64 cols 80
export TERM=xterm-256color

hosts="${PITERM_HOSTS:-$(dirname "$0")/gate.hosts}"

labels=()
targets=()
if [ -r "$hosts" ]; then
    while read -r label target rest; do
        case "$label" in ''|'#'*) continue ;; esac
        [ -n "$target" ] || continue
        labels+=("$label")
        targets+=("$target")
    done < "$hosts"
fi

if [ ${#labels[@]} -eq 0 ]; then
    echo "No destinations in $hosts - falling back to a shell here."
    exec /bin/bash -l
fi

# The menu is redrawn on a bad answer rather than nagging on one line,
# because 80x64 has room and a Beeb user cannot scroll back.
while true; do
    echo
    echo "PiTerm gateway on $(hostname) - authenticated with this machine's key"
    echo
    for i in "${!labels[@]}"; do
        if [ "${targets[$i]}" = "-" ]; then
            printf '  %d  %-12s a shell here\n' "$((i + 1))" "${labels[$i]}"
        else
            printf '  %d  %-12s %s\n' "$((i + 1))" "${labels[$i]}" "${targets[$i]}"
        fi
    done
    echo "  q  quit"
    echo
    printf 'where? '

    # EOF means PTERM dropped the connection; without this test the
    # loop spins forever printing the menu into a closed socket.
    read -r answer || exit 0

    answer="${answer%%[[:space:]]*}"
    pick=-1
    case "$answer" in
        q|Q|quit) exit 0 ;;
        '') continue ;;
        *[!0-9]*)
            for i in "${!labels[@]}"; do
                [ "$answer" = "${labels[$i]}" ] && pick=$i
            done
            ;;
        *)
            [ "$answer" -ge 1 ] 2>/dev/null && [ "$answer" -le ${#labels[@]} ] \
                && pick=$((answer - 1))
            ;;
    esac

    if [ "$pick" -lt 0 ]; then
        echo "No such destination: $answer"
        continue
    fi

    target="${targets[$pick]}"
    if [ "$target" = "-" ]; then
        exec /bin/bash -l
    fi

    echo "Connecting to $target ..."
    # NOT exec, unlike the local shell above: logging out of the target
    # comes back to this menu, so a second machine costs a keypress
    # rather than a reconnect from the Beeb. Reconnecting means PTERM's
    # socket open, DNS and connect again, which is seconds.
    #
    # -tt because socat's pty is ours, not ssh's: without it ssh sees a
    # non-interactive parent for the second leg and no pty is allocated
    # on the target, which loses full-screen apps entirely.
    # ConnectTimeout because ssh's default wait for an unreachable host
    # is over two minutes, and PTERM has no way to show that anything is
    # happening - it looks exactly like the terminal having locked up,
    # which is a fault this project has spent real time chasing.
    ssh -tt \
        -o ConnectTimeout=10 \
        -o PasswordAuthentication=no \
        -o KbdInteractiveAuthentication=no \
        "$target"
    echo "$target: exit $?"

    # A full-screen program on the target that died without restoring
    # the terminal leaves this pty in raw mode, and then read -r never
    # sees a line and the menu is unusable. ssh normally restores it;
    # this is for when it did not.
    stty sane
    stty rows 64 cols 80
done
