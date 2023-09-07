#!/bin/sh
# shellcheck shell=bash

# This is a script that sets up an entire defguard instance (including core, gateway, enrollment proxy
# and reverse proxy). It's goal is to prepare a working instance by running a single command.
#
# It saves all the relevant files in the current directory and creates a `.volumes` subdirectory for storing
# persistent data.

set -o errexit  # abort on nonzero exitstatus
set -o pipefail # don't hide errors within pipes

# Global variables
VERSION="0.1.0"
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"
SECRET_LENGTH=64
PASSWORD_LENGTH=16
SSL_DIR=".volumes/ssl"
RSA_DIR=".volumes/core"
BASE_COMPOSE_FILE_URL="https://raw.githubusercontent.com/DefGuard/deployment/main/docker-compose/docker-compose.yaml"
BASE_ENV_FILE_URL="https://raw.githubusercontent.com/DefGuard/deployment/main/docker-compose/.env.template"
CORE_IMAGE_TAG="latest"
GATEWAY_IMAGE_TAG="latest"
PROXY_IMAGE_TAG="latest"

#####################
### MAIN FUNCTION ###
#####################

main() {
	print_header

	# check if necessary tools are available
	check_environment

	# load variables from `.env` file if available
	if [ -f $ENV_FILE ]; then
		echo "Loading configuration environment variables from ${ENV_FILE} file"
		export $(cat "$ENV_FILE" | sed 's/#.*//g' | xargs)
		print_confirmation
	fi

	# load configuration from env variables
	load_configuration_from_env

	# TODO: load configuration from CLI options

	# TODO: load configuration from user inputs

	# check that all required configuration options are set
	validate_required_variables

	# generate external service URLs based on config
	generate_external_urls

	# set current working directory
	WORK_DIR_PATH=$(pwd)
	echo "Using working directory ${WORK_DIR_PATH}"
	print_confirmation

	# setup RSA & SSL keys
	setup_keys

	# generate caddyfile
	create_caddyfile

	# generate `.env` file
	generate_env_file

	# generate base docker-compose file
	PROD_COMPOSE_FILE="${WORK_DIR_PATH}/${COMPOSE_FILE}"
	if [ -f "$PROD_COMPOSE_FILE" ]; then
		echo "Using existing docker-compose file at ${PROD_COMPOSE_FILE}"
		print_confirmation
	else
		fetch_base_compose_file
	fi

	# enable enrollment service in compose file
	if [ "$CFG_ENABLE_ENROLLMENT" ]; then
		enable_enrollment
	fi

	# enable and setup VPN gateway
	if [ "$CFG_ENABLE_VPN" ]; then
		enable_vpn_gateway
	fi

	# start docker-compose stack
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" up -d
	if [ $? -ne 0 ]; then
		echo >&2 "ERROR: failed to start docker-compose stack"
		exit 1
	fi

	# print out instance info summary for user
	print_instance_summary
}

########################
### HELPER FUNCTIONS ###
########################

print_header() {
	echo
	echo "defguard deployment setup script v${VERSION}"
	echo "Copyright (C) 2023 teonite <https://teonite.com>"
	echo
}

print_confirmation() {
	echo "OK"
	echo
}

command_exists() {
	local command="$1"
	command -v "$command" >/dev/null 2>&1
}

command_exists_check() {
	local command="$1"
	if ! command_exists "$command"; then
		echo >&2 "ERROR: $command command not found"
		echo >&2 "ERROR: dependency failed, exiting..."
		exit 1
	fi
}

check_environment() {
	echo "Checking if all required tools are available"
	# compose can be provided by newer docker versions or a separate docker-compose
	docker compose version >/dev/null 2>&1
	if [ $? = 0 ]; then
		COMPOSE_CMD="docker compose"
	else
		if command_exists docker-compose; then
			COMPOSE_CMD="docker-compose"
		else
			echo >&2 "ERROR: docker-compose or docker compose command not found"
			echo >&2 "ERROR: dependency failed, exiting..."
			exit 1
		fi
	fi

	command_exists_check openssl
	command_exists_check curl
	command_exists_check grep

	print_confirmation
}

load_configuration_from_env() {
	echo "Loading configuration from environment variables"
	# required variables
	CFG_DOMAIN="$DEFGUARD_DOMAIN"

	# optional variables
	CFG_VPN_NAME="$DEFGUARD_VPN_NAME"
	CFG_VPN_IP="$DEFGUARD_VPN_IP"
	CFG_VPN_GATEWAY_IP="$DEFGUARD_VPN_GATEWAY_IP"
	CFG_VPN_GATEWAY_PORT="$DEFGUARD_VPN_GATEWAY_PORT"
	CFG_ENROLLMENT_DOMAIN="$DEFGUARD_ENROLLMENT_DOMAIN"
	CFG_USE_HTTPS="$DEFGUARD_USE_HTTPS"

	print_confirmation
}

