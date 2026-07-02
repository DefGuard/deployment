#!/bin/bash
# Boot the defguard OVA on Proxmox once per deployment mode and assert the right
# components come up. Meant to run ON the Proxmox host (invoked over SSH by CI).
# Usage: test-deployment-modes.sh /path/to/defguard.ova
set -euo pipefail

OVA="${1:?usage: $0 /path/to/defguard.ova}"

PVE_STORAGE="${PVE_STORAGE:-local-zfs}"
PVE_BRIDGE="${PVE_BRIDGE:-vmbr0}"
SNIPPET_STORAGE="${SNIPPET_STORAGE:-local}"
SNIPPET_DIR="${SNIPPET_DIR:-/var/lib/vz/snippets}"

# The template takes VMID_BASE; the four test VMs take the next four IDs. Shift the whole
# block with VMID_BASE if that range is not free on the node.
VMID_BASE="${VMID_BASE:-9000}"
TEMPLATE_VMID="$VMID_BASE"

# Static IPs: the image has no guest agent, so there is no DHCP lease to query; a known
# IP per VM is how we reach it.
TEST_IP_PREFIX="${TEST_IP_PREFIX:-10.2.0}"
TEST_GW="${TEST_GW:-10.2.0.1}"
TEST_CIDR="${TEST_CIDR:-24}"

BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
# Generous: the stack pulls images from ghcr on first boot.
STACK_TIMEOUT="${STACK_TIMEOUT:-600}"

MODES=(full core edge gateway)
declare -A VMID=(       [full]=$((VMID_BASE+1)) [core]=$((VMID_BASE+2)) [edge]=$((VMID_BASE+3)) [gateway]=$((VMID_BASE+4)) )
declare -A IP_LAST=(    [full]=150  [core]=151  [edge]=152  [gateway]=153  )
declare -A PROFILE=(    [full]=""   [core]=core [edge]=edge [gateway]=gateway )
# Ground truth from ova/files/docker-compose.standalone.yaml (full uses the all-in-one).
declare -A EXPECT=(     [full]="core db edge gateway" [core]="core db"      [edge]="edge"          [gateway]="gateway" )
declare -A FORBID=(     [full]=""                     [core]="edge gateway" [edge]="core db gateway" [gateway]="core db edge" )

declare -A RESULT

WORKDIR="$(mktemp -d)"
KEY="$WORKDIR/id"
PUBKEY="$WORKDIR/id.pub"

# VMs this script creates are named with this prefix; nothing else is ever touched.
VM_PREFIX="defguard-test"

log() { echo "[test] $*"; }

vm_exists() { sudo qm status "$1" &>/dev/null; }
vm_name()   { sudo qm config "$1" 2>/dev/null | sed -n 's/^name: //p'; }
is_ours()   { [[ "$(vm_name "$1")" == "$VM_PREFIX"* ]]; }

destroy_vm() {
  local v="$1"
  vm_exists "$v" || return 0
  is_ours "$v" || { log "refusing to touch VMID $v ('$(vm_name "$v")'): not created by this script"; return 0; }
  sudo qm stop "$v" --skiplock &>/dev/null || true
  sudo qm destroy "$v" --purge &>/dev/null || true
}

# Abort before doing anything if one of our IDs is already a foreign VM.
guard_vmids() {
  local v
  for v in "$TEMPLATE_VMID" "${VMID[@]}"; do
    if vm_exists "$v" && ! is_ours "$v"; then
      log "ERROR: VMID $v is in use by '$(vm_name "$v")'. Set VMID_BASE to a free range."
      exit 2
    fi
  done
}

