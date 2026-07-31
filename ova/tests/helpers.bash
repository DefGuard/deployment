# shellcheck shell=bash

OVA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_DIR="$OVA_DIR/files"
STUB_DIR="$OVA_DIR/tests/stub"

# DEFGUARD_STACK_DIR/DEFGUARD_INIT_DIR redirect the scripts at temp dirs.
make_stack() {
  STACK_DIR="$(mktemp -d)"
  INIT_DIR="$STACK_DIR/init"
  mkdir -p "$INIT_DIR"
  export DEFGUARD_STACK_DIR="$STACK_DIR"
  export DEFGUARD_INIT_DIR="$INIT_DIR"
  cp "$FILES_DIR/docker-compose.template.yaml" "$INIT_DIR/"
  cp "$FILES_DIR/lib.sh" "$INIT_DIR/"
}

teardown_stack() {
  [ -n "${STACK_DIR:-}" ] && rm -rf "$STACK_DIR"
  return 0
}

# Bake image tags as the Packer build does; generate-env.sh sources this.
write_image_tags() {
  cat > "$INIT_DIR/.image-tags" <<EOF
DEFGUARD_CORE_TAG=${1:-test-core}
DEFGUARD_PROXY_TAG=${2:-test-proxy}
DEFGUARD_GATEWAY_TAG=${3:-test-gateway}
EOF
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

make_ova_home() {
  OVA_HOME="$(mktemp -d)"
  mkdir -p "$OVA_HOME/backups"
  export DEFGUARD_OVA_DIR="$OVA_HOME"
  export DEFGUARD_OVA_ALLOW_NONROOT=1
  # Keep tests from touching the host's systemd unit while exercising the
  # legacy-layout backup/upgrade path.
  export DEFGUARD_INIT_SERVICE_FILE="$OVA_HOME/defguard-init.service"
}

teardown_ova_home() {
  [ -n "${OVA_HOME:-}" ] && rm -rf "$OVA_HOME"
  return 0
}

stub_docker() {
  STUB_BIN="$(mktemp -d)"
  DOCKER_REAL="$(command -v docker)"
  export DOCKER_REAL
  export DOCKER_STUB_LOG="$STUB_BIN/calls.log"
  export DOCKER_STUB_STATE_FILE="$STUB_BIN/state"
  cp "$STUB_DIR/docker-stub" "$STUB_BIN/docker"
  chmod +x "$STUB_BIN/docker"
  PATH="$STUB_BIN:$PATH"
  export PATH
}

teardown_stub_docker() {
  [ -n "${STUB_BIN:-}" ] && rm -rf "$STUB_BIN"
  return 0
}

seed_stack() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@" > "$STACK_DIR/active-profiles"
  fi
  write_image_tags "${CORE_TAG:-2}" "${PROXY_TAG:-2}" "${GATEWAY_TAG:-2}"
  bash "$FILES_DIR/generate-env.sh" >/dev/null
  bash "$FILES_DIR/generate-compose.sh" >/dev/null
  mkdir -p "$STACK_DIR/.volumes/db" "$STACK_DIR/.volumes/certs"
  echo "seeded-db-file" > "$STACK_DIR/.volumes/db/marker"
}

