#!/bin/sh
# Mirror BASIC sources into the Samba share the Beeb mounts.
#
#   tools/mirror.sh                 mirror everything in test/ and src/
#   tools/mirror.sh test/foo.bas    mirror just that
#   tools/mirror.sh --tok src/x.bas TOKENISED, for CHAIN instead of *EXEC
#   tools/mirror.sh --dir CMOS a.bas b.bas   into the share subfolder CMOS
#
# --dir puts the files in a subfolder of the share instead of its root, so
# a subproject's files travel together and the Beeb reaches them with a
# *DIR. The folder name obeys the same rule the file names do - 8 characters
# or fewer, because LANManFS truncates a longer one silently and two folders
# can then be the same folder. --dir needs an explicit file list; it will
# not mirror the whole of test/ and src/ into one subfolder.
#
# NAMES COLLIDE SILENTLY between the two modes: mirror.sh --tok src/x.bas
# and mirror.sh test/x.bas both write share/X, and whichever ran last wins.
# A tokenised build overwritten by text still LOADs and then fails somewhere
# unrelated. Give a combined build its own name.
#
# --tok writes the file BASIC would have built for itself, so the machine
# does not have to: *EXEC feeds text through the input stream a character
# at a time, and CHAIN reads a tokenised file at the 14 KB/sec measured in
# specification.md 6.4 - about three seconds for the whole engine. The
# output is verified byte-identical to the machine's own SAVE, see
# tools/bastok-diff.py. A tokenised file must be CHAINed, NOT *EXECed.
#
# Two rules, both of which fail SILENTLY on the machine if broken, which is
# why this exists rather than a cp:
#
#  1. CR (&0D) line endings, not LF. *EXEC on an LF-terminated file finds no
#     line terminator at all, pours the whole file into a 238-byte input
#     buffer and locks the machine up. Cost an evening on 2026-08-19.
#  2. Uppercase names of 8 characters or fewer. Longer names are truncated by
#     the filing system, so two sources can collide - checked for below.
#
# See specification.md 2.5.

set -e
here=$(cd "$(dirname "$0")/.." && pwd)
share=$here/share

tok=""
dir=""
while :; do
    case "$1" in
        --tok) tok=1; shift ;;
        --dir) dir=$2
               if [ -z "$dir" ]; then
                   echo "--dir needs a folder name" >&2
                   exit 1
               fi
               case "$dir" in
                   *[!A-Za-z0-9-]*)
                       echo "refusing --dir $dir: letters, digits and - only" >&2
                       exit 1 ;;
               esac
               if [ "${#dir}" -gt 8 ]; then
                   echo "refusing --dir $dir: over 8 characters, LANManFS truncates" >&2
                   exit 1
               fi
               shift 2 ;;
        *) break ;;
    esac
done

if [ -n "$dir" ]; then
    if [ $# -eq 0 ]; then
        echo "--dir needs an explicit file list" >&2
        exit 1
    fi
    share=$share/$dir
    mkdir -p "$share"
fi

if [ $# -gt 0 ]; then
    set -- "$@"
else
    set -- "$here"/test/*.bas "$here"/src/*.bas
fi

seen=""
for src in "$@"; do
    base=$(basename "$src" .bas)
    name=$(echo "$base" | tr '[:lower:]' '[:upper:]' | cut -c1-8)

    case " $seen " in
        *" $name "*)
            echo "refusing $src: name collides with an earlier file at $name" >&2
            exit 1 ;;
    esac
    seen="$seen $name"

    if [ -n "$tok" ]; then
        python3 "$here/tools/bastok.py" "$src" "$share/$name" >/dev/null
        printf '%-14s <- %-24s %6s bytes  CHAIN "%s"\n' \
            "$name" "${src#$here/}" "$(wc -c < "$share/$name")" "$name"
        continue
    fi

    # Refuse to overwrite a TOKENISED file with text. bastok.py and this
    # write the same share name from different sources and whichever ran
    # last wins - a tokenised build replaced by text still loads and then
    # answers "Bad program". A tokenised program starts 0D 00.
    if [ -f "$share/$name" ] && [ "$(head -c2 "$share/$name" | od -An -tx1 | tr -d ' ')" = "0d00" ]; then
        echo "refusing $src: $share/$name is a TOKENISED build" >&2
        echo "  rebuild it with tools/bastok.py, or delete it first" >&2
        exit 1
    fi

    tr '\n' '\r' < "$src" > "$share/$name"

    # Prove it, rather than trusting the tr above. Only the files written
    # here are checked - ARCADE and the disc images are binaries, and an
    # 0x0A inside them is data, not a line ending.
    lf=$(tr -dc '\n' < "$share/$name" | wc -c)
    cr=$(tr -dc '\r' < "$share/$name" | wc -c)
    if [ "$lf" -ne 0 ] || [ "$cr" -eq 0 ]; then
        echo "$name: still LF-terminated (LF=$lf CR=$cr)" >&2
        exit 1
    fi

    printf '%-14s <- %-24s %4s lines\n' "$name" "${src#$here/}" "$cr"
done
