#!/usr/bin/env bats
# Exercises /opt/defguard/dg-ctl against a temp stack: real `docker compose config`
# (offline), everything daemon-facing faked by tests/stub/docker-stub.

load helpers

CLI="$FILES_DIR/dg-ctl"

setup() {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  command -v zstd >/dev/null 2>&1 || skip "zstd not installed"
  command -v sha256sum >/dev/null 2>&1 || skip "sha256sum not available"
  make_stack
  make_ova_home
  stub_docker
  # Health checks must not sit in retry loops in unit tests.
  export HEALTH_TIMEOUT=1 HEALTH_SETTLE=0
}

teardown() {
  teardown_stub_docker
  teardown_ova_home
  teardown_stack
  teardown_migration_source
}

@test "backup captures volumes, env, compose file and a matching checksum" {
  seed_stack core
  run bash "$CLI" backup --label unit
  [ "$status" -eq 0 ]
  id="${lines[-1]}"
  dir="$OVA_HOME/backups/$id"

  for f in volumes.tar.zst env docker-compose.yml applied-profiles image-digests meta.json; do
    [ -f "$dir/$f" ]
  done
  [ "$(jq -r '.volumes_sha256' "$dir/meta.json")" = "$(sha256sum "$dir/volumes.tar.zst" | awk '{print $1}')" ]
  [ "$(jq -r '.tags.core' "$dir/meta.json")" = "2" ]
  [ "$(cat "$dir/applied-profiles")" = "core" ]
  [ "$(file_mode "$dir/env")" = "600" ]
}

@test "list-backups shows a created backup" {
  seed_stack core
  id="$(bash "$CLI" backup 2>/dev/null | tail -n1)"
  run bash "$CLI" list-backups
  [ "$status" -eq 0 ]
  [[ "$output" == *"$id"* ]]
}

@test "backups beyond KEEP_BACKUPS are pruned on upgrade" {
  seed_stack core
  write_manifest
  for n in 1 2 3 4; do mkdir -p "$OVA_HOME/backups/2000010$n-000000Z"; done
  KEEP_BACKUPS=2 run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -eq 0 ]
  # 2 kept: the freshly taken one sorts last, so only it plus one placeholder.
  [ "$(ls -1 "$OVA_HOME/backups" | wc -l)" -eq 2 ]
}

@test "rollback restores volumes and refuses a corrupt archive" {
  seed_stack core
  id="$(bash "$CLI" backup 2>/dev/null | tail -n1)"

  echo "damaged-after-backup" > "$STACK_DIR/.volumes/db/marker"
  run bash "$CLI" rollback --skip-tests "$id"
  [ "$status" -eq 0 ]
  [ "$(cat "$STACK_DIR/.volumes/db/marker")" = "seeded-db-file" ]

  printf 'corrupt' >> "$OVA_HOME/backups/$id/volumes.tar.zst"
  echo "damaged-again" > "$STACK_DIR/.volumes/db/marker"
  run bash "$CLI" rollback "$id"
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  # Refusal happens before anything is deleted.
  [ "$(cat "$STACK_DIR/.volumes/db/marker")" = "damaged-again" ]
}

@test "rollback rejects an unknown backup id" {
  seed_stack core
  run bash "$CLI" rollback 19700101-000000Z
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such backup"* ]]
}

@test "profile resolution prefers init/.applied-profiles" {
  seed_stack core
  printf 'core\ngateway\n' > "$INIT_DIR/.applied-profiles"
  run bash "$CLI" test
  [[ "$output" == *"profiles: core gateway"* ]]
}

@test "profile resolution falls back to the generated header comment" {
  seed_stack edge
  rm -f "$INIT_DIR/.applied-profiles"
  run bash "$CLI" test
  [[ "$output" == *"profiles: edge"* ]]
}

@test "profile resolution falls back to the service list" {
  seed_stack core
  rm -f "$INIT_DIR/.applied-profiles"
  grep -v '^# Selected profiles:' "$STACK_DIR/docker-compose.yml" > "$STACK_DIR/stripped.yml"
  mv "$STACK_DIR/stripped.yml" "$STACK_DIR/docker-compose.yml"
  run bash "$CLI" test
  [[ "$output" == *"profiles: core"* ]]
}

@test "upgrade rewrites only the tag lines in .env" {
  seed_stack core
  write_manifest 9.9.9 9.1 9.2 9.3
  db_password_before="$(sed -n 's/^DEFGUARD_DB_PASSWORD=//p' "$STACK_DIR/.env")"

  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^DEFGUARD_CORE_TAG=//p' "$STACK_DIR/.env")" = "9.1" ]
  [ "$(sed -n 's/^DEFGUARD_PROXY_TAG=//p' "$STACK_DIR/.env")" = "9.2" ]
  [ "$(sed -n 's/^DEFGUARD_GATEWAY_TAG=//p' "$STACK_DIR/.env")" = "9.3" ]
  [ "$(sed -n 's/^DEFGUARD_DB_PASSWORD=//p' "$STACK_DIR/.env")" = "$db_password_before" ]
  [ "$(file_mode "$STACK_DIR/.env")" = "600" ]
}

@test "upgrade regenerates the compose file for the same profile set" {
  seed_stack core
  write_manifest
  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -eq 0 ]
  unset COMPOSE_PROFILES
  [ "$(docker compose -f "$STACK_DIR/docker-compose.yml" config --services | sort | xargs)" = "core db" ]
  [ ! -e "$STACK_DIR/active-profiles" ]
  [ "$(cat "$INIT_DIR/.applied-profiles")" = "core" ]
}