# Recreates the layout emitted before commit ff0bce1 (the Compose
# simplification): static full/standalone files, root startup scripts, and no
# init directory. The segmented fixture deliberately selects all three
# profiles because that was still a distinct standalone layout before the
# simplification.
seed_legacy_stack() {
  local mode="$1"
  write_env "2" "2" "2"
  write_image_tags 2 2 2
  cat > "$STACK_DIR/docker-compose.yaml" <<'EOF'
services:
  core:
    image: ghcr.io/defguard/defguard:${DEFGUARD_CORE_TAG:?DEFGUARD_CORE_TAG is required}
    env_file: .env
    environment:
      DEFGUARD_DB_HOST: db
      DEFGUARD_DB_PORT: 5432
      DEFGUARD_ADOPT_EDGE: "edge:50051"
      DEFGUARD_ADOPT_GATEWAY: "host.docker.internal:50066"
    depends_on: [db, edge, gateway]
  edge:
    image: ghcr.io/defguard/defguard-proxy:${DEFGUARD_PROXY_TAG:?DEFGUARD_PROXY_TAG is required}
    ports: ["8080:8080", "443:443", "80:80"]
  gateway:
    image: ghcr.io/defguard/gateway:${DEFGUARD_GATEWAY_TAG:?DEFGUARD_GATEWAY_TAG is required}
    network_mode: host
  dockge:
    image: louislam/dockge:1
    profiles: [dockge]
  db:
    image: postgres:18-alpine
    env_file: .env
EOF
  cat > "$STACK_DIR/docker-compose.standalone.yaml" <<'EOF'
services:
  core:
    profiles: [core]
    image: ghcr.io/defguard/defguard:${DEFGUARD_CORE_TAG:?DEFGUARD_CORE_TAG is required}
    env_file: .env
    depends_on: [db]
  edge:
    profiles: [edge]
    image: ghcr.io/defguard/defguard-proxy:${DEFGUARD_PROXY_TAG:?DEFGUARD_PROXY_TAG is required}
    ports: ["8080:8080", "50051:50051", "443:443", "80:80"]
  gateway:
    profiles: [gateway]
    image: ghcr.io/defguard/gateway:${DEFGUARD_GATEWAY_TAG:?DEFGUARD_GATEWAY_TAG is required}
    network_mode: host
  dockge:
    profiles: [dockge]
    image: louislam/dockge:1
  db:
    profiles: [core]
    image: postgres:18-alpine
    env_file: .env
EOF
  cat > "$STACK_DIR/generate-env.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$STACK_DIR/start.sh" <<'EOF'
#!/bin/bash
docker compose up -d
EOF
  chmod +x "$STACK_DIR/generate-env.sh" "$STACK_DIR/start.sh"
  if [ "$mode" = segmented ]; then
    printf 'core\nedge\ngateway\n' > "$STACK_DIR/active-profiles"
  fi
  mkdir -p "$STACK_DIR/.volumes/db"
  echo "seeded-db-file" > "$STACK_DIR/.volumes/db/marker"
  cat > "$DEFGUARD_INIT_SERVICE_FILE" <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/bash /opt/stacks/defguard/generate-env.sh
ExecStart=/bin/bash /opt/stacks/defguard/start.sh
EOF
}

# A file:// manifest, so upgrades can be exercised without network access.
# $5, if given, is a JSON array literal for the "migrations" field.
write_manifest() {
  cat > "$STACK_DIR/manifest.json" <<EOF
{
  "ova_version": "${1:-9.9.9}",
  "core_tag": "${2:-9}",
  "proxy_tag": "${3:-9}",
  "gateway_tag": "${4:-9}",
  "template_ref": "test-ref",
  "migrations": ${5:-[]}
}
EOF
  export DEFGUARD_OVA_MANIFEST_URL="file://$STACK_DIR/manifest.json"
  export DEFGUARD_OVA_SOURCE_DIR="$(cd "$OVA_DIR/.." && pwd)"
}

# Copies the real ova/files/* alongside a fake migrations/<version>.sh so
# do_upgrade's fetch_ova_file picks it up, and points DEFGUARD_OVA_SOURCE_DIR
# at the copy. Caller must write_manifest with matching "migrations" first (or
# after - only DEFGUARD_OVA_SOURCE_DIR needs to be set last).
stage_migration() {
  local version="$1" body="$2"
  MIGRATION_SOURCE_DIR="$(mktemp -d)"
  mkdir -p "$MIGRATION_SOURCE_DIR/ova/files/migrations"
  cp "$FILES_DIR/docker-compose.template.yaml" "$FILES_DIR/lib.sh" "$FILES_DIR/generate-compose.sh" \
    "$MIGRATION_SOURCE_DIR/ova/files/"
  printf '%s\n' "$body" > "$MIGRATION_SOURCE_DIR/ova/files/migrations/$version.sh"
  export DEFGUARD_OVA_SOURCE_DIR="$MIGRATION_SOURCE_DIR"
}

teardown_migration_source() {
  [ -n "${MIGRATION_SOURCE_DIR:-}" ] && rm -rf "$MIGRATION_SOURCE_DIR"
  return 0
}

# Minimal .env so compose interpolation of the *_TAG variables succeeds.
write_env() {
  cat > "$STACK_DIR/.env" <<EOF
DEFGUARD_CORE_TAG=${1:-test-core}
DEFGUARD_PROXY_TAG=${2:-test-proxy}
DEFGUARD_GATEWAY_TAG=${3:-test-gateway}
EOF
}
