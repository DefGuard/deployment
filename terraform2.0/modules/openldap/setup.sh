#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/defguard-openldap.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

(
log "Installing OpenLDAP..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y debconf-utils

base_dn="$(printf '%s' '${ldap_domain}' | awk -F. '{for (i=1; i<=NF; i++) {printf "%sdc=%s", (i>1 ? "," : ""), $i}}')"
cat >/tmp/slapd-debconf <<EOF
slapd slapd/domain string ${ldap_domain}
slapd shared/organization string ${ldap_organization}
slapd slapd/password1 password ${ldap_admin_password}
slapd slapd/password2 password ${ldap_admin_password}
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/no_configuration boolean false
EOF
debconf-set-selections /tmp/slapd-debconf
rm -f /tmp/slapd-debconf
apt install -y slapd ldap-utils prometheus-node-exporter prometheus-process-exporter

log "Configuring LDAP listeners..."
sed -ri 's#^SLAPD_SERVICES=.*#SLAPD_SERVICES="ldap:/// ldapi:///"#' /etc/default/slapd
systemctl enable --now slapd
systemctl enable --now prometheus-node-exporter prometheus-process-exporter

for _ in $(seq 1 30); do
  if ldapsearch -x -H "ldap://127.0.0.1:${ldap_port}" -D "cn=admin,$${base_dn}" -w '${ldap_admin_password}' -b "$${base_dn}" -s base >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
ldapsearch -x -H "ldap://127.0.0.1:${ldap_port}" -D "cn=admin,$${base_dn}" -w '${ldap_admin_password}' -b "$${base_dn}" -s base >/dev/null
log "OpenLDAP setup completed. Base DN: $${base_dn}"
) 2>&1 | tee -a "$LOG_FILE"
