#!/usr/bin/env bats
# iptables/ip6tables/sysctl/sleep are stubbed so only defguard-firewall.sh's
# rule logic is exercised, with no effect on the host firewall.

load helpers

setup() {
  BIN="$(mktemp -d)"
  cp "$STUB_DIR/iptables-stub" "$BIN/iptables"
  cp "$STUB_DIR/iptables-stub" "$BIN/ip6tables"
  cp "$STUB_DIR/noop" "$BIN/sysctl"
  cp "$STUB_DIR/noop" "$BIN/sleep"
  chmod +x "$BIN"/*
  export PATH="$BIN:$PATH"
  export IPT_STUB_LOG="$BIN/ipt.log"
  : > "$IPT_STUB_LOG"
  export DEFGUARD_SYSCTL_DIR="$BIN/sysctl.d"
  mkdir "$DEFGUARD_SYSCTL_DIR"
}

teardown() {
  rm -rf "$BIN"
}

inserts() {
  grep -c -- '-I DOCKER-USER' "$IPT_STUB_LOG"
}

@test "whitelists wg+ in/out for both iptables and ip6tables" {
  run bash "$FILES_DIR/defguard-firewall.sh"
  [ "$status" -eq 0 ]
  [ "$(inserts)" -eq 4 ]
  grep -q -- 'iptables -I DOCKER-USER -i wg+ -j ACCEPT' "$IPT_STUB_LOG"
  grep -q -- 'iptables -I DOCKER-USER -o wg+ -j ACCEPT' "$IPT_STUB_LOG"
  grep -q -- 'ip6tables -I DOCKER-USER -i wg+ -j ACCEPT' "$IPT_STUB_LOG"
  grep -q -- 'ip6tables -I DOCKER-USER -o wg+ -j ACCEPT' "$IPT_STUB_LOG"
}

@test "writes the forwarding sysctl drop-in" {
  run bash "$FILES_DIR/defguard-firewall.sh"
  [ "$status" -eq 0 ]
  conf="$DEFGUARD_SYSCTL_DIR/99-defguard-forward.conf"
  [ -f "$conf" ]
  grep -qx 'net.ipv4.ip_forward = 1' "$conf"
  grep -qx 'net.ipv6.conf.all.forwarding = 1' "$conf"
}

@test "idempotent: no inserts when the rules already exist" {
  IPT_RULE_EXISTS=1 run bash "$FILES_DIR/defguard-firewall.sh"
  [ "$status" -eq 0 ]
  [ "$(inserts)" -eq 0 ]
}

@test "exits cleanly without inserts when DOCKER-USER is absent" {
  IPT_CHAIN_EXISTS=0 run bash "$FILES_DIR/defguard-firewall.sh"
  [ "$status" -eq 0 ]
  [ "$(inserts)" -eq 0 ]
}
