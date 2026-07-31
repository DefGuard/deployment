#!/usr/bin/env bats
# Real bring-up: pulls images and binds :8000, so it is gated behind
# RUN_INTEGRATION=1. Tags default to "2" (matching the other CI tests);
# override with CORE_TAG / PROXY_TAG / GATEWAY_TAG.

load helpers

HEALTH_URL="http://localhost:8000/api/v1/health"

setup() {
  [ "${RUN_INTEGRATION:-0}" = "1" ] || skip "set RUN_INTEGRATION=1 to run real bring-up"
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  make_stack
  write_image_tags "${CORE_TAG:-2}" "${PROXY_TAG:-2}" "${GATEWAY_TAG:-2}"
}

teardown() {
  if [ "${RUN_INTEGRATION:-0}" = "1" ] && [ -n "${STACK_DIR:-}" ] && command -v docker >/dev/null 2>&1; then
    docker compose -f "$STACK_DIR/docker-compose.yml" down -v >/dev/null 2>&1 || true
  fi
  teardown_stack
}

bring_up() {
  bash "$FILES_DIR/generate-env.sh"
  bash "$FILES_DIR/generate-compose.sh"
  docker compose -f "$STACK_DIR/docker-compose.yml" up -d
}

wait_for_health() {
  local tries="${1:-90}"
  for ((i = 0; i < tries; i++)); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "core health endpoint never came up; recent logs:" >&2
  docker compose -f "$STACK_DIR/docker-compose.yml" logs --tail 50 core >&2 2>&1 || true
  return 1
}

@test "all-in-one stack serves the core health endpoint" {
  bring_up
  wait_for_health
}

@test "standalone core-only profile serves the core health endpoint" {
  echo "core" > "$STACK_DIR/active-profiles"
  bring_up
  wait_for_health
}

# Upgrade the core-only profile in place: cheaper than the full stack and it is
# the profile that owns the database, which is what an upgrade must not lose.
@test "dg-ctl upgrade keeps database state and passes its own health checks" {
  command -v zstd >/dev/null 2>&1 || skip "zstd not installed"
  echo "core" > "$STACK_DIR/active-profiles"
  bring_up
  wait_for_health

  psql() { docker compose -f "$STACK_DIR/docker-compose.yml" exec -T db psql -qtAX -U defguard -d defguard "$@"; }
  psql -c "CREATE TABLE ova_upgrade_probe (v text); INSERT INTO ova_upgrade_probe VALUES ('survived');"

  OVA_HOME="$(mktemp -d)"
  cat > "$OVA_HOME/manifest.json" <<EOF
{
"ova_version": "9.9.9-integration",
  "core_tag": "${UPGRADE_CORE_TAG:-${CORE_TAG:-2}}",
  "proxy_tag": "${UPGRADE_PROXY_TAG:-${PROXY_TAG:-2}}",
  "gateway_tag": "${UPGRADE_GATEWAY_TAG:-${GATEWAY_TAG:-2}}",
  "template_ref": "worktree"
}
EOF

  DEFGUARD_OVA_DIR="$OVA_HOME" \
  DEFGUARD_OVA_ALLOW_NONROOT=1 \
  DEFGUARD_OVA_MANIFEST_URL="file://$OVA_HOME/manifest.json" \
  DEFGUARD_OVA_SOURCE_DIR="$(cd "$OVA_DIR/.." && pwd)" \
    bash "$FILES_DIR/dg-ctl" upgrade --yes

  [ "$(psql -c 'SELECT v FROM ova_upgrade_probe;' | tr -d '[:space:]')" = "survived" ]
  [ "$(jq -r '.ova_version' "$OVA_HOME/state.json")" = "9.9.9-integration" ]
  [ -f "$OVA_HOME/backups/$(jq -r '.backup_id' "$OVA_HOME/state.json")/volumes.tar.zst" ]
  rm -rf "$OVA_HOME"
}
