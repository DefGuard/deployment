#!/usr/bin/env bash
set -e

LOG_FILE="/var/log/defguard.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

(
log "Installing prerequisites..."
apt update
apt install -y ca-certificates curl

log "Adding the Defguard APT repository..."
# The repo serves two suites: trixie (glibc >= 2.39, e.g. Ubuntu 24.04 / Debian 13) and
# bookworm (older glibc, e.g. Ubuntu 22.04 / Debian 12). Pick the one matching this host to
# avoid the known GLIBC_2.39 incompatibility.
. /etc/os-release
case "$VERSION_CODENAME" in
    noble | trixie) apt_dist="trixie" ;;
    *) apt_dist="bookworm" ;;
esac
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.defguard.net/defguard.asc -o /etc/apt/keyrings/defguard.asc
chmod a+r /etc/apt/keyrings/defguard.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/defguard.asc] https://apt.defguard.net/ $apt_dist release-2.0" >/etc/apt/sources.list.d/defguard.list
apt update

log "Installing defguard-gateway package..."
%{ if package_version != "" ~}
apt install -y defguard-gateway=${package_version}
%{ else ~}
apt install -y defguard-gateway
%{ endif ~}

log "Ensuring certificate directory exists..."
mkdir -p /etc/defguard/certs

log "Writing gateway configuration to /etc/defguard/gateway.toml..."
tee /etc/defguard/gateway.toml <<EOF
# Defguard VPN gateway configuration (2.0)

# Port the gRPC server listens on. Core connects here to adopt and manage the gateway.
grpc_port = ${grpc_port}
# Name of the WireGuard interface
ifname = "wg0"
# How often interface stat updates are sent to Core (in seconds)
stats_period = 30
# Use userspace WireGuard implementation (e.g. wireguard-go)
userspace = false
# Directory where adoption-provisioned mTLS certificates are stored
cert_dir = "/etc/defguard/certs"
# Enable automatic masquerading of traffic by the firewall
masquerade = ${nat}
log_level = "${log_level}"

# Optional: HTTP port exposing gateway health status (200 connected, 503 not connected)
# health_port = 55003
EOF

%{ if nat ~}
  log "Enabling IP forwarding for NAT (IPv4)..."
  sysctl -w net.ipv4.ip_forward=1
  grep -q -e '^net.ipv4.ip_forward' /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf

  log "Enabling IP forwarding for NAT (IPv6)..."
  sysctl -w net.ipv6.conf.all.forwarding=1
  grep -q -e '^net.ipv6.conf.all.forwarding' /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding = 1" | tee -a /etc/sysctl.conf
%{ endif ~}

log "Reloading systemd daemon to apply changes..."
systemctl daemon-reload

log "Enabling defguard-gateway service..."
systemctl enable defguard-gateway

log "Starting defguard-gateway service..."
systemctl start defguard-gateway

log "Setup completed."
) 2>&1 | tee -a "$LOG_FILE"
