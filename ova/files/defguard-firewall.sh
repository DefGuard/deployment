#!/bin/bash
# Docker sets the FORWARD policy to DROP and only accepts its own bridges, which
# drops the gateway's decrypted WireGuard traffic before it can be forwarded.

set -u

SYSCTL_DIR="${DEFGUARD_SYSCTL_DIR:-/etc/sysctl.d}"

# Docker enables net.ipv4.ip_forward itself, but not IPv6 forwarding.
cat > "$SYSCTL_DIR/99-defguard-forward.conf" <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system >/dev/null

# DOCKER-USER only exists once dockerd has set up its chains; this may race
# docker.service. Wait briefly, then bail cleanly (next boot re-applies).
for _ in $(seq 1 30); do
  if iptables -n -L DOCKER-USER >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! iptables -n -L DOCKER-USER >/dev/null 2>&1; then
  echo "DefGuard: DOCKER-USER chain not present; skipping (Docker not ready)."
  exit 0
fi

for ipt in iptables ip6tables; do
  for dir in "-i" "-o"; do
    "$ipt" -C DOCKER-USER "$dir" wg+ -j ACCEPT 2>/dev/null \
      || "$ipt" -I DOCKER-USER "$dir" wg+ -j ACCEPT
  done
done

echo "DefGuard: wg+ forwarding whitelisted in DOCKER-USER."
