#!/bin/sh
# shellcheck shell=dash

# This is a script that sets up an entire defguard instance (including core, gateway, enrollment proxy
# and reverse proxy). It's goal is to prepare a working instance by running a single command.
#
# It should create a `gateway` directory in current directory, which will contain a `docker-compose.yml` file.

set -o errexit  # abort on nonzero exitstatus
set -o pipefail # don't hide errors within pipes

# Global variables
VERSION="0.1.0"
LOCAL_ENV_FILE=".env"
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"
SECRET_LENGTH=64
PASSWORD_LENGTH=16
WORK_DIR_NAME="defguard"
SSL_DIR="${WORK_DIR_NAME}/.volumes/ssl"
RSA_DIR="${WORK_DIR_NAME}/.volumes/core"
BASE_COMPOSE_FILE_URL="https://raw.githubusercontent.com/DefGuard/deployment/main/docker-compose/docker-compose.yaml"
CORE_IMAGE_TAG="latest"
GATEWAY_IMAGE_TAG="latest"
PROXY_IMAGE_TAG="latest"

main() {
	print_header

	# check if necessary tools are available
	check_environment

	# load variables from `.env` file if available
	if [ -f $LOCAL_ENV_FILE ]; then
		echo "Loading environment variables from ${LOCAL_ENV_FILE} file"
		export $(cat $LOCAL_ENV_FILE | sed 's/#.*//g' | xargs)
		print_confirmation
	fi

	# load configuration from env variables
	load_configuration

	# create working directory
	current_dir=$(pwd)
	WORK_DIR_PATH="${current_dir}/${WORK_DIR_NAME}"
	echo "Creating working directory at ${WORK_DIR_PATH}"
	mkdir -p ${WORK_DIR_NAME}
	print_confirmation

	# setup RSA & SSL keys
	setup_keys

	# generate base docker-compose file
	PROD_COMPOSE_FILE="${WORK_DIR_PATH}/${COMPOSE_FILE}"
	if [ -f $PROD_COMPOSE_FILE ]; then
		echo "Using existing docker-compose file at ${PROD_COMPOSE_FILE}"
		USE_EXISTING_COMPOSE=1
		print_confirmation
	else
		write_base_compose_file
	fi

	# save `.env` file for docker-compose
	PROD_ENV_FILE="${WORK_DIR_PATH}/${ENV_FILE}"
	if [ -f $PROD_ENV_FILE ]; then
		echo "Using existing ${ENV_FILE} file."
		print_confirmation
	else
		create_env_file
	fi

	# create VPN location

	# get gateway token

	# add gateway token to .env file

	# add enrollment service to compose file if enabled
	if [ $CFG_ENROLLMENT_DOMAIN ] && ! [ $USE_EXISTING_COMPOSE ]; then
		enable_enrollment
	fi

	# generate caddyfile

	# start docker-compose stack
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" up -d
	if [ $? -ne 0 ]; then
	  echo >&2 "ERROR: failed to start docker-compose stack"
		exit 1
	fi

	# print out instance info summary for user
	print_instance_summary
}

### HELPER FUNCTIONS ###
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
	if [ $? == 0 ]; then
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

	print_confirmation
}

load_configuration() {
	echo "Loading configuration from environment variables"
	# required variables
	check_required_variable "DEFGUARD_DOMAIN"
	CFG_DOMAIN="$DEFGUARD_DOMAIN"
	check_required_variable "DEFGUARD_VPN_NAME"
	CFG_VPN_NAME="$DEFGUARD_VPN_NAME"
	check_required_variable "DEFGUARD_VPN_IP"
	CFG_VPN_IP="$DEFGUARD_VPN_IP"
	check_required_variable "DEFGUARD_VPN_GATEWAY_IP"
	CFG_VPN_GATEWAY_IP="$DEFGUARD_VPN_GATEWAY_IP"
	check_required_variable "DEFGUARD_VPN_GATEWAY_PORT"
	CFG_VPN_GATEWAY_PORT="$DEFGUARD_VPN_GATEWAY_PORT"

	# optional variables
	CFG_ENROLLMENT_DOMAIN="$DEFGUARD_ENROLLMENT_DOMAIN"
	CFG_USE_HTTPS="$DEFGUARD_USE_HTTPS"

	# prepare full defguard URL
	if [ $CFG_USE_HTTPS ]; then
		CFG_DEFGUARD_URL="https://${CFG_DOMAIN}"
	else
		CFG_DEFGUARD_URL="http://${CFG_DOMAIN}"
	fi

	# prepare full enrollment URL
	if [ $CFG_ENROLLMENT_DOMAIN ]; then
		if [ $CFG_USE_HTTPS ]; then
			CFG_ENROLLMENT_URL="https://${CFG_ENROLLMENT_DOMAIN}"
		else
			CFG_ENROLLMENT_URL="http://${CFG_ENROLLMENT_DOMAIN}"
		fi
	fi

	print_confirmation
}

