#!/usr/bin/env bats
# `docker compose config` evaluates profiles without pulling images, so the
# expected service set per profile combination can be checked offline.

load helpers

setup() {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
  make_stack
  write_env
}

teardown() {
  teardown_stack
}

# sorted, space-joined active services for a given file ($1) and profiles ($2)
services_for() {
  COMPOSE_PROFILES="$2" docker compose -f "$STACK_DIR/$1" config --services 2>/dev/null | sort | xargs
}

@test "all-in-one without profiles -> core db edge gateway" {
  [ "$(services_for docker-compose.yaml "")" = "core db edge gateway" ]
}

@test "all-in-one with dockge -> core db dockge edge gateway" {
  [ "$(services_for docker-compose.yaml "dockge")" = "core db dockge edge gateway" ]
}

@test "standalone core -> core db" {
  [ "$(services_for docker-compose.standalone.yaml "core")" = "core db" ]
}

@test "standalone core,gateway -> core db gateway" {
  [ "$(services_for docker-compose.standalone.yaml "core,gateway")" = "core db gateway" ]
}

@test "standalone core,edge,gateway -> core db edge gateway" {
  [ "$(services_for docker-compose.standalone.yaml "core,edge,gateway")" = "core db edge gateway" ]
}

@test "standalone core,edge,gateway,dockge -> core db dockge edge gateway" {
  [ "$(services_for docker-compose.standalone.yaml "core,edge,gateway,dockge")" = "core db dockge edge gateway" ]
}

@test "standalone with no profiles -> no services" {
  [ "$(services_for docker-compose.standalone.yaml "")" = "" ]
}
