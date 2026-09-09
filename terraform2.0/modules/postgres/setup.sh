#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/defguard-postgres.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

(
log "Installing PostgreSQL..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y postgresql

config_file=$(find /etc/postgresql -path '*/main/postgresql.conf' -print -quit)
hba_file=$(find /etc/postgresql -path '*/main/pg_hba.conf' -print -quit)
if [[ -z "$config_file" || -z "$hba_file" ]]; then
  log "PostgreSQL configuration files were not found"
  exit 1
fi

log "Configuring PostgreSQL to accept VPC connections..."
sed -ri "s/^#?listen_addresses\s*=.*/listen_addresses = '*'/" "$config_file"
echo "host ${db_name} ${db_username} ${vpc_cidr} scram-sha-256" >> "$hba_file"
systemctl restart postgresql

for _ in $(seq 1 30); do
  if sudo -u postgres pg_isready -q; then
    break
  fi
  sleep 1
done
sudo -u postgres pg_isready -q

log "Creating Defguard database and role..."
sudo -u postgres psql --set=ON_ERROR_STOP=1 \
  --set=db_name="${db_name}" \
  --set=db_username="${db_username}" \
  --set=db_password="${db_password}" <<'SQL'
CREATE ROLE :"db_username" LOGIN PASSWORD :'db_password';
CREATE DATABASE :"db_name" OWNER :"db_username";
SQL

log "PostgreSQL setup completed."
) 2>&1 | tee -a "$LOG_FILE"
