#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/prometheus-setup.log"
(
  echo "$(date '+%Y-%m-%d %H:%M:%S') Installing Prometheus..."
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y prometheus

  cat >/etc/prometheus/prometheus.yml <<'PROMETHEUS_CONFIG'
global:
  scrape_interval: ${scrape_interval}
  evaluation_interval: ${scrape_interval}

scrape_configs:
%{ for job, targets in scrape_targets ~}
  - job_name: "${job}"
    static_configs:
      - targets:
%{ for target in targets ~}
          - "${target}"
%{ endfor ~}
%{ endfor ~}
PROMETHEUS_CONFIG

  chown root:prometheus /etc/prometheus/prometheus.yml
  chmod 0640 /etc/prometheus/prometheus.yml
  systemctl enable prometheus
  systemctl restart prometheus
  echo "$(date '+%Y-%m-%d %H:%M:%S') Prometheus setup completed."
) 2>&1 | tee -a "$LOG_FILE"
