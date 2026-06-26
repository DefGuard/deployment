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
  make_stack
  write_image_tags "${CORE_TAG:-2}" "${PROXY_TAG:-2}" "${GATEWAY_TAG:-2}"
  bash "$FILES_DIR/generate-env.sh"
}

teardown() {
  if [ "${RUN_INTEGRATION:-0}" = "1" ] && [ -n "${STACK_DIR:-}" ] && command -v docker >/dev/null 2>&1; then
    COMPOSE_PROFILES="core,edge,gateway,dockge" \
      docker compose -f "$STACK_DIR/docker-compose.standalone.yaml" down -v >/dev/null 2>&1 || true
    COMPOSE_PROFILES="dockge" \
      docker compose -f "$STACK_DIR/docker-compose.yaml" down -v >/dev/null 2>&1 || true
  fi
  teardown_stack
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
  docker compose -f "$STACK_DIR/docker-compose.yaml" logs --tail 50 core >&2 2>&1 || true
  return 1
}

@test "all-in-one stack serves the core health endpoint" {
  ( cd "$STACK_DIR" && bash "$FILES_DIR/start.sh" )
  wait_for_health
}

@test "standalone core-only profile serves the core health endpoint" {
  echo "core" > "$STACK_DIR/active-profiles"
  ( cd "$STACK_DIR" && bash "$FILES_DIR/start.sh" )
  wait_for_health
}
