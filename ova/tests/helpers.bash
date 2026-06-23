# shellcheck shell=bash

OVA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_DIR="$OVA_DIR/files"
STUB_DIR="$OVA_DIR/tests/stub"

# DEFGUARD_STACK_DIR redirects the scripts at this temp dir; compose files are
# copied in so `docker compose config` and real `up` see the actual definitions.
make_stack() {
  STACK_DIR="$(mktemp -d)"
  export DEFGUARD_STACK_DIR="$STACK_DIR"
  cp "$FILES_DIR/docker-compose.yaml" "$STACK_DIR/"
  cp "$FILES_DIR/docker-compose.standalone.yaml" "$STACK_DIR/"
}

teardown_stack() {
  [ -n "${STACK_DIR:-}" ] && rm -rf "$STACK_DIR"
  return 0
}

# Bake image tags as the Packer build does; generate-env.sh sources this.
write_image_tags() {
  cat > "$STACK_DIR/.image-tags" <<EOF
DEFGUARD_CORE_TAG=${1:-test-core}
DEFGUARD_PROXY_TAG=${2:-test-proxy}
DEFGUARD_GATEWAY_TAG=${3:-test-gateway}
EOF
}

# Minimal .env so compose interpolation of the *_TAG variables succeeds.
write_env() {
  cat > "$STACK_DIR/.env" <<EOF
DEFGUARD_CORE_TAG=${1:-test-core}
DEFGUARD_PROXY_TAG=${2:-test-proxy}
DEFGUARD_GATEWAY_TAG=${3:-test-gateway}
EOF
}

last_compose_file() {
  grep '^args=' "$DOCKER_STUB_LOG" | tail -1 | grep -oE '[^ ]+\.yaml' | xargs -n1 basename
}

last_profiles() {
  grep '^compose_profiles=' "$DOCKER_STUB_LOG" | tail -1 | cut -d= -f2-
}
