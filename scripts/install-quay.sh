#!/usr/bin/env bash
set -euo pipefail

# ---- repo-aware paths ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
QUAY_ROOT="${REPO_ROOT}/quay"

# ---- files/dirs ----
COMPOSE_FILE="${QUAY_ROOT}/docker-compose.yml"
CONFIG_YAML="${QUAY_ROOT}/config/config.yaml"
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
HEALTH_TIMEOUT_SECS=30   # timeout shortened per request

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

# Ensure directory structure
echo "📂 Ensuring directories exist under ${QUAY_ROOT} ..."
mkdir -p \
  "${QUAY_ROOT}/config" \
  "${QUAY_ROOT}/storage" \
  "${QUAY_ROOT}/redis/data" \
  "${QUAY_ROOT}/db/data" \
  "${QUAY_ROOT}/db/init" \
  "${QUAY_ROOT}/nginx-pm"

# Set open permissions for storage (for demo/student use)
chmod 777 "${QUAY_ROOT}/storage" || echo "⚠️ Could not chmod 777 ${QUAY_ROOT}/storage"

# .env for nginx-pm variables
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<EOF
PUID=$(id -u)
PGID=$(id -g)
TZ=Asia/Singapore
EOF
  echo "📝 Wrote ${ENV_FILE}"
fi

# Postgres init extensions
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

# Patch SERVER_HOSTNAME in YAML
if [[ -f "$CONFIG_YAML" ]]; then
  read -rp "Enter public SERVER_HOSTNAME (e.g. quay.example.com): " SERVER_HOSTNAME
  [[ -n "${SERVER_HOSTNAME}" ]] || die "SERVER_HOSTNAME cannot be empty."

  cp "$CONFIG_YAML" "${CONFIG_YAML}.bak"
  if grep -qE '^[[:space:]]*SERVER_HOSTNAME:' "${CONFIG_YAML}.bak"; then
    awk -v host="$SERVER_HOSTNAME" '
      BEGIN{done=0}
      /^[[:space:]]*SERVER_HOSTNAME:/ && !done { sub(/:.*/, ": " host); done=1 }
      { print }
      END{
        if (!done) print "SERVER_HOSTNAME: " host
      }
    ' "${CONFIG_YAML}.bak" > "${CONFIG_YAML}"
  else
    printf "\nSERVER_HOSTNAME: %s\n" "$SERVER_HOSTNAME" >> "$CONFIG_YAML"
  fi
  echo "✅ Patched SERVER_HOSTNAME=${SERVER_HOSTNAME} in ${CONFIG_YAML} (backup: ${CONFIG_YAML}.bak)"
else
  echo "⚠️  ${CONFIG_YAML} not found. Quay requires /conf/stack/config.yaml. Skipping hostname patch."
fi

# Bring up the stack
echo "🚀 Starting containers via compose..."
( cd "$QUAY_ROOT" && $COMPOSE -f "$COMPOSE_FILE" up -d )

# Wait for Quay health
echo "⏳ Waiting up to ${HEALTH_TIMEOUT_SECS}s for Quay health..."
start_ts=$(date +%s)
while true; do
  if docker inspect "$QUAY_CONTAINER_NAME" >/dev/null 2>&1; then
    status=$(docker inspect --format='{{.State.Health.Status}}' "$QUAY_CONTAINER_NAME" 2>/dev/null || echo "unknown")
    if [[ "$status" == "healthy" ]]; then
      echo "✅ Quay is healthy."
      break
    fi
    if docker exec "$QUAY_CONTAINER_NAME" bash -lc "curl -fsS http://localhost:8080/health/instance >/dev/null" 2>/dev/null; then
      echo "✅ Quay responded OK."
      break
    fi
  fi
  (( $(date +%s) - start_ts > HEALTH_TIMEOUT_SECS )) && die "Timed out waiting for Quay. Check: docker logs ${QUAY_CONTAINER_NAME}"
  sleep 3
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
- Tear down:     (cd ${QUAY_ROOT} && ${COMPOSE} down)
EOF
