#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl prometheus-node-exporter prometheus-process-exporter
systemctl enable --now prometheus-node-exporter prometheus-process-exporter
curl -fsSL https://get.docker.com | sh

install -d -m 0755 /opt/defguard-edge/certs
cat > /opt/defguard-edge/proxy.toml <<'CONFIG'
http_port = ${http_port}
https_port = ${https_port}
grpc_port = ${grpc_port}
cert_dir = "/etc/defguard/certs"
log_level = "${log_level}"
rate_limit_per_second = 0
rate_limit_burst = 0
CONFIG
cat > /opt/defguard-edge/docker-compose.yaml <<'COMPOSE'
services:
  edge:
    image: ${image}
    restart: unless-stopped
    volumes:
      - /opt/defguard-edge/certs:/etc/defguard/certs
      - /opt/defguard-edge/proxy.toml:/etc/defguard/proxy.toml:ro
    ports:
      - "${grpc_port}:${grpc_port}"
      - "${http_port}:${http_port}"
      - "${https_port}:${https_port}"
COMPOSE

docker compose -f /opt/defguard-edge/docker-compose.yaml pull
docker compose -f /opt/defguard-edge/docker-compose.yaml up -d
