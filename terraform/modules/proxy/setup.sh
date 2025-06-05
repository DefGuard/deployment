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
dpkg -i /tmp/defguard-proxy.deb

log "Writing proxy configuration to /etc/defguard/proxy.toml..."
tee /etc/defguard/proxy.toml <<EOF
# port the API server will listen on
http_port = ${http_port}
# port the gRPC server will listen on
grpc_port = ${grpc_port}

log_level = "${log_level}"
rate_limit_per_second = 0
rate_limit_burst = 0
url = "${proxy_url}"

EOF

log "Enabling defguard-proxy service..."
systemctl enable defguard-proxy

log "Starting defguard-proxy service..."
systemctl start defguard-proxy

log "Cleaning up after installing Defguard Proxy..."
rm -f /tmp/defguard-proxy.deb

log "Setup completed."
) 2>&1 | tee -a "$LOG_FILE"

