#!/bin/bash
# Installs the defguard OVA maintenance CLI onto an already-deployed OVA VM,
# which shipped without it. Idempotent - re-running just refreshes the CLI.
#
#   curl -fsSL https://raw.githubusercontent.com/DefGuard/deployment/main/ova/files/install-dg-ctl.sh | sudo bash
set -euo pipefail

STACK_DIR="${DEFGUARD_STACK_DIR:-/opt/stacks/defguard}"
OVA_DIR="${DEFGUARD_OVA_DIR:-/opt/defguard}"
OVA_REPO="${DEFGUARD_OVA_REPO:-DefGuard/deployment}"
MANIFEST_URL="${DEFGUARD_OVA_MANIFEST_URL:-https://raw.githubusercontent.com/$OVA_REPO/main/ova/manifest.json}"
SOURCE_DIR="${DEFGUARD_OVA_SOURCE_DIR:-}"

log() { echo "[dg-ctl-install] $*"; }
die() { echo "[dg-ctl-install] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run as root (pipe into 'sudo bash')"
if [ ! -f "$STACK_DIR/docker-compose.yml" ] \
  && [ ! -f "$STACK_DIR/docker-compose.yaml" ]; then
  die "$STACK_DIR/docker-compose.yml or $STACK_DIR/docker-compose.yaml not found; this does not look like a defguard OVA host"
fi

# jq and zstd are baked into OVA 2.1 images but not into earlier ones.
missing=()
command -v jq >/dev/null 2>&1 || missing+=(jq)
command -v zstd >/dev/null 2>&1 || missing+=(zstd)
command -v curl >/dev/null 2>&1 || missing+=(curl)
if [ "${#missing[@]}" -gt 0 ]; then
  log "installing missing dependencies: ${missing[*]}"
  apt-get update -qq
  apt-get install -y --no-install-recommends "${missing[@]}"
fi

fetch() {
  local src="$1" dest="$2"
  case "$src" in
    file://*) cp "${src#file://}" "$dest" ;;
    /*)       cp "$src" "$dest" ;;
    *)        curl -fsSL --retry 3 -o "$dest" "$src" ;;
  esac
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fetch "$MANIFEST_URL" "$work/manifest.json" || die "could not fetch manifest from $MANIFEST_URL"
REF="$(jq -r '.template_ref // "main"' "$work/manifest.json")"

if [ -n "$SOURCE_DIR" ]; then
  cp "$SOURCE_DIR/ova/files/dg-ctl" "$work/dg-ctl"
else
  fetch "https://raw.githubusercontent.com/$OVA_REPO/$REF/ova/files/dg-ctl" "$work/dg-ctl" \
    || die "could not fetch dg-ctl at ref $REF"
fi
bash -n "$work/dg-ctl" || die "downloaded dg-ctl does not parse; aborting"

mkdir -p "$OVA_DIR/backups"
install -m 750 -o root -g root "$work/dg-ctl" "$OVA_DIR/dg-ctl"
ln -sf "$OVA_DIR/dg-ctl" /usr/local/bin/dg-ctl

# Seed state from what is actually deployed. ova_version is unknown for images
# built before the manifest existed; the tags in .env are the truth.
if [ ! -f "$OVA_DIR/state.json" ]; then
  env_value() { sed -n "s/^$1=//p" "$STACK_DIR/.env" | tail -n1; }
  jq -n \
    --arg core "$(env_value DEFGUARD_CORE_TAG)" \
    --arg proxy "$(env_value DEFGUARD_PROXY_TAG)" \
    --arg gateway "$(env_value DEFGUARD_GATEWAY_TAG)" \
    '{ova_version: "2.0-unknown", template_ref: "unknown",
      tags: {core: $core, proxy: $proxy, gateway: $gateway}}' > "$OVA_DIR/state.json"
  chmod 600 "$OVA_DIR/state.json"
fi

log "installed $OVA_DIR/dg-ctl (ref $REF)"
log "next: sudo $OVA_DIR/dg-ctl upgrade"
