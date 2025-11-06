#!/usr/bin/env bash
set -euo pipefail

# Installs Docker Engine on Ubuntu using the official repository
# and applies recommended Linux post-install steps.

UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
ARCH="$(dpkg --print-architecture)"
APT_KEYRING="/etc/apt/keyrings/docker.asc"
REPO_LIST="/etc/apt/sources.list.d/docker.list"

echo "[*] Uninstalling conflicting packages (safe if none exist)..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get -y remove "$pkg" >/dev/null 2>&1 || true
done

echo "[*] Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

echo "[*] Adding Docker’s official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${APT_KEYRING}"
chmod a+r "${APT_KEYRING}"

echo "[*] Adding Docker apt repository for ${UBUNTU_CODENAME} (${ARCH})..."
cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=${APT_KEYRING}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF

echo "[*] Updating apt metadata..."
apt-get update -y

echo "[*] Installing Docker Engine, CLI, containerd, Buildx and Compose plugin..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[*] Enabling and starting Docker service..."
systemctl enable --now docker

echo "[*] Creating 'docker' group if needed and adding user '${SUDO_USER:-${USER}}' to it..."
groupadd -f docker
usermod -aG docker "${SUDO_USER:-${USER}}" || true

echo "[*] Verifying Docker is running..."
systemctl --no-pager status docker || true

echo "[*] Running hello-world (may require newgrp/relogin if not using sudo)..."
if sudo -n true 2>/dev/null; then
  # Run hello-world through sudo to avoid group caching issues
  sudo docker run --rm hello-world || true
else
  docker run --rm hello-world || true
fi

echo
echo "[*] Post-install notes:"
echo " - To use docker without sudo in this shell: run 'newgrp docker' or log out/in."
echo " - Docker-published ports bypass ufw/firewalld zone rules by default; prefer DOCKER-USER chain for filtering."
echo " - See: Packet filtering and firewalls and Linux post-install docs."
echo

echo "[*] Optional: create DOCKER-USER baseline policy (only if you plan to add your own firewall rules)."
read -r -p "Create a default-accept DOCKER-USER chain now? [y/N]: " ANS
if [[ "${ANS:-N}" =~ ^[Yy]$ ]]; then
  iptables -C DOCKER-USER -j RETURN 2>/dev/null || iptables -I DOCKER-USER -j RETURN
  ip6tables -C DOCKER-USER -j RETURN 2>/dev/null || ip6tables -I DOCKER-USER -j RETURN
  echo "   Added DOCKER-USER default RETURN rule. Insert your restrictions before this line as needed."
fi

echo "[*] Done. Reboot or re-login may be required for group membership to take effect."
