#!/bin/sh
# shellcheck shell=dash

# This is a script that sets up an entire defguard instance (including core, gateway, enrollment proxy
# and reverse proxy). It's goal is to prepare a working instance by running a single command.
#
# It should create a `gateway` directory in current directory, which will contain a `docker-compose.yml` file.

set -o errexit  # abort on nonzero exitstatus
set -o nounset  # abort on unbound variable
set -o pipefail # don't hide errors within pipes

# Global variables
VERSION="0.1.0"
ENV_FILE=".env"
LOCAL_ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"
SECRET_LENGTH=64
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
	work_dir_path="${current_dir}/${WORK_DIR_NAME}"
	echo "Creating working directory at ${work_dir_path}"
	mkdir -p ${WORK_DIR_NAME}
	print_confirmation

	# setup RSA & SSL keys
	setup_keys

	# generate base docker-compose file
	compose_file_path="${work_dir_path}/${COMPOSE_FILE}"
	if [ -f $compose_file_path ]; then
		echo >&2 "ERROR: docker-compose file exists already at ${compose_file_path}"
		exit 1
	fi
	write_base_compose_file $compose_file_path

	# generate base docker-compose file

	# save `.env` file for docker-compose

	# create VPN location

	# get gateway token

	# add gateway token to .env file

	# add enrollment service to compose file if enabled

	# generate caddyfile

	# start docker-compose stack

	# print out instance info summary for user

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
	DOCKER_COMPOSE=$(docker compose version >/dev/null 2>&1)
	if [ $? -ne 0 ] && ! command_exists docker-compose; then
		echo >&2 "ERROR: docker-compose or docker compose command not found"
		echo >&2 "ERROR: dependency failed, exiting..."
		exit 1
	fi

	command_exists_check openssl

	print_confirmation
}

load_configuration() {
	domain=

	vpn_name=
	vpn_network=
	vpn_endpoint=

	enable_enrollment=
	enrollment_domain=
	use_https=
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

function generate_secret
{
	openssl rand -base64 ${SECRET_LENGTH} | tr -d "=+/" | tr -d '\n' | cut -c1-${SECRET_LENGTH-1}
}

write_base_compose_file() {
	local path="$1"
	echo "Writing base compose file to $path"

	tee -a "$path" >/dev/null <<EOF
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
      DEFGUARD_ENROLLMENT_URL: \${DEFGUARD_ENROLLMENT_URL}
      DEFGUARD_GRPC_CERT: /ssl/defguard.crt
      DEFGUARD_GRPC_KEY: /ssl/defguard.key

    ports:
      # web
      - "80:8000"
      # grpc
      - "50055:50055"
    depends_on:
      - db
    volumes:
      - ./.volumes/ssl:/ssl
EOF

	print_confirmation
}

# run main function
main "$@" || exit 1
