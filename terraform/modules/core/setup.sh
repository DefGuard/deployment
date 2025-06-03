#!/usr/bin/env bash
set -e

LOG_FILE="/var/log/defguard.log"

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

generate_secret_inner() {
	local length="$1"
	openssl rand -base64 $${length} | tr -d "=+/" | tr -d '\n' | cut -c1-$${length-1} 
}

log "Updating apt repositories..."
sudo apt update | tee -a "$LOG_FILE"

log "Installing curl..."
sudo apt install -y curl | tee -a "$LOG_FILE"

log "Downloading defguard-core package..."
curl -fsSL -o /tmp/defguard-core.deb https://github.com/DefGuard/defguard/releases/download/v${package_version}/defguard-${package_version}-${arch}-unknown-linux-gnu.deb | tee -a "$LOG_FILE"

log "Installing defguard-core package..."
sudo dpkg -i /tmp/defguard-core.deb | tee -a "$LOG_FILE"

log "Writing core configuration to /etc/defguard/core.conf..."
sudo tee /etc/defguard/core.conf <<EOF | tee -a "$LOG_FILE"
### Core configuration ###
DEFGUARD_AUTH_SECRET=$(generate_secret_inner 64)
DEFGUARD_GATEWAY_SECRET=${gateway_secret}
DEFGUARD_YUBIBRIDGE_SECRET=$(generate_secret_inner 64)
DEFGUARD_SECRET_KEY=$(generate_secret_inner 64)
DEFGUARD_URL=${core_url}
# How long auth session lives in seconds
DEFGUARD_AUTH_SESSION_LIFETIME=604800
# Optional. Generated based on DEFGUARD_URL if not provided.
# DEFGUARD_WEBAUTHN_RP_ID=localhost
DEFGUARD_ADMIN_GROUPNAME=admin
DEFGUARD_DEFAULT_ADMIN_PASSWORD=${default_admin_password}
DEFGUARD_GRPC_PORT=${grpc_port}
DEFGUARD_HTTP_PORT=${http_port}
DEFGUARD_COOKIE_INSECURE=${cookie_insecure}

### Proxy configuration ###
# Optional. URL of proxy gRPC server
DEFGUARD_PROXY_URL=http://${proxy_address}:${proxy_grpc_port}
DEFGUARD_ENROLLMENT_URL=${proxy_url}

### DB configuration ###
DEFGUARD_DB_HOST="${db_address}"
DEFGUARD_DB_PORT=${db_port}
DEFGUARD_DB_NAME="${db_name}"
DEFGUARD_DB_USER="${db_username}"
DEFGUARD_DB_PASSWORD="${db_password}"
EOF

log "Enabling defguard service..."
sudo systemctl enable defguard | tee -a "$LOG_FILE"

log "Starting defguard service..."
sudo systemctl start defguard | tee -a "$LOG_FILE"

%{ for network in vpn_networks ~}
log "Creating VPN location ${network.name} with address ${network.address} and endpoint ${network.endpoint} and port ${network.port}..."
export $(grep -v '^#' /etc/defguard/core.conf | xargs) && /usr/bin/defguard --secret-key ${gateway_secret} init-vpn-location --name ${network.name} --address ${network.address} --endpoint ${network.endpoint} --port ${network.port} --id ${network.id} --allowed-ips ${network.address} >> "$LOG_FILE" 2>&1
log "Created VPN location ${network.name} with address ${network.address} and endpoint ${network.endpoint} and port ${network.port}"
%{ endfor ~}

log "Cleaning up after installing Defguard core..."
rm -f /tmp/defguard-core.deb | tee -a "$LOG_FILE"

log "Setup completed."
