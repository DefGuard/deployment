#!/usr/bin/env bash
set -e

LOG_FILE="/var/log/defguard.log"

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Wait until a TCP host:port accepts connections, up to a bounded number of attempts.
# Core auto-adoption runs once on startup with a short per-target timeout and no retry,
# so the gateway and edge gRPC servers must be listening before core starts.
wait_for_port() {
	local host="$1"
	local port="$2"
	local attempts="$3"
	local i=0
	while [ "$i" -lt "$attempts" ]; do
		if timeout 2 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
			log "Reachable: $host:$port"
			return 0
		fi
		i=$((i + 1))
		sleep 5
	done
	log "WARNING: $host:$port not reachable after $attempts attempts; auto-adoption may fail"
	return 1
}

(
log "Updating apt repositories..."
apt update

log "Installing curl..."
apt install -y curl

log "Downloading defguard-core package..."
curl -fsSL -o /tmp/defguard-core.deb https://github.com/DefGuard/defguard/releases/download/v${package_version}/defguard-${package_version}-${arch}-unknown-linux-gnu.deb

log "Installing defguard-core package..."
# apt-get resolves the deb's dependencies (dpkg -i would not).
apt-get install -y /tmp/defguard-core.deb

log "Writing Core configuration to /etc/defguard/core.conf..."
tee /etc/defguard/core.conf <<EOF
### Core configuration ###
DEFGUARD_GRPC_PORT=${grpc_port}
DEFGUARD_HTTP_PORT=${http_port}
DEFGUARD_HTTP_BIND_ADDRESS=0.0.0.0
DEFGUARD_GRPC_BIND_ADDRESS=0.0.0.0
DEFGUARD_COOKIE_INSECURE=${cookie_insecure}
DEFGUARD_LOG_LEVEL=${log_level}

### Auto-adoption ###
# If the gateway host is a private IP, set the WireGuard location endpoint in the Core web UI
# after adoption so external clients can connect.
DEFGUARD_ADOPT_GATEWAY=${gateway_address}:${gateway_grpc_port}
DEFGUARD_ADOPT_EDGE=${edge_address}:${edge_grpc_port}

### DB configuration ###
DEFGUARD_DB_HOST="${db_address}"
DEFGUARD_DB_PORT=${db_port}
DEFGUARD_DB_NAME="${db_name}"
DEFGUARD_DB_USER="${db_username}"
DEFGUARD_DB_PASSWORD="${db_password}"
EOF

chown defguard:defguard /etc/defguard/core.conf
chmod 640 /etc/defguard/core.conf

log "Waiting for gateway and edge gRPC servers to become reachable..."
wait_for_port "${gateway_address}" "${gateway_grpc_port}" 60 || true
wait_for_port "${edge_address}" "${edge_grpc_port}" 60 || true

log "Enabling Defguard service..."
systemctl enable defguard

log "Starting Defguard service..."
systemctl start defguard

log "Cleaning up after installing Defguard Core..."
rm -f /tmp/defguard-core.deb

log "Setup completed."
) 2>&1 | tee -a "$LOG_FILE"
