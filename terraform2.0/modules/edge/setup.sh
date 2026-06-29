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

log "Downloading defguard-proxy package..."
curl -fsSL -o /tmp/defguard-proxy.deb https://github.com/DefGuard/proxy/releases/download/v${package_version}/defguard-proxy-${package_version}-${arch}-unknown-linux-gnu.deb

log "Installing defguard-proxy package..."
# apt-get resolves the deb's dependencies (dpkg -i would not).
apt-get install -y /tmp/defguard-proxy.deb

# The edge runs as the 'defguard' user, so the cert dir must be writable by it.
log "Ensuring certificate directory exists..."
mkdir -p /etc/defguard/certs
chown -R defguard:defguard /etc/defguard/certs

log "Writing edge configuration to /etc/defguard/proxy.toml..."
tee /etc/defguard/proxy.toml <<EOF
# Defguard Edge (proxy) configuration (2.0)

# Port the API/enrollment HTTP server listens on
http_port = ${http_port}
# Port the HTTPS server listens on (used after Core provisions TLS)
https_port = ${https_port}
# Port the gRPC server listens on. Core connects here to adopt and manage the edge.
grpc_port = ${grpc_port}
# Directory where adoption-provisioned mTLS certificates are stored
cert_dir = "/etc/defguard/certs"

log_level = "${log_level}"
rate_limit_per_second = 0
rate_limit_burst = 0
# acme_staging = false
EOF

chown defguard:defguard /etc/defguard/proxy.toml

log "Enabling defguard-proxy service..."
systemctl enable defguard-proxy

log "Starting defguard-proxy service..."
systemctl start defguard-proxy

log "Cleaning up after installing Defguard Edge..."
rm -f /tmp/defguard-proxy.deb

log "Setup completed."
) 2>&1 | tee -a "$LOG_FILE"
