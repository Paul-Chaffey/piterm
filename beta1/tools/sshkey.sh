#!/bin/bash
# The Beeb's own SSH key, and the raw form the blob can read.
#
#   tools/sshkey.sh              make the key if absent, write it to the share
#
# A SEPARATE KEY, not ~/.ssh/id_ed25519. The private half has to sit on a
# Samba share that a 40-year-old computer mounts with no authentication worth
# the name, so it should be a key that can be revoked on its own and that
# opens only what you choose to let it open. Reusing your everyday key would
# put it in the same place with none of those properties.
#
# The share form is RAW, not OpenSSH's container: 32 bytes of public key
# followed by the 32-byte private seed, 64 bytes exactly. Parsing base64 and
# a nested length-prefixed structure in BBC BASIC would be a page of code to
# no purpose - the conversion belongs on the machine that has Python.
#
# Add the printed line to authorized_keys on every machine the Beeb should
# reach. Restricting it there is worth doing:
#
#   restrict,pty,command="..."  ssh-ed25519 AAAA... piterm

set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
key="${PITERM_KEY:-$HOME/.ssh/piterm_ed25519}"
share="$here/share/Pi-TERM"

if [ ! -f "$key" ]; then
    echo "sshkey: generating $key"
    ssh-keygen -t ed25519 -N "" -C "piterm" -f "$key" >/dev/null
fi

[ -d "$share" ] || { echo "sshkey: $share does not exist" >&2; exit 1; }

python3 - "$key" "$share/SSHKEY" <<'EOF'
import base64, struct, sys

path, out = sys.argv[1], sys.argv[2]
text = open(path).read()
body = text.split("-----BEGIN OPENSSH PRIVATE KEY-----")[1]
body = body.split("-----END OPENSSH PRIVATE KEY-----")[0]
raw = base64.b64decode("".join(body.split()))

assert raw[:15] == b"openssh-key-v1\0", "not an openssh-key-v1 container"
off = 15

def s():
    global off
    n, = struct.unpack(">I", raw[off:off + 4])
    off += 4 + n
    return raw[off - n:off]

cipher = s()
assert cipher == b"none", "the key has a passphrase; the Beeb cannot ask for one"
s()                     # kdfname
s()                     # kdfoptions
off += 4                # key count
s()                     # public blob
off += 4                # private section length
off += 8                # the two check integers
s()                     # key type
pub = s()
priv = s()
assert len(pub) == 32 and len(priv) == 64, "not an ed25519 key"
assert priv[32:] == pub, "the private key's public half does not match"

with open(out, "wb") as f:
    f.write(pub + priv[:32])
print(f"sshkey: wrote {out}, 64 bytes (32 public + 32 seed)")
EOF

echo
echo "Add this to authorized_keys wherever the Beeb should be able to log in:"
echo
sed 's/^/  /' "$key.pub"
echo
echo "The private half is now on the share. Treat the share accordingly."
