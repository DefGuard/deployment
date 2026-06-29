#!/usr/bin/env bash
set -e

LOG_FILE="/var/log/defguard.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

(
log "Updating apt repositories..."
apt update

log "Installing curl..."
apt install -y curl

log "Downloading defguard-gateway package..."
curl -fsSL -o /tmp/defguard-gateway.deb https://github.com/DefGuard/gateway/releases/download/v${package_version}/defguard-gateway-${package_version}-${arch}-unknown-linux-gnu.deb

log "Installing defguard-gateway package..."
# apt-get resolves the deb's dependencies (dpkg -i would not).
apt-get install -y /tmp/defguard-gateway.deb

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

log "Cleaning up after installing Defguard Gateway..."
rm -f /tmp/defguard-gateway.deb

log "Setup completed."
) 2>&1 | tee -a "$LOG_FILE"