cleanup() {
  for m in "${MODES[@]}"; do destroy_vm "${VMID[$m]}"; done
  destroy_vm "$TEMPLATE_VMID"
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

vm_ssh() {
  local ip="$1"; shift
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -o BatchMode=yes "cloudtest@$ip" "$@"
}

# A running service shows up as a "-<service>-" token in compose container names.
has_service() { grep -q -- "-$2-" <<<"$1"; }

wait_ssh() {
  local ip="$1" deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  until vm_ssh "$ip" true 2>/dev/null; do
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 10
  done
}

wait_services() {
  local ip="$1" expected="$2" deadline=$(( $(date +%s) + STACK_TIMEOUT )) names svc ok
  while :; do
    # sudo: the fresh cloudtest user is not in the docker group.
    names="$(vm_ssh "$ip" "sudo docker ps --format '{{.Names}}'" 2>/dev/null || true)"
    ok=1
    for svc in $expected; do has_service "$names" "$svc" || ok=0; done
    [ "$ok" = 1 ] && return 0
    [ "$(date +%s)" -ge "$deadline" ] && { echo "$names"; return 1; }
    sleep 10
  done
}

verify_mode() {
  local mode="$1" ip="$2" profile="${PROFILE[$mode]}" names actual

  if [ -z "$profile" ]; then
    vm_ssh "$ip" "test ! -e /opt/stacks/defguard/active-profiles" \
      || { log "$mode: active-profiles unexpectedly present"; return 1; }
  else
    actual="$(vm_ssh "$ip" "cat /opt/stacks/defguard/active-profiles 2>/dev/null" | tr -d '[:space:]')"
    [ "$actual" = "$profile" ] \
      || { log "$mode: active-profiles is '$actual', expected '$profile'"; return 1; }
  fi

  names="$(wait_services "$ip" "${EXPECT[$mode]}")" \
    || { log "$mode: expected services did not all start; running: $(tr '\n' ' ' <<<"$names")"; return 1; }

  local svc
  for svc in ${FORBID[$mode]}; do
    has_service "$names" "$svc" \
      && { log "$mode: unexpected service '$svc' is running"; return 1; }
  done
  return 0
}

import_template() {
  log "importing OVA as template $TEMPLATE_VMID"
  destroy_vm "$TEMPLATE_VMID"
  tar -xf "$OVA" -C "$WORKDIR"
  local vmdk import_out volid
  vmdk="$(find "$WORKDIR" -name '*.vmdk' | head -n1)"
  [ -n "$vmdk" ] || { log "no .vmdk found inside OVA"; return 1; }

  sudo qm create "$TEMPLATE_VMID" --name defguard-test-tpl --memory 2048 --cores 2 \
    --net0 "virtio,bridge=$PVE_BRIDGE" --scsihw virtio-scsi-single --ostype l26
  import_out="$(sudo qm importdisk "$TEMPLATE_VMID" "$vmdk" "$PVE_STORAGE" 2>&1)"
  echo "$import_out"
  volid="$(grep -oE "$PVE_STORAGE:[^ '\"]+" <<<"$import_out" | tail -n1)"
  [ -n "$volid" ] || { log "could not determine imported disk volume id"; return 1; }

  sudo qm set "$TEMPLATE_VMID" --scsi0 "$volid"
  sudo qm set "$TEMPLATE_VMID" --boot order=scsi0
  sudo qm set "$TEMPLATE_VMID" --ide2 "$PVE_STORAGE:cloudinit"
  sudo qm template "$TEMPLATE_VMID"
}

write_snippets() {
  local m
  for m in core edge gateway; do
    sudo tee "$SNIPPET_DIR/defguard-test-$m.yaml" >/dev/null <<EOF
#cloud-config
write_files:
  - path: /opt/stacks/defguard/active-profiles
    content: "$m"
EOF
  done
}

run_mode() {
  local mode="$1" vmid="${VMID[$mode]}" ip="$TEST_IP_PREFIX.${IP_LAST[$mode]}"
  log "=== mode: $mode (vmid $vmid, ip $ip) ==="
  destroy_vm "$vmid"
  sudo qm clone "$TEMPLATE_VMID" "$vmid" --name "defguard-test-$mode"
  # Inject a throwaway CI user via native cloud-init fields: the built-in `ubuntu`
  # account has an expired password (chage -d 0) which blocks even key-based SSH.
  sudo qm set "$vmid" --ciuser cloudtest --sshkeys "$PUBKEY" \
    --ipconfig0 "ip=$ip/$TEST_CIDR,gw=$TEST_GW"
  if [ -n "${PROFILE[$mode]}" ]; then
    sudo qm set "$vmid" \
      --cicustom "vendor=$SNIPPET_STORAGE:snippets/defguard-test-$mode.yaml"
  fi
  sudo qm start "$vmid"

  if ! wait_ssh "$ip"; then
    log "$mode: VM never became reachable over SSH (cloud-init/datasource issue?)"
    RESULT[$mode]=FAIL
  elif verify_mode "$mode" "$ip"; then
    log "$mode: PASS"
    RESULT[$mode]=PASS
  else
    RESULT[$mode]=FAIL
  fi
  destroy_vm "$vmid"
}

main() {
  guard_vmids
  ssh-keygen -t ed25519 -N '' -f "$KEY" -q
  import_template
  write_snippets

  for mode in "${MODES[@]}"; do run_mode "$mode"; done

  echo
  echo "==== deployment mode results ===="
  local failed=0
  for mode in "${MODES[@]}"; do
    printf '  %-8s %s\n' "$mode" "${RESULT[$mode]:-FAIL}"
    [ "${RESULT[$mode]:-FAIL}" = PASS ] || failed=1
  done
  [ "$failed" = 0 ] && log "all modes passed" || log "one or more modes failed"
  return "$failed"
}

main "$@"