check_required_variable() {
	local var_name="$1"
	if [ -z "${!var_name}" ]; then
		echo >&2 "ERROR: ${var_name} configuration option not set"
		exit 1
	fi
}

validate_required_variables() {
	echo "Validating configuration options"
	check_required_variable "CFG_DOMAIN"

	# if VPN name is given validate other VPN configurations are present
	if [ "$CFG_VPN_NAME" ]; then
		CFG_ENABLE_VPN=1
		check_required_variable "CFG_VPN_IP"
		check_required_variable "CFG_VPN_GATEWAY_IP"
		check_required_variable "CFG_VPN_GATEWAY_PORT"
	fi

	print_confirmation
}

generate_external_urls() {
	# prepare full defguard URL
	if [ "$CFG_USE_HTTPS" ]; then
		CFG_DEFGUARD_URL="https://${CFG_DOMAIN}"
	else
		CFG_DEFGUARD_URL="http://${CFG_DOMAIN}"
	fi

	# prepare full enrollment URL
	if [ "$CFG_ENROLLMENT_DOMAIN" ]; then
		CFG_ENABLE_ENROLLMENT=1
		if [ "$CFG_USE_HTTPS" ]; then
			CFG_ENROLLMENT_URL="https://${CFG_ENROLLMENT_DOMAIN}"
		else
			CFG_ENROLLMENT_URL="http://${CFG_ENROLLMENT_DOMAIN}"
		fi
	fi
}

setup_keys() {
	echo "Setting up SSL certs and RSA keys"
	if [ -d ${SSL_DIR} ] && [ "$(ls -A ${SSL_DIR})" ]; then
		echo "Using existing SSL certificates from ${SSL_DIR}."
	else
		generate_certs
	fi

	if [ -d ${RSA_DIR} ] && [ "$(ls -A ${RSA_DIR})" ]; then
		echo "Using existing RSA keys from ${RSA_DIR}."
	else
		generate_rsa
	fi

	print_confirmation
}

generate_certs() {
	echo "Creating new SSL certificates in ${SSL_DIR}..."
	mkdir -p ${SSL_DIR}

	PASSPHRASE=$(generate_secret)

	echo "PEM pass phrase for SSL certificates set to '${PASSPHRASE}'."

	openssl genrsa -des3 -out ${SSL_DIR}/defguard-ca.key -passout pass:"${PASSPHRASE}" 2048
	openssl req -x509 -new -nodes -key ${SSL_DIR}/defguard-ca.key -sha256 -days 1825 -out ${SSL_DIR}/defguard-ca.pem -passin pass:"${PASSPHRASE}" -subj "/C=PL/ST=Zachodniopomorskie/L=Szczecin/O=Example/OU=IT Department/CN=example.com"
}

generate_rsa() {
	echo "Generating RSA keys in ${RSA_DIR}..."
	mkdir -p ${RSA_DIR}
	openssl genpkey -out ${RSA_DIR}/rsakey.pem -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -quiet
}

generate_secret() {
	generate_secret_inner "${SECRET_LENGTH}"
}

generate_password() {
	generate_secret_inner "${PASSWORD_LENGTH}"
}

generate_secret_inner() {
	local length="$1"
	openssl rand -base64 ${length} | tr -d "=+/" | tr -d '\n' | cut -c1-${length-1}
}

create_caddyfile() {
	caddy_volume_path="${WORK_DIR_PATH}/.volumes/caddy"
	caddyfile_path="${caddy_volume_path}/Caddyfile"
	mkdir -p ${caddy_volume_path}

	cat >${caddyfile_path} <<EOF
${CFG_DEFGUARD_URL} {
	reverse_proxy core:8000
}
EOF

	if [ "$CFG_ENABLE_ENROLLMENT" ]; then
		cat >>${caddyfile_path} <<EOF
${CFG_ENROLLMENT_URL} {
	reverse_proxy proxy:8080
}

EOF
	fi
}

fetch_base_compose_file() {
	echo "Fetching base compose file to ${PROD_COMPOSE_FILE}"

	curl --proto '=https' --tlsv1.2 -sSf "${BASE_COMPOSE_FILE_URL}" -o "${PROD_COMPOSE_FILE}"

	print_confirmation
}

