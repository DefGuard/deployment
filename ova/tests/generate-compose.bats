#!/usr/bin/env bats
# `docker compose config` evaluates profiles without pulling images, so
# generate-compose.sh's output can be checked offline.

load helpers

setup() {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  make_stack
  write_env
}

teardown() {
  teardown_stack
}

generated_services() {
  unset COMPOSE_PROFILES
  docker compose -f "$STACK_DIR/docker-compose.yml" config --services 2>/dev/null | sort | xargs
}

generated_json() {
  unset COMPOSE_PROFILES
  docker compose -f "$STACK_DIR/docker-compose.yml" config --format json
}

@test "no active-profiles -> full stack: core db edge gateway" {
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [ "$(generated_services)" = "core db edge gateway" ]
}

@test "active-profiles=core -> core db" {
  echo "core" > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [ "$(generated_services)" = "core db" ]
}

@test "active-profiles='core gateway' -> core db gateway" {
  printf 'core gateway\n' > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [ "$(generated_services)" = "core db gateway" ]
}

@test "full stack + dockge flag -> core db dockge edge gateway" {
  touch "$STACK_DIR/enable-docker-management"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [ "$(generated_services)" = "core db dockge edge gateway" ]
}

@test "no surviving service carries a profiles key" {
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [ "$(generated_json | jq '[.services[] | select(has("profiles"))] | length')" -eq 0 ]
}

@test "full stack: core.depends_on includes edge and gateway" {
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  deps="$(generated_json | jq -r 'if (.services.core.depends_on | type) == "array" then .services.core.depends_on[] else (.services.core.depends_on | keys[]) end' | sort | xargs)"
  [ "$deps" = "db edge gateway" ]
}

@test "segmented core-only: core.depends_on is just db" {
  echo "core" > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  deps="$(generated_json | jq -r 'if (.services.core.depends_on | type) == "array" then .services.core.depends_on[] else (.services.core.depends_on | keys[]) end' | sort | xargs)"
  [ "$deps" = "db" ]
}

@test "full stack: edge's 50051 port is not exposed" {
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  ! generated_json | jq -e '.services.edge.ports[] | select(.published == "50051")' >/dev/null
}

@test "segmented edge+gateway (no core): edge's 50051 port is exposed" {
  printf 'edge gateway\n' > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  generated_json | jq -e '.services.edge.ports[] | select(.published == "50051")' >/dev/null
}

@test "idempotent: second run is a no-op" {
  bash "$FILES_DIR/generate-compose.sh"
  before="$(cat "$STACK_DIR/docker-compose.yml")"
  echo "core" > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$STACK_DIR/docker-compose.yml")" = "$before" ]
}

@test "flag files and the init dir are removed after a successful run" {
  echo "core" > "$STACK_DIR/active-profiles"
  touch "$STACK_DIR/enable-docker-management"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$STACK_DIR/active-profiles" ]
  [ ! -f "$STACK_DIR/enable-docker-management" ]
  [ ! -d "$INIT_DIR" ]
}

@test "empty/whitespace active-profiles falls back to full stack" {
  printf '   \n' > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using full all-in-one stack"* ]]
  [ "$(generated_services)" = "core db edge gateway" ]
}

@test "generated file's leading comment lists the resolved profiles" {
  printf 'core gateway\n' > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/generate-compose.sh"
  [ "$status" -eq 0 ]
  head -n2 "$STACK_DIR/docker-compose.yml" | grep -q '# Selected profiles: core gateway'
}
