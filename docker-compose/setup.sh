#!/usr/bin/env bash
# shellcheck shell=bash

# This is a script that sets up an entire defguard instance (including core, gateway, enrollment proxy
# and reverse proxy). It's goal is to prepare a working instance by running a single command.
#
# It saves all the relevant files in the current directory and creates a `.volumes` subdirectory for storing
# persistent data.

set -o errexit  # abort on nonzero exitstatus
set -o pipefail # don't hide errors within pipes

# Global variables
VERSION="0.1.1"
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"
SECRET_LENGTH=64
PASSWORD_LENGTH=16
SSL_DIR=".volumes/ssl"
RSA_DIR=".volumes/core"
BASE_COMPOSE_FILE_URL="https://raw.githubusercontent.com/DefGuard/deployment/main/docker-compose/docker-compose.yaml"
BASE_ENV_FILE_URL="https://raw.githubusercontent.com/DefGuard/deployment/main/docker-compose/.env.template"
CORE_IMAGE_TAG="${CORE_IMAGE_TAG:-latest}"
GATEWAY_IMAGE_TAG="${GATEWAY_IMAGE_TAG:-latest}"
PROXY_IMAGE_TAG="${PROXY_IMAGE_TAG:-latest}"

#####################
### MAIN FUNCTION ###
#####################

main() {
	print_header

	# display help `--help` argument is found
	for i in $*; do
		test "$i" == "--help" && print_usage && exit 0
		# run script in non-interactive mode
		test "$i" == "--non-interactive" && CFG_NON_INTERACTIVE=1
		test "$i" == "--use-https" && CFG_USE_HTTPS=1
	done

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

	# load configuration from CLI options
	load_configuration_from_cli "$@"

	# load configuration from user inputs
	if ! [ $CFG_NON_INTERACTIVE ]; then
		load_configuration_from_input
	fi

	# check that all required configuration options are set
	validate_required_variables

	# generate external service URLs based on config
	generate_external_urls

	# print out config
	print_config

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

	# enable reverse proxy in compose file
	uncomment_feature "PROXY" "${PROD_COMPOSE_FILE}"

	# enable enrollment service in compose file
	if [ "$CFG_ENABLE_ENROLLMENT" ]; then
		enable_enrollment
	fi

	# fetch latest images
	echo "Fetching latest Docker images"
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" pull
	print_confirmation

	# enable and setup VPN gateway
	if [ "$CFG_ENABLE_VPN" ]; then
		enable_vpn_gateway
	fi

	# start docker-compose stack
	echo "Starting docker-compose stack"
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" up -d
	if [ $? -ne 0 ]; then
		echo >&2 "ERROR: failed to start docker-compose stack"
		exit 1
	fi
	print_confirmation

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

print_usage() {

	echo "Usage: ${BASENAME} [options]"
	echo
	echo 'Available options:'
	echo
	echo -e "\t--help                         this help message"
	echo -e "\t--non-interactive              run in non-interactive mode (no user input)"
	echo -e "\t--domain <domain>              domain where defguard web UI will be available"
	echo -e "\t--enrollment-domain <domain>   domain where enrollment service will be available"
	echo -e "\t--use-https                    configure reverse proxy to use HTTPS"
	echo -e "\t--vpn-name <name>              VPN location name"
	echo -e "\t--vpn-ip <address>             VPN server address & netmask (e.g. 10.0.50.1/24)"
	echo -e "\t--vpn-gateway-ip <ip>          VPN gateway external IP"
	echo -e "\t--vpn-gateway-port <port>      VPN gateway external port"
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

load_configuration_from_cli() {
	echo "Loading configuration from CLI arguments"

	ARGUMENT_LIST=(
		"domain"
		"enrollment-domain"
		"vpn-name"
		"vpn-ip"
		"vpn-gateway-ip"
		"vpn-gateway-port"
	)

	# read arguments
	opts=$(
		getopt \
			--longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
			--name "$(basename "$0")" \
			--options "" \
			-- "$@"
	)

	eval set --$opts

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--domain)
			CFG_DOMAIN=$2
			shift 2
			;;

		--enrollment-domain)
			CFG_ENROLLMENT_DOMAIN=$2
			shift 2
			;;

		--vpn-name)
			CFG_VPN_NAME=$2
			shift 2
			;;

		--vpn-ip)
			CFG_VPN_IP=$2
			shift 2
			;;

		--vpn-gateway-ip)
			CFG_VPN_GATEWAY_IP=$2
			shift 2
			;;

		--vpn-gateway-port)
			CFG_VPN_GATEWAY_PORT=$2
			shift 2
			;;

		*)
			break
			;;
		esac
	done

	print_confirmation
}