check_required_variable() {
	local var_name="$1"
	if [ -z ${!var_name+x} ]; then
		echo >&2 "ERROR: ${var_name} variable not set"
		exit 1
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

	echo "PEM pass phrase for set to '${PASSPHRASE}'."

	openssl genrsa -des3 -out ${SSL_DIR}/myCA.key -passout pass:"${PASSPHRASE}" 2048
	openssl req -x509 -new -nodes -key ${SSL_DIR}/myCA.key -sha256 -days 1825 -out ${SSL_DIR}/myCA.pem -passin pass:"${PASSPHRASE}" -subj "/C=PL/ST=Zachodniopomorskie/L=Szczecin/O=Example/OU=IT Department/CN=example.com"
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

write_base_compose_file() {
	echo "Writing base compose file to ${PROD_COMPOSE_FILE}"

	tee -a "${PROD_COMPOSE_FILE}" >/dev/null <<EOF
version: "3"

services:
  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: defguard
      POSTGRES_USER: defguard
      POSTGRES_PASSWORD: \${DEFGUARD_DB_PASSWORD}
    volumes:
      - ./.volumes/db:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  core:
    image: ghcr.io/defguard/defguard:${CORE_IMAGE_TAG}
    environment:
      DEFGUARD_AUTH_SECRET: \${DEFGUARD_AUTH_SECRET}
      DEFGUARD_GATEWAY_SECRET: \${DEFGUARD_GATEWAY_SECRET}
      DEFGUARD_YUBIBRIDGE_SECRET: \${DEFGUARD_YUBIBRIDGE_SECRET}
      DEFGUARD_SECRET_KEY: \${DEFGUARD_SECRET_KEY}
      DEFGUARD_DB_HOST: db
      DEFGUARD_DB_PORT: 5432
      DEFGUARD_DB_USER: defguard
      DEFGUARD_DB_PASSWORD: \${DEFGUARD_DB_PASSWORD}
      DEFGUARD_DB_NAME: defguard
      DEFGUARD_URL: \${DEFGUARD_URL}
      DEFGUARD_LOG_LEVEL: info
      DEFGUARD_WEBAUTHN_RP_ID: \${DEFGUARD_WEBAUTHN_RP_ID}
      # DEFGUARD_ENROLLMENT_URL: \${DEFGUARD_ENROLLMENT_URL}  # [ENROLLMENT]
      DEFGUARD_GRPC_CERT: /ssl/defguard.crt
      DEFGUARD_GRPC_KEY: /ssl/defguard.key
      DEFGUARD_OPENID_KEY: /keys/rsakey.pem

    ports:
      # web
      - "8000:8000"
      # grpc
      - "50055:50055"
    depends_on:
      - db
    volumes:
      - ./.volumes/ssl:/ssl
      - ./.volumes/core/rsakey.pem:/keys/rsakey.pem
EOF

	print_confirmation
}

create_env_file() {
	echo "Creating ${ENV_FILE} file for compose stack"

	# create base file
	tee -a "$PROD_ENV_FILE" >/dev/null <<EOF
DEFGUARD_AUTH_SECRET=
DEFGUARD_YUBIBRIDGE_SECRET=
DEFGUARD_GATEWAY_SECRET=
DEFGUARD_SECRET_KEY=
DEFGUARD_DB_PASSWORD=
DEFGUARD_URL=
DEFGUARD_WEBAUTHN_RP_ID=
# DEFGUARD_ENROLLMENT_URL=  # [ENROLLMENT]
DEFGUARD_GATEWAY_TOKEN=
EOF

	# fill in values
	set_env_file_secret "DEFGUARD_AUTH_SECRET"
	set_env_file_secret "DEFGUARD_YUBIBRIDGE_SECRET"
	set_env_file_secret "DEFGUARD_GATEWAY_SECRET"
	set_env_file_secret "DEFGUARD_SECRET_KEY"
	set_env_file_password "DEFGUARD_DB_PASSWORD"

	set_env_file_value "DEFGUARD_URL" "${CFG_DEFGUARD_URL}"
	set_env_file_value "DEFGUARD_WEBAUTHN_RP_ID" "${CFG_DOMAIN}"

	print_confirmation
}

set_env_file_value() {
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
	echo "Adding enrollment service to compose file"

	# update .env file
	uncomment_feature "ENROLLMENT" ${PROD_ENV_FILE}
	set_env_file_value "DEFGUARD_ENROLLMENT_URL" "${CFG_ENROLLMENT_URL}"

	# update compose file
	uncomment_feature "ENROLLMENT" ${PROD_COMPOSE_FILE}
	tee -a "${PROD_COMPOSE_FILE}" >/dev/null <<EOF

  enrollment:
    image: ghcr.io/defguard/defguard-proxy:${PROXY_IMAGE_TAG}
    environment:
      DEFGUARD_PROXY_UPSTREAM_GRPC_URL: http://core:50055/
      DEFGUARD_PROXY_GRPC_CA: /ssl/defguard-ca.pem
    volumes:
      - ./.volumes/ssl:/ssl
    ports:
      # web
      - "8080:8080"
    depends_on:
      - core
EOF

	print_confirmation
}

print_instance_summary() {
	echo
	echo "defguard setup finished successfully"
	echo "If your DNS configuration is correct your defguard instance should be available at:"
	echo
	echo -e "\tWeb UI: ${CFG_DEFGUARD_URL}"
	if [ $CFG_ENROLLMENT_DOMAIN ]; then
		echo -e "\tEnrollment service: ${CFG_ENROLLMENT_URL}"
	fi
	echo
	echo "You can log into the UI using the default admin user:"
	echo
	echo -e "\tusername: admin"
	echo -e "\tpassword: pass123"
	echo
	echo "Files used to deploy your instance are stored in ${WORK_DIR_PATH}"

}

# run main function
main "$@" || exit 1
