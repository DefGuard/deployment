#!/usr/bin/env bats

load helpers

setup() {
  make_stack
}

teardown() {
  teardown_stack
}

@test "generates .env with tags sourced from .image-tags" {
  write_image_tags aaa bbb ccc
  run bash "$FILES_DIR/generate-env.sh"
  [ "$status" -eq 0 ]
  [ -f "$STACK_DIR/.env" ]
  grep -qx 'DEFGUARD_CORE_TAG=aaa' "$STACK_DIR/.env"
  grep -qx 'DEFGUARD_PROXY_TAG=bbb' "$STACK_DIR/.env"
  grep -qx 'DEFGUARD_GATEWAY_TAG=ccc' "$STACK_DIR/.env"
}

@test "db and postgres passwords match and are non-empty" {
  write_image_tags
  bash "$FILES_DIR/generate-env.sh"
  dbp=$(grep '^DEFGUARD_DB_PASSWORD=' "$STACK_DIR/.env" | cut -d= -f2)
  pgp=$(grep '^POSTGRES_PASSWORD=' "$STACK_DIR/.env" | cut -d= -f2)
  [ -n "$dbp" ]
  [ "$dbp" = "$pgp" ]
}

@test ".env is created with 600 permissions" {
  write_image_tags
  bash "$FILES_DIR/generate-env.sh"
  perm=$(stat -c '%a' "$STACK_DIR/.env" 2>/dev/null || stat -f '%Lp' "$STACK_DIR/.env")
  [ "$perm" = "600" ]
}

@test "existing .env is left untouched (idempotent)" {
  echo "SENTINEL=keep-me" > "$STACK_DIR/.env"
  write_image_tags
  run bash "$FILES_DIR/generate-env.sh"
  [ "$status" -eq 0 ]
  grep -qx 'SENTINEL=keep-me' "$STACK_DIR/.env"
}

@test "fails and writes nothing when .image-tags is missing" {
  run bash "$FILES_DIR/generate-env.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DEFGUARD_CORE_TAG is required"* ]]
  [ ! -f "$STACK_DIR/.env" ]
}