load_configuration_from_input() {
	echo "#################################################################################"
	echo
	echo "We'll now ask you to provide a couple values to configure your defguard instance."
	echo
	echo "If you've already configured some options by setting environment variables or through CLI options,"
	echo "those values will be used as defaults."
	echo
	echo "If you prefer to disable this user input section, please restart the script with --non-interactive CLI flag."
	echo

	echo "### DOMAINS ###"
	echo
	echo "Please choose the domains that will be used to expose your instance through Caddy reverse proxy."
	echo "We use a separate domain for the main Web UI and for the optional enrollment service."
	echo "If you don't provide any domain for the enrollment service, the service itself will not be deployed."
	echo
	echo "You can also enable HTTPS here (highly recommended), which will configure Caddy to automatically"
	echo "provision SSL certificates."
	echo "Please note that this requires you server to have a public IP address and public DNS records"
	echo "for your chosen domains to be configured correctly (pointing to your server's IP)."
	echo

	read -p "Enter defguard domain [default: ${CFG_DOMAIN}]: " value
	if [ "$value" ]; then
		CFG_DOMAIN="$value"
	fi

	read -p "Enter enrollment domain [default: ${CFG_ENROLLMENT_DOMAIN}]: " value
	if [ "$value" ]; then
		CFG_ENROLLMENT_DOMAIN="$value"
	fi

	use_https_bool_value="false"
	if [ $CFG_USE_HTTPS ]; then use_https_bool_value="true"; fi
	read -p "Use HTTPS [default: ${use_https_bool_value}]: " value
	if [ "$value" ]; then
		CFG_USE_HTTPS=1
	fi

	echo
	echo "### VPN ###"
	echo
	echo "We'll now try to configure your own Wireguard VPN gateway."
	echo "If you don't choose a VPN location name this step will be skipped"
	echo "and a gateway will not be deployed."
	echo

	read -p "Enter VPN location name [default: ${CFG_VPN_NAME}]: " value
	if [ "$value" ]; then
		CFG_VPN_NAME="$value"
	fi

	if [ "$CFG_VPN_NAME" ]; then
		read -p "Enter VPN server address and subnet (e.g. 10.0.60.1/24) [default: ${CFG_VPN_IP}]: " value
		if [ "$value" ]; then
			CFG_VPN_IP="$value"
		fi

		echo
		echo "Now we'll configure a public endpoint (IP + port) that your Wireguard"
		echo "client devices will use to safely connect to your gateway from the public internet."
		echo
		echo "Since we'll be starting the gateway on this server the IP should"
		echo "be the same as your server's public IP."
		echo "Please also remember that your firewall should be configured"
		echo "to allow incoming UDP traffic on the chosen Wireguard port."
		echo

		read -p "Enter VPN gateway public IP [default: ${CFG_VPN_GATEWAY_IP}]: " value
		if [ "$value" ]; then
			CFG_VPN_GATEWAY_IP="$value"
		fi

		read -p "Enter VPN gateway public port [default: ${CFG_VPN_GATEWAY_PORT}]: " value
		if [ "$value" ]; then
			CFG_VPN_GATEWAY_PORT="$value"
		fi
	fi

	echo
	echo "Thank you. We'll now proceed with the deployment using provided values."

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

print_config() {
	echo "Setting up your defguard instance with following config:"
	echo "Domain: ${CFG_DOMAIN}"
	echo "Web UI URL: ${CFG_DEFGUARD_URL}"

	if [ "$CFG_VPN_NAME" ]; then
		echo "VPN location name: ${CFG_VPN_NAME}"
		echo "VPN address: ${CFG_VPN_IP}"
		echo "VPN gateway IP: ${CFG_VPN_GATEWAY_IP}"
		echo "VPN gateway port: ${CFG_VPN_GATEWAY_PORT}"
	fi

	if [ "$CFG_ENROLLMENT_DOMAIN" ]; then
		echo "Enrollment service domain: ${CFG_ENROLLMENT_DOMAIN}"
		echo "Enrollment service URL: ${CFG_ENROLLMENT_URL}"
	fi

	echo
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
	#	TODO: allow configuring CA parameters
	openssl req -x509 -new -nodes -key ${SSL_DIR}/defguard-ca.key -sha256 -days 1825 -out ${SSL_DIR}/defguard-ca.pem -passin pass:"${PASSPHRASE}" -subj "/C=PL/ST=Zachodniopomorskie/L=Szczecin/O=Example/OU=IT Department/CN=example.com"
}

generate_rsa() {
	echo "Generating RSA keys in ${RSA_DIR}..."
	mkdir -p ${RSA_DIR}
	openssl genpkey -out ${RSA_DIR}/rsakey.pem -algorithm RSA -pkeyopt rsa_keygen_bits:2048
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

	cat >>${caddyfile_path} <<EOF
:80 {
    respond 404
}
:443 {
    respond 404
}

EOF
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
	sed -i "s@\(${1}\)=.*@\1=${2}@" "${PROD_ENV_FILE}"
}

set_env_file_secret() {
	set_env_file_value "${1}" "$(generate_secret)" "${PROD_ENV_FILE}"
}

set_env_file_password() {
	set_env_file_value "${1}" "$(generate_password)" "${PROD_ENV_FILE}"
}

uncomment_feature() {
	sed -i "s@# \(.*\) # \[${1}\]@\1@" "${2}"
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

	# fetch latest image
	echo "Fetching latest gateway image"
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" pull gateway

	# create VPN location
	token=$($COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" run core init-vpn-location --name "${CFG_VPN_NAME}" --address "${CFG_VPN_IP}" --endpoint "${CFG_VPN_GATEWAY_IP}" --port "${CFG_VPN_GATEWAY_PORT}" --allowed-ips "0.0.0.0/0")
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
