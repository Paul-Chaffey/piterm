#!/bin/bash
# Set up a Samba share that the BBC Master's LANMANFS can mount.
#
#   sudo bash tools/setup-samba.sh
#
# SECURITY NOTE - read before running.
# The Sprow module dates from ~2009 and speaks SMB1/NetBIOS with old-style
# authentication. Modern Samba disables all of that by default because it is
# insecure. This config deliberately re-enables SMB1, NTLMv1 and LANMAN auth,
# and shares a directory with guest access. That is a real weakening of this
# host's security. Only do it on a trusted LAN, and undo it when finished
# (instructions at the bottom of this file).

set -e
SHARE=$REPO/share
BEEB=192.0.2.20

echo "== installing samba"
DEBIAN_FRONTEND=noninteractive apt-get install -y samba >/dev/null

echo "== backing up existing config"
if [ -f /etc/samba/smb.conf ] && [ ! -f /etc/samba/smb.conf.orig ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.orig
    echo "   saved /etc/samba/smb.conf.orig"
fi

echo "== writing config"
cat > /etc/samba/smb.conf <<'CONF'
[global]
   workgroup = WORKGROUP
   server string = BBC Master file server
   security = user
   map to guest = Bad User
   guest account = user

   # --- required for the 2009-era Sprow module ---
   server min protocol = NT1
   client min protocol = NT1
   ntlm auth = ntlmv1-permitted
   lanman auth = yes
   client lanman auth = yes
   raw NTLMv2 auth = yes
   disable netbios = no
   smb ports = 139 445

   log file = /var/log/samba/log.%m
   max log size = 1000

[beeb]
   comment = BBC Master share
   path = $REPO/share
   browseable = yes
   writable = yes
   guest ok = yes
   force user = user
   create mask = 0664
   directory mask = 0775
CONF

echo "== validating config"
testparm -s >/dev/null

echo "== permissions"
chmod 775 "$SHARE"

echo "== firewall: allow SMB from the Beeb only"
ufw allow from $BEEB to any port 139 proto tcp >/dev/null || true
ufw allow from $BEEB to any port 445 proto tcp >/dev/null || true
ufw allow from $BEEB to any port 137 proto udp >/dev/null || true
ufw allow from $BEEB to any port 138 proto udp >/dev/null || true

echo "== restarting services"
systemctl enable --now smbd nmbd >/dev/null 2>&1 || true
systemctl restart smbd nmbd

echo
echo "done. share 'beeb' -> $SHARE"
systemctl is-active smbd nmbd || true

# ---------------------------------------------------------------------------
# To undo all of this when you no longer need it:
#
#   sudo systemctl disable --now smbd nmbd
#   sudo cp /etc/samba/smb.conf.orig /etc/samba/smb.conf
#   sudo ufw delete allow from 192.0.2.20 to any port 139 proto tcp
#   sudo ufw delete allow from 192.0.2.20 to any port 445 proto tcp
#   sudo ufw delete allow from 192.0.2.20 to any port 137 proto udp
#   sudo ufw delete allow from 192.0.2.20 to any port 138 proto udp
# ---------------------------------------------------------------------------
