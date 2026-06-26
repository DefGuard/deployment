#!/usr/bin/env bats
# `docker` is stubbed so only start.sh's compose-file/COMPOSE_PROFILES choice
# is exercised, not an actual bring-up.

load helpers

setup() {
  make_stack
  export PATH="$STUB_DIR:$PATH"
  export DOCKER_STUB_LOG="$STACK_DIR/docker-calls.log"
  : > "$DOCKER_STUB_LOG"
}

teardown() {
  teardown_stack
}

@test "no active-profiles, no dockge -> all-in-one, profiles unset" {
  run bash "$FILES_DIR/start.sh"
  [ "$status" -eq 0 ]
  [ "$(last_compose_file)" = "docker-compose.yaml" ]
  [ "$(last_profiles)" = "<unset>" ]
}

@test "no active-profiles, dockge enabled -> all-in-one, dockge profile" {
  touch "$STACK_DIR/enable-docker-management"
  run bash "$FILES_DIR/start.sh"
  [ "$status" -eq 0 ]
  [ "$(last_compose_file)" = "docker-compose.yaml" ]
  [ "$(last_profiles)" = "dockge" ]
}

@test "active-profiles=core -> standalone, core profile" {
  echo "core" > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/start.sh"
  [ "$status" -eq 0 ]
  [ "$(last_compose_file)" = "docker-compose.standalone.yaml" ]
  [ "$(last_profiles)" = "core" ]
}

@test "active-profiles='core gateway' (space separated) -> core,gateway" {
  printf 'core gateway\n' > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/start.sh"
  [ "$status" -eq 0 ]
  [ "$(last_compose_file)" = "docker-compose.standalone.yaml" ]
  [ "$(last_profiles)" = "core,gateway" ]
}

@test "active-profiles multiline + dockge -> profiles plus dockge appended" {
  printf 'core\nedge\ngateway\n' > "$STACK_DIR/active-profiles"
  touch "$STACK_DIR/enable-docker-management"
  run bash "$FILES_DIR/start.sh"
  [ "$status" -eq 0 ]
  [ "$(last_compose_file)" = "docker-compose.standalone.yaml" ]
  [ "$(last_profiles)" = "core,edge,gateway,dockge" ]
}

@test "empty/whitespace active-profiles -> falls back to all-in-one" {
  printf '   \n' > "$STACK_DIR/active-profiles"
  run bash "$FILES_DIR/start.sh"
  [ "$status" -eq 0 ]
  [ "$(last_compose_file)" = "docker-compose.yaml" ]
  [ "$(last_profiles)" = "<unset>" ]
}

@test "empty active-profiles + dockge -> all-in-one with dockge" {
  printf '\n' > "$STACK_DIR/active-profiles"
  touch "$STACK_DIR/enable-docker-management"
  run bash "$FILES_DIR/start.sh"
  [ "$status" -eq 0 ]
  [ "$(last_compose_file)" = "docker-compose.yaml" ]
  [ "$(last_profiles)" = "dockge" ]
}
