#!/usr/bin/env bash
set -euo pipefail

# Install Docker Engine on Ubuntu using the official Docker apt repo.
# Includes: service enable/start, add user to docker group, immediate newgrp, verification tests, and rollback.

ROLLBACK_STEPS=()

log() { echo "[*] $*"; }
warn() { echo "[!] $*" >&2; }
fail() { echo "[x] $*" >&2; exit 1; }

# Track a rollback action
add_rollback() { ROLLBACK_STEPS+=("$*"); }

run_rollbacks() {
  if [ "${#ROLLBACK_STEPS[@]}" -gt 0 ]; then
    warn "Running rollback steps..."
    for cmd in "${ROLLBACK_STEPS[@]}"; do
      bash -c "$cmd" || true
    done
  fi
}

trap 'warn "An error occurred."; run_rollbacks' ERR

UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
ARCH="$(dpkg --print-architecture)"
APT_KEYRING="/etc/apt/keyrings/docker.asc"
REPO_LIST="/etc/apt/sources.list.d/docker.list"

log "Uninstalling conflicting packages (safe if none exist)..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  if dpkg -l | awk '{print $2}' | grep -qx "$pkg"; then
    add_rollback "apt-get install -y $pkg"
  fi
  apt-get -y remove "$pkg" >/dev/null 2>&1 || true
done
# Not removing /var/lib/docker to preserve existing data.

log "Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

log "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
if [ -f "$APT_KEYRING" ]; then
  add_rollback "cp -a $APT_KEYRING ${APT_KEYRING}.rollback && mv -f ${APT_KEYRING}.rollback $APT_KEYRING"
fi
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${APT_KEYRING}"
chmod a+r "${APT_KEYRING}"

log "Adding Docker apt repository (${UBUNTU_CODENAME}, ${ARCH})..."
if [ -f "$REPO_LIST" ]; then
  add_rollback "cp -a $REPO_LIST ${REPO_LIST}.rollback && mv -f ${REPO_LIST}.rollback $REPO_LIST"
fi
cat >"$REPO_LIST" <<EOF
deb [arch=${ARCH} signed-by=${APT_KEYRING}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF

log "Updating apt metadata..."
apt-get update -y

log "Installing Docker Engine, CLI, containerd, Buildx, Compose plugin..."
add_rollback "apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras"
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Enabling and starting Docker service..."
systemctl enable --now docker
# Roll back service enable/start if needed
add_rollback "systemctl disable --now docker || true"

# Verification: service status
if ! systemctl is-active --quiet docker; then
  fail "Docker service failed to start."
fi

# Post-install: group membership
TARGET_USER="${SUDO_USER:-${USER}}"
log "Adding user '${TARGET_USER}' to 'docker' group..."
groupadd -f docker
# Capture whether the user was already in the group
if id -nG "${TARGET_USER}" | tr ' ' '\n' | grep -qx docker; then
  PREEXISTING_GROUP=true
else
  PREEXISTING_GROUP=false
fi
usermod -aG docker "${TARGET_USER}" || warn "Could not add ${TARGET_USER} to docker group."

# Rollback for group change (best-effort): remove user from docker group if it was not previously a member
if [ "${PREEXISTING_GROUP}" = "false" ]; then
  add_rollback "gpasswd -d ${TARGET_USER} docker || true"
fi

# Immediate group refresh for current shell if we are the target user and running interactively
log "Refreshing group membership in current shell with 'newgrp docker' (best-effort)..."
# Only attempt if script is run interactively on TTY and the target is the invoking user
if [ -t 1 ] && [ "${TARGET_USER}" = "${USER}" ]; then
  # Start a subshell to avoid disrupting this script's environment
  newgrp docker <<'EONG'
echo "[*] 'newgrp docker' session started."
exit
EONG
else
  warn "Skipping 'newgrp docker' (non-interactive or different SUDO_USER); log out/in or run 'newgrp docker' manually."
fi

# Functional verification tests
log "Running hello-world test (may still require sudo if group cache not refreshed)..."
if docker run --rm hello-world >/dev/null 2>&1; then
  log "hello-world ran successfully without sudo."
else
  warn "hello-world failed without sudo; trying with sudo..."
  if sudo docker run --rm hello-world >/dev/null 2>&1; then
    log "hello-world ran successfully with sudo."
  else
    warn "hello-world failed even with sudo. Collecting diagnostics..."
    systemctl --no-pager status docker || true
    journalctl -u docker --no-pager -n 100 || true
    fail "Docker daemon not responding properly."
  fi
fi

# Compose plugin verification
log "Checking docker compose plugin..."
if docker compose version >/dev/null 2>&1; then
  log "docker compose plugin is available."
else
  warn "docker compose plugin not found; attempting to reinstall compose plugin..."
  apt-get install -y docker-compose-plugin || warn "Reinstall of compose plugin failed."
fi

# Print firewall and DOCKER-USER guidance
cat <<'NOTE'

[INFO] Firewall behavior:
- Published container ports bypass ufw/firewalld zone rules by default. Place filtering rules in the DOCKER-USER chain, which Docker preserves. See Docker docs on packet filtering and firewalls.

[INFO] Optional DOCKER-USER baseline:
- You can seed a default RETURN rule (accept) and add your own allows/denies ahead of it:

  sudo iptables -C DOCKER-USER -j RETURN 2>/dev/null || sudo iptables -I DOCKER-USER -j RETURN
  sudo ip6tables -C DOCKER-USER -j RETURN 2>/dev/null || sudo ip6tables -I DOCKER-USER -j RETURN

NOTE

log "Installation complete. If you still need non-sudo access, run: newgrp docker"
