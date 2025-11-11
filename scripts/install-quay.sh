#!/usr/bin/env bash
set -euo pipefail

# ---- repo-aware paths ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
QUAY_ROOT="${REPO_ROOT}/quay"

# ---- files/dirs ----
COMPOSE_FILE="${QUAY_ROOT}/docker-compose.yml"
CONFIG_TOML="${QUAY_ROOT}/config/config.toml"
ENV_FILE="${QUAY_ROOT}/.env"
INIT_SQL="${QUAY_ROOT}/db/init/00-extensions.sql"

# ---- docker/network ----
NETWORK_NAME="lab_nw"
NETWORK_SUBNET="172.18.0.0/24"

# ---- quay admin bootstrap ----
QUAY_CONTAINER_NAME="quay"
QUAY_ADMIN_USER="quayadmin"
QUAY_ADMIN_PASS="quayadmin"
QUAY_ADMIN_EMAIL="quayadmin@local"
HEALTH_TIMEOUT_SECS=600

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
die() { echo "❌ $*"; exit 1; }

echo "🔎 Preflight checks..."
need docker
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  die "Docker Compose v2 (plugin) or legacy docker-compose is required."
fi

[[ -f "$COMPOSE_FILE" ]] || die "Compose not found: $COMPOSE_FILE"
mkdir -p "${QUAY_ROOT}/config" "${QUAY_ROOT}/storage" "${QUAY_ROOT}/db/data" "${QUAY_ROOT}/db/init" "${QUAY_ROOT}/redis/data" "${REPO_ROOT}/docker/nginx-pm" || true

# .env for nginx-pm image variables
if [[ ! -f "$ENV_FILE" ]]; then
cat > "$ENV_FILE" <<EOF
PUID=$(id -u)
PGID=$(id -g)
TZ=Asia/Singapore
EOF
  echo "📝 Wrote ${ENV_FILE}"
fi

# Ensure postgres extensions init file exists (safe if already present)
if [[ ! -f "$INIT_SQL" ]]; then
cat > "$INIT_SQL" <<'SQL'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;
SQL
  echo "🗃️  Wrote ${INIT_SQL}"
fi

# Create external docker network
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "🌐 Creating network ${NETWORK_NAME} (${NETWORK_SUBNET})"
  docker network create --subnet "$NETWORK_SUBNET" "$NETWORK_NAME"
else
  echo "🌐 Network ${NETWORK_NAME} already exists."
fi

# Patch SERVER_HOSTNAME in config.toml, if present
if [[ -f "$CONFIG_TOML" ]]; then
  read -rp "Enter public SERVER_HOSTNAME (e.g. quay.example.com): " SERVER_HOSTNAME
  [[ -n "${SERVER_HOSTNAME}" ]] || die "SERVER_HOSTNAME cannot be empty."
  if grep -q '^SERVER_HOSTNAME:' "$CONFIG_TOML"; then
    sed -i.bak "s/^SERVER_HOSTNAME:.*/SERVER_HOSTNAME: ${SERVER_HOSTNAME}/" "$CONFIG_TOML"
  else
    echo "SERVER_HOSTNAME: ${SERVER_HOSTNAME}" >> "$CONFIG_TOML"
    cp "$CONFIG_TOML" "${CONFIG_TOML}.bak"
  fi
  echo "✅ Patched SERVER_HOSTNAME=${SERVER_HOSTNAME} in ${CONFIG_TOML} (backup: ${CONFIG_TOML}.bak)"
else
  echo "⚠️  ${CONFIG_TOML} not found. Skipping hostname patch."
fi

# Bring up the stack
echo "🚀 Starting containers..."
( cd "$QUAY_ROOT" && $COMPOSE -f "$COMPOSE_FILE" up -d )

# Wait for Quay health
echo "⏳ Waiting for Quay to become healthy (timeout ${HEALTH_TIMEOUT_SECS}s)..."
start_ts=$(date +%s)
while true; do
  if docker inspect "$QUAY_CONTAINER_NAME" >/dev/null 2>&1; then
    status=$(docker inspect --format='{{.State.Health.Status}}' "$QUAY_CONTAINER_NAME" 2>/dev/null || echo "unknown")
    if [[ "$status" == "healthy" ]]; then
      echo "✅ Quay is healthy."
      break
    fi
    # Fallback to HTTP probe if no healthcheck yet
    if docker exec "$QUAY_CONTAINER_NAME" bash -lc "curl -fsS http://localhost:8080/health/instance >/dev/null" 2>/dev/null; then
      echo "✅ Quay responded OK."
      break
    fi
  fi
  (( $(date +%s) - start_ts > HEALTH_TIMEOUT_SECS )) && die "Timed out waiting for Quay. Check: docker logs ${QUAY_CONTAINER_NAME}"
  sleep 5
done

# Ensure admin user
echo "👤 Ensuring superuser '${QUAY_ADMIN_USER}' exists..."
set +e
docker exec -i "$QUAY_CONTAINER_NAME" bash -lc '
set -e
QM=""
for c in quay-manage /usr/local/bin/quay-manage /quay-registry/quay-manage; do
  if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then QM="$c"; break; fi
done
if [[ -z "$QM" ]]; then
  echo "⚠️  quay-manage not found; skipping user creation."
  exit 0
fi

("$QM" create-user --username "'"$QUAY_ADMIN_USER"'" --password "'"$QUAY_ADMIN_PASS"'" --email "'"$QUAY_ADMIN_EMAIL"'" --superuser) \
  || ("$QM" changepassword --username "'"$QUAY_ADMIN_USER"'" --password "'"$QUAY_ADMIN_PASS"'") || true

("$QM" make-superuser --username "'"$QUAY_ADMIN_USER"'") >/dev/null 2>&1 || true
echo "✅ User ensured: '"'$QUAY_ADMIN_USER'"'"
'
set -e

cat <<EOF

🎉 Done.

Nginx Proxy Manager (NPM):
- Web UI:   http://<your-host>:8181
- Default:  admin@example.com / changeme   ← change this immediately.

Create a Proxy Host in NPM:
- Domain Names: ${SERVER_HOSTNAME:-<your FQDN>}
- Scheme:       http
- Forward Host: quay
- Forward Port: 8080
- SSL:          Request new (Let's Encrypt), enable Force SSL + HTTP/2
- (Optional)    Enable Websockets

Test Quay:
- URL:   https://${SERVER_HOSTNAME:-<your FQDN>}
- Login: ${QUAY_ADMIN_USER} / ${QUAY_ADMIN_PASS}

Utilities:
- Logs (Quay):   docker logs -f ${QUAY_CONTAINER_NAME}
- Restart stack: (cd ${QUAY_ROOT} && ${COMPOSE} restart)
- Tear down:     (cd ${QUAY_ROOT} && ${COMPOSE} down)   # data persists in quay/{db,redis,storage}
EOF
