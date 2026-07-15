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

# Minimal .env so compose interpolation of the *_TAG variables succeeds.
write_env() {
  cat > "$STACK_DIR/.env" <<EOF
DEFGUARD_CORE_TAG=${1:-test-core}
DEFGUARD_PROXY_TAG=${2:-test-proxy}
DEFGUARD_GATEWAY_TAG=${3:-test-gateway}
EOF
}
