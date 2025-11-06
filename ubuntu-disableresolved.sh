#!/usr/bin/env bash
set -euo pipefail

# Option 2: Disable systemd-resolved entirely on Ubuntu 24.x
# - Disables/stops the resolver
# - Replaces /etc/resolv.conf with a static file
# - Verifies that port 53 is free

# Change these to your preferred upstream resolvers
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-1.0.0.1}"
DNS3="${DNS3:-9.9.9.9}"

echo "[*] Disabling systemd-resolved service..."
if systemctl is-enabled systemd-resolved >/dev/null 2>&1; then
  sudo systemctl disable --now systemd-resolved
else
  sudo systemctl stop systemd-resolved || true
fi

echo "[*] Backing up existing /etc/resolv.conf (if present)..."
if [ -e /etc/resolv.conf ]; then
  TS=$(date +%Y%m%d-%H%M%S)
  sudo cp -a /etc/resolv.conf "/etc/resolv.conf.bak-${TS}"
fi

echo "[*] Writing static /etc/resolv.conf with upstream DNS servers..."
sudo rm -f /etc/resolv.conf
sudo tee /etc/resolv.conf >/dev/null <<EOF
# Static resolv.conf installed by disable-systemd-resolved script
# Adjust DNS servers to your environment if needed.
nameserver ${DNS1}
nameserver ${DNS2}
nameserver ${DNS3}
options edns0
EOF

echo "[*] Ensuring NetworkManager won't re-point resolv.conf to systemd-resolved..."
# If NetworkManager is present and uses systemd-resolved, switch it to default
if systemctl is-active NetworkManager >/dev/null 2>&1; then
  sudo mkdir -p /etc/NetworkManager/conf.d
  sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null <<'EOF'
[main]
dns=default
EOF
  sudo systemctl reload NetworkManager || sudo systemctl restart NetworkManager
fi

echo "[*] Verifying DNS resolution works with the new resolv.conf..."
getent hosts example.com >/dev/null || {
  echo "[!] DNS lookup failed via static resolv.conf. Check your upstream DNS entries." >&2
  exit 1
}

echo "[*] Checking that port 53 is free..."
if ss -lntup | grep -qE '(:53\s)'; then
  echo "[!] Port 53 still appears occupied. Current listeners:" >&2
  ss -lntup | grep -E '(:53\s)' || true
  echo "[!] Investigate other software binding 53 (e.g., dnsmasq, bind9). Aborting." >&2
  exit 1
fi

echo "[*] Success. systemd-resolved is disabled and port 53 is free."
echo "[*] You can now start AdGuard Home with docker compose."
