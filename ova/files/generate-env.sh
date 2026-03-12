#!/bin/bash
# Generates /opt/defguard/.env with random secrets on first boot.
# If .env already exists (e.g. provided via cloud-init), this script does nothing.

ENV_FILE="/opt/defguard/.env"

if [ -f "$ENV_FILE" ]; then
  echo "DefGuard: .env already exists, skipping generation."
  exit 0
fi

echo "DefGuard: generating .env with random secrets..."

DEFGUARD_SECRET_KEY=$(openssl rand -hex 32)
DEFGUARD_AUTH_SECRET=$(openssl rand -hex 32)
DEFGUARD_GATEWAY_SECRET=$(openssl rand -hex 32)
DEFGUARD_YUBIBRIDGE_SECRET=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 16)

if [ -f "/opt/defguard/.image-tags" ]; then
  source "/opt/defguard/.image-tags"
fi

: "${DEFGUARD_CORE_TAG:?DEFGUARD_CORE_TAG is required}"
: "${DEFGUARD_PROXY_TAG:?DEFGUARD_PROXY_TAG is required}"
: "${DEFGUARD_GATEWAY_TAG:?DEFGUARD_GATEWAY_TAG is required}"

cat > "$ENV_FILE" <<EOF
DEFGUARD_SECRET_KEY=${DEFGUARD_SECRET_KEY}
DEFGUARD_AUTH_SECRET=${DEFGUARD_AUTH_SECRET}
DEFGUARD_GATEWAY_SECRET=${DEFGUARD_GATEWAY_SECRET}
DEFGUARD_YUBIBRIDGE_SECRET=${DEFGUARD_YUBIBRIDGE_SECRET}
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
EOF

chmod 600 "$ENV_FILE"
echo "DefGuard: .env generated at ${ENV_FILE}"