@test "upgrade command line tags override the manifest" {
  seed_stack core
  write_manifest 9.9.9 9 9 9
  run bash "$CLI" upgrade --yes --skip-tests --core-tag 3.3.3
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^DEFGUARD_CORE_TAG=//p' "$STACK_DIR/.env")" = "3.3.3" ]
  [ "$(sed -n 's/^DEFGUARD_PROXY_TAG=//p' "$STACK_DIR/.env")" = "9" ]
}

@test "upgrade records state.json" {
  seed_stack core
  write_manifest 2.1.7 2.1 2.1 2.1
  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ova_version' "$OVA_HOME/state.json")" = "2.1.7" ]
  [ "$(jq -r '.template_ref' "$OVA_HOME/state.json")" = "test-ref" ]
  [ "$(jq -r '.tags.gateway' "$OVA_HOME/state.json")" = "2.1" ]
  [ "$(jq -r '.backup_id' "$OVA_HOME/state.json")" != "none" ]
}

@test "upgrade aborts without touching the stack when the fetched template is broken" {
  seed_stack core
  write_manifest
  broken="$(mktemp -d)"
  mkdir -p "$broken/ova/files"
  cp "$FILES_DIR/lib.sh" "$FILES_DIR/generate-compose.sh" "$broken/ova/files/"
  echo "this: is: not: a: compose: file" > "$broken/ova/files/docker-compose.template.yaml"
  export DEFGUARD_OVA_SOURCE_DIR="$broken"
  before="$(sha256sum "$STACK_DIR/docker-compose.yml" | awk '{print $1}')"

  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not parse"* ]]
  [ "$(sha256sum "$STACK_DIR/docker-compose.yml" | awk '{print $1}')" = "$before" ]
  [ "$(ls -1 "$OVA_HOME/backups" | wc -l)" -eq 0 ]
  rm -rf "$broken"
}

@test "upgrade with an unreachable manifest changes nothing" {
  seed_stack core
  export DEFGUARD_OVA_MANIFEST_URL="file://$STACK_DIR/does-not-exist.json"
  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -ne 0 ]
  [ "$(ls -1 "$OVA_HOME/backups" | wc -l)" -eq 0 ]
}

@test "a failing health check exits non-zero and prints the rollback command" {
  seed_stack gateway
  write_manifest
  DOCKER_STUB_STATE=exited run bash "$CLI" upgrade --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"rollback"* ]]
  # The upgrade itself happened; only the verdict failed.
  [ -f "$OVA_HOME/state.json" ]
}

@test "--no-backup takes no backup" {
  seed_stack core
  write_manifest
  run bash "$CLI" upgrade --yes --skip-tests --no-backup
  [ "$status" -eq 0 ]
  [ "$(ls -1 "$OVA_HOME/backups" | wc -l)" -eq 0 ]
  [ "$(jq -r '.backup_id' "$OVA_HOME/state.json")" = "none" ]
}

@test "upgrade runs a pending migration and records it in state.json" {
  seed_stack core
  write_manifest 5.0.0 5 5 5 '["5.0.0"]'
  stage_migration 5.0.0 'echo "migrated $FROM_VERSION -> $TO_VERSION" > "$STACK_DIR/migration-ran"'

  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -eq 0 ]
  [[ "$output" == *"running migration 5.0.0"* ]]
  [ -f "$STACK_DIR/migration-ran" ]
  [[ "$(cat "$STACK_DIR/migration-ran")" == "migrated unknown -> 5.0.0" ]]
  [ "$(jq -r '.migrations_applied | join(",")' "$OVA_HOME/state.json")" = "5.0.0" ]
}

@test "upgrade does not re-run a migration already covered by the current version" {
  seed_stack core
  write_manifest 5.0.0 5 5 5 '["5.0.0"]'
  stage_migration 5.0.0 'echo ran >> "$STACK_DIR/migration-ran"'
  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$STACK_DIR/migration-ran")" -eq 1 ]
  teardown_migration_source

  write_manifest 6.0.0 6 6 6 '["5.0.0","6.0.0"]'
  # Only 6.0.0.sh is staged; if 5.0.0 were (wrongly) re-fetched, the upgrade
  # would fail outright since no such file exists here.
  stage_migration 6.0.0 'echo ran >> "$STACK_DIR/migration-ran"'
  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$STACK_DIR/migration-ran")" -eq 2 ]
  [ "$(jq -r '.migrations_applied | join(",")' "$OVA_HOME/state.json")" = "6.0.0" ]
}

@test "a failing migration aborts the upgrade before tags or compose change" {
  seed_stack core
  write_manifest 5.0.0 5 5 5 '["5.0.0"]'
  stage_migration 5.0.0 'exit 1'
  before="$(sha256sum "$STACK_DIR/docker-compose.yml" | awk '{print $1}')"

  run bash "$CLI" upgrade --yes --skip-tests
  [ "$status" -ne 0 ]
  [[ "$output" == *"migration 5.0.0 failed"* ]]
  [[ "$output" == *"rollback"* ]]
  [ "$(sed -n 's/^DEFGUARD_CORE_TAG=//p' "$STACK_DIR/.env")" = "2" ] # untouched, seeded before the manifest's "5"
  [ "$(sha256sum "$STACK_DIR/docker-compose.yml" | awk '{print $1}')" = "$before" ]
  # a backup was taken before the migration ran, so rollback is possible
  [ "$(ls -1 "$OVA_HOME/backups" | wc -l)" -eq 1 ]
}

@test "version reports installed and available versions" {
  seed_stack core
  write_manifest 4.5.6 4 4 4
  run bash "$CLI" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"core tag:       2"* ]]
  [[ "$output" == *"4.5.6"* ]]
}

@test "an unknown command fails with usage" {
  run bash "$CLI" definitely-not-a-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: dg-ctl"* ]]
}

@test "commands refuse to run outside a defguard stack" {
  run bash "$CLI" test
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not look like a defguard OVA host"* ]]
}
