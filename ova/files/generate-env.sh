#!/bin/bash
# Generates /opt/stacks/defguard/.env with random secrets on first boot.
# If .env already exists (e.g. provided via cloud-init), this script does nothing.
set -euo pipefail

STACK_DIR="${DEFGUARD_STACK_DIR:-/opt/stacks/defguard}"
INIT_DIR="${DEFGUARD_INIT_DIR:-$STACK_DIR/init}"
ENV_FILE="$STACK_DIR/.env"
PROFILES_FILE="$STACK_DIR/active-profiles"
DEPLOYMENT_MODE_FILE="$INIT_DIR/.deployment-mode"

if [ -f "$ENV_FILE" ]; then
  echo "DefGuard: .env already exists, skipping generation."
  exit 0
fi

echo "DefGuard: generating .env with random secrets..."

# shellcheck source=lib.sh
source "$INIT_DIR/lib.sh"

DB_PASSWORD=$(openssl rand -hex 16)

if [ -f "$INIT_DIR/.image-tags" ]; then
  source "$INIT_DIR/.image-tags"
fi

: "${DEFGUARD_CORE_TAG:?DEFGUARD_CORE_TAG is required}"
: "${DEFGUARD_PROXY_TAG:?DEFGUARD_PROXY_TAG is required}"
: "${DEFGUARD_GATEWAY_TAG:?DEFGUARD_GATEWAY_TAG is required}"

# Only default the adopt targets when core/edge/gateway are genuinely
# co-located on this host; segmented deployments must fill these in manually
# since edge/gateway live on other VMs entirely.
mapfile -t _profiles < <(resolve_profiles "$STACK_DIR")
PERSISTED_MODE="$(deployment_mode "$INIT_DIR")" \
  || { echo "DefGuard: invalid deployment mode in $DEPLOYMENT_MODE_FILE" >&2; exit 1; }
if [ -n "${DEFGUARD_DEPLOYMENT_MODE:-}" ]; then
  MODE="$DEFGUARD_DEPLOYMENT_MODE"
elif [ "$PERSISTED_MODE" = segmented ]; then
  MODE=segmented
elif [ -f "$PROFILES_FILE" ]; then
  MODE=auto
else
  MODE="$PERSISTED_MODE"
fi
case "$MODE" in
  auto|full|segmented) ;;
  *) echo "DefGuard: invalid deployment mode '$MODE'" >&2; exit 1 ;;
esac
ADOPT_EDGE=""
ADOPT_GATEWAY=""
if [ "$MODE" = full ] || { [ "$MODE" = auto ] && is_full_stack "${_profiles[@]}"; }; then
  ADOPT_EDGE="edge:50051"
  ADOPT_GATEWAY="host.docker.internal:50066"
fi

cat > "$ENV_FILE" <<EOF
DEFGUARD_COOKIE_INSECURE=false

DEFGUARD_DB_HOST=db
DEFGUARD_DB_PORT=5432
DEFGUARD_DB_USER=defguard
DEFGUARD_DB_PASSWORD=${DB_PASSWORD}
DEFGUARD_DB_NAME=defguard
POSTGRES_USER=defguard
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=defguard

DEFGUARD_CORE_TAG=${DEFGUARD_CORE_TAG}
DEFGUARD_PROXY_TAG=${DEFGUARD_PROXY_TAG}
DEFGUARD_GATEWAY_TAG=${DEFGUARD_GATEWAY_TAG}

DEFGUARD_ADOPT_EDGE=${ADOPT_EDGE}
DEFGUARD_ADOPT_GATEWAY=${ADOPT_GATEWAY}
EOF

chmod 600 "$ENV_FILE"
echo "DefGuard: .env generated at ${ENV_FILE}"
