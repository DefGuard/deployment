#!/usr/bin/env bash
set -e

LOG_FILE="/var/log/defguard.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log "Updating apt repositories..."
sudo apt update | tee -a "$LOG_FILE"

log "Installing curl..."
sudo apt install -y curl | tee -a "$LOG_FILE"

log "Downloading defguard-proxy package..."
curl -fsSL -o /tmp/defguard-proxy.deb https://github.com/DefGuard/proxy/releases/download/v${package_version}/defguard-proxy-${package_version}-${arch}-unknown-linux-gnu.deb | tee -a "$LOG_FILE"

log "Installing defguard-proxy package..."
sudo dpkg -i /tmp/defguard-proxy.deb | tee -a "$LOG_FILE"

log "Writing proxy configuration to /etc/defguard/proxy.toml..."
sudo tee /etc/defguard/proxy.toml <<EOF | tee -a "$LOG_FILE"
# port the API server will listen on
http_port = ${http_port}
# port the gRPC server will listen on
grpc_port = ${grpc_port}

log_level = "info"
rate_limit_per_second = 0
rate_limit_burst = 0
url = "${proxy_url}"

EOF

log "Enabling defguard-proxy service..."
sudo systemctl enable defguard-proxy | tee -a "$LOG_FILE"

log "Starting defguard-proxy service..."
sudo systemctl start defguard-proxy | tee -a "$LOG_FILE"

log "Cleaning up after installing Defguard proxy..."
rm -f /tmp/defguard-proxy.deb | tee -a "$LOG_FILE"

log "Setup completed."
