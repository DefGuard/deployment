#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/prometheus-grafana-setup.log"
(
  echo "$(date '+%Y-%m-%d %H:%M:%S') Installing Prometheus and Grafana..."
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y ca-certificates curl gnupg openssl prometheus

  install -d -o root -g prometheus -m 0750 /etc/prometheus
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

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/grafana.gpg
  chmod 0644 /etc/apt/keyrings/grafana.gpg
  cat >/etc/apt/sources.list.d/grafana.list <<'GRAFANA_REPOSITORY'
deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main
GRAFANA_REPOSITORY

  apt update
  apt install -y grafana

  install -d -o grafana -g grafana -m 0755 /etc/grafana/provisioning/datasources
  install -d -o grafana -g grafana -m 0755 /etc/grafana/provisioning/dashboards
  cat >/etc/grafana/provisioning/datasources/prometheus.yml <<'DATASOURCE'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: false
DATASOURCE

  cat >/etc/grafana/provisioning/dashboards/defguard.yml <<'DASHBOARD_PROVIDER'
apiVersion: 1
providers:
  - name: Defguard monitoring
    orgId: 1
    folder: Defguard
    type: file
    disableDeletion: true
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards/defguard
DASHBOARD_PROVIDER

  install -d -o grafana -g grafana -m 0755 /var/lib/grafana/dashboards/defguard
%{ for filename, content in dashboard_files ~}
  cat >/var/lib/grafana/dashboards/defguard/${filename} <<'DASHBOARD_JSON'
${content}
DASHBOARD_JSON
%{ endfor ~}
  chown -R grafana:grafana /var/lib/grafana/dashboards/defguard /etc/grafana/provisioning

  systemctl enable grafana-server
  systemctl restart grafana-server

  if [[ ! -s /root/grafana-admin-password ]]; then
    password=""
    if [[ -n "${grafana_admin_password_b64}" ]]; then
      password="$(printf '%s' '${grafana_admin_password_b64}' | base64 -d)"
    fi
    if [[ -z "$password" ]]; then
      password="$(openssl rand -hex 24)"
    fi
    systemctl stop grafana-server
    chown -R grafana:grafana /var/lib/grafana
    runuser -u grafana -- env \
      GF_PATHS_DATA=/var/lib/grafana \
      GF_PATHS_LOGS=/var/log/grafana \
      GF_PATHS_PLUGINS=/var/lib/grafana/plugins \
      GF_PATHS_PROVISIONING=/etc/grafana/provisioning \
      /usr/share/grafana/bin/grafana cli \
        --config /etc/grafana/grafana.ini \
        --homepath /usr/share/grafana \
        admin reset-admin-password "$password"
    printf '%s\n' "$password" >/root/grafana-admin-password
    chmod 0600 /root/grafana-admin-password
    systemctl start grafana-server
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') Prometheus and Grafana setup completed."
) 2>&1 | tee -a "$LOG_FILE"
