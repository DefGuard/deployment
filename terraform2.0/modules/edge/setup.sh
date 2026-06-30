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

log "Installing defguard-proxy package..."
%{ if package_version != "" ~}
apt install -y defguard-proxy=${package_version}
%{ else ~}
apt install -y defguard-proxy
%{ endif ~}

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

log "Setup completed."
) 2>&1 | tee -a "$LOG_FILE"
