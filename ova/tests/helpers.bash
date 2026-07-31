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