generate_env_file() {
	PROD_ENV_FILE="${WORK_DIR_PATH}/${ENV_FILE}"
	if [ -f "$PROD_ENV_FILE" ]; then
		echo "Using existing ${ENV_FILE} file."
	else
		fetch_base_env_file
	fi
	update_env_file
	print_confirmation
}

fetch_base_env_file() {
	echo "Fetching base ${ENV_FILE} file for compose stack"

	curl --proto '=https' --tlsv1.2 -sSf "${BASE_ENV_FILE_URL}" -o "${PROD_ENV_FILE}"
}

update_env_file() {
	echo "Setting environment variables in ${ENV_FILE} file for compose stack"

	# set image versions
	set_env_file_value "CORE_IMAGE_TAG" "${CORE_IMAGE_TAG}"
	set_env_file_value "PROXY_IMAGE_TAG" "${PROXY_IMAGE_TAG}"
	set_env_file_value "GATEWAY_IMAGE_TAG" "${GATEWAY_IMAGE_TAG}"

	# fill in values
	set_env_file_secret "DEFGUARD_AUTH_SECRET"
	set_env_file_secret "DEFGUARD_YUBIBRIDGE_SECRET"
	set_env_file_secret "DEFGUARD_GATEWAY_SECRET"
	set_env_file_secret "DEFGUARD_SECRET_KEY"
	set_env_file_password "DEFGUARD_DB_PASSWORD"

	# generate an admin password to display later
	ADMIN_PASSWORD="$(generate_password)"
	set_env_file_value "DEFGUARD_DEFAULT_ADMIN_PASSWORD" "${ADMIN_PASSWORD}"

	set_env_file_value "DEFGUARD_URL" "${CFG_DEFGUARD_URL}"
	set_env_file_value "DEFGUARD_WEBAUTHN_RP_ID" "${CFG_DOMAIN}"
}

set_env_file_value() {
	# make sure variable exists in file
	grep -qF "${1}=" "${PROD_ENV_FILE}" || echo "${1}=" >>"${PROD_ENV_FILE}"
	sed -i~ "s@\(${1}\)=.*@\1=${2}@" "${PROD_ENV_FILE}"
}

set_env_file_secret() {
	set_env_file_value "${1}" "$(generate_secret)" "${PROD_ENV_FILE}"
}

set_env_file_password() {
	set_env_file_value "${1}" "$(generate_password)" "${PROD_ENV_FILE}"
}

uncomment_feature() {
	sed -i~ "s@# \(.*\) # \[${1}\]@\1@" "${2}"
}

enable_enrollment() {
	echo "Enabling enrollment proxy service in compose file"

	# update .env file
	uncomment_feature "ENROLLMENT" "${PROD_ENV_FILE}"
	set_env_file_value "DEFGUARD_ENROLLMENT_URL" "${CFG_ENROLLMENT_URL}"

	# update compose file
	uncomment_feature "ENROLLMENT" "${PROD_COMPOSE_FILE}"

	print_confirmation
}

enable_vpn_gateway() {
	echo "Enabling VPN gateway service"

	uncomment_feature "VPN" "${PROD_COMPOSE_FILE}"
	uncomment_feature "VPN" "${PROD_ENV_FILE}"

	# create VPN location
	token=$($COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" run core init-vpn-location --name "${CFG_VPN_NAME}" --address "${CFG_VPN_IP}" --endpoint "${CFG_VPN_GATEWAY_IP}" --port "${CFG_VPN_GATEWAY_PORT}" --dns "8.8.8.8" --allowed-ips "0.0.0.0/0")
	if [ $? -ne 0 ]; then
		echo >&2 "ERROR: failed to create VPN network"
		exit 1
	fi

	# add gateway token to .env file
	set_env_file_value "DEFGUARD_TOKEN" "${token}"

	print_confirmation
}

print_instance_summary() {
	echo
	echo "defguard setup finished successfully"
	echo "If your DNS configuration is correct your defguard instance should be available at:"
	echo
	echo -e "\tWeb UI: ${CFG_DEFGUARD_URL}"
	if [ "$CFG_ENABLE_ENROLLMENT" ]; then
		echo -e "\tEnrollment service: ${CFG_ENROLLMENT_URL}"
	fi
	echo
	echo "You can log into the UI using the default admin user:"
	echo
	echo -e "\tusername: admin"
	echo -e "\tpassword: ${ADMIN_PASSWORD}"
	echo
	echo "Files used to deploy your instance are stored in ${WORK_DIR_PATH}"
	echo "Persistent data is stored in ${WORK_DIR_PATH}/.volumes"

}

# run main function
main "$@" || exit 1
