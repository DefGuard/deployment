#!/usr/bin/env bash
# shellcheck shell=bash

# This is a script that sets up an entire Defguard instance (including core,
# gateway, enrollment proxy and reverse proxy). It's goal is to prepare
# a working instance by running a single command.

set -o errexit  # abort on nonzero exitstatus
set -o pipefail # don't hide errors within pipes

# Global variables
VERSION="1.2.2"
SECRET_LENGTH=64
PASSWORD_LENGTH=16

VOLUME_DIR='.volumes'
SSL_DIR="${VOLUME_DIR}/ssl"
RSA_DIR="${VOLUME_DIR}/core"

COMPOSE_FILE='docker-compose.yaml'
ENV_FILE='.env'
LOG_FILE=$(mktemp setup.log.XXXXXX)

BASE_COMPOSE_FILE_URL='https://raw.githubusercontent.com/DefGuard/deployment/main/docker-compose/docker-compose.yaml'
BASE_ENV_FILE_URL='https://raw.githubusercontent.com/DefGuard/deployment/main/docker-compose/.env.template'

if [ "$(uname)" = 'Darwin' ]; then
	SED=(sed -i '')
else
	SED=(sed -i)
fi

#####################
### MAIN FUNCTION ###
#####################

main() {
	is_utf_term
	is_term_color
	tput reset
	print_header

	# display help `--help` argument is found
	for i in $*; do
		test "$i" = '--help' && print_usage && exit 0

		# run non interactive
		if [ "$i" = '--non-interactive' ]; then
			CFG_NON_INTERACTIVE=1
			# we need to remove this element from $* or getopt will return an error
			set -- $(remove_element "$i" $*)
		fi

		# configure https
		if [ "$i" = '--use-https' ]; then
			CFG_USE_HTTPS=1
			# we need to remove this element from $* or getopt will return an error
			set -- $(remove_element "$i" $*)
		fi
	done

	#
	# First let's gather the ENV/command line variables
	#

	# load configuration from env variables
	load_configuration_from_env

	# load configuration from CLI options
	load_configuration_from_cli "$@"

	# load configuration from user inputs
	if [ X$CFG_VOLUME_DIR != X ]; then
		VOLUME_DIR=${CFG_VOLUME_DIR}
		SSL_DIR="${VOLUME_DIR}/ssl"
		RSA_DIR="${VOLUME_DIR}/core"
	fi

	export VOLUME_DIR

	# set current working directory
	WORK_DIR_PATH=$(pwd)

	# set docker compose file directory
	PROD_COMPOSE_FILE="${WORK_DIR_PATH}/${COMPOSE_FILE}"

	# We have enough to check the enviromnent
	# so check if necessary tools are available
	check_environment

	# Set the correct docker image version based on passed arguments/env variables
	# either latest, pre-release or dev
	setup_docker_image_version

	# Print architecture for debugging purposes
	echo " ${TXT_BEGIN} Identified architecture as: $(uname -m)"

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

	# setup RSA & SSL keys
	setup_keys

	# generate caddyfile
	create_caddyfile

	# generate `.env` file
	generate_env_file

	# enable insecure cookies if not using HTTPS
	if ! [ "$CFG_USE_HTTPS" ]; then
		uncomment_feature "HTTP" "${PROD_ENV_FILE}"
	fi

	# generate base docker-compose file
	fetch_base_compose_file

	# enable reverse proxy in compose file
	uncomment_feature "PROXY" "${PROD_COMPOSE_FILE}"

	# enable enrollment service in compose file
	if [ "$CFG_ENABLE_ENROLLMENT" ]; then
		enable_enrollment
	fi

	# fetch latest images

	echo -e " ${TXT_BEGIN} Fetching ${IMAGE_TYPE_NAME} Docker images: "
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" pull

	# enable and setup VPN gateway
	if [ "$CFG_ENABLE_VPN" ]; then
		enable_vpn_gateway
	fi

	# start docker-compose stack
	echo " ${TXT_BEGIN} Starting docker-compose stack"
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" up -d
	if [ $? -ne 0 ]; then
		echo >&2 "ERROR: failed to start docker-compose stack"
		exit 1
	fi

	print_instance_summary
}

########################
### HELPER FUNCTIONS ###
########################

check_character_support() {
	local char="$1"
	echo -e "$char" | grep -q "$char"
}

is_utf_term() {
	if check_character_support "√"; then
		TXT_CHECK="✓"
		TXT_BEGIN="▶"
		TXT_SUB="▷"
		TXT_STAR="★"
		TXT_X="✗"
		TXT_INPUT="✍"
	else
		TXT_CHECK="+"
		TXT_BEGIN=">>"
		TXT_SUB=">"
		TXT_STAR="*"
		TXT_X="x"
		TXT_INPUT=" ::"
	fi
}

is_term_color() {
	if [[ $TERM == *"256"* ]]; then
		C_RED="\033[31m"
		C_GREEN="\033[32m"
		C_YELLOW="\033[33m"
		C_BLUE="\033[34m"
		C_WHITE="\033[37m"
		C_GREY="\033[90m"

		C_LRED="\033[91m"
		C_LGREEN="\033[92m"
		C_LYELLOW="\033[93m"
		C_LBLUE="\033[94m"

		C_BOLD="\033[1m"
		C_ITALICS="\033[3m"
		C_BG_GREY="\033[100m"
		C_END="\033[0m"
	else
		C_RED=""
		C_GREEN=""
		C_YELLOW=""
		C_BLUE=""
		C_WHITE=""
		C_GREY=""

		C_LRED=""
		C_LGREEN=""
		C_LYELLOW=""
		C_LBLUE=""

		C_BOLD=""
		C_ITALICS=""
		C_BG_GREY=""
		C_END=""
	fi
}

# remove array element
remove_element() {
	local remove=$1
	local result=()
	for element in "$@"; do
		if [ "$element" != "$remove" ]; then
			result+=("$element")
		fi
	done
	echo "${result[@]}"
}

# Function to convert relative path to absolute path
to_absolute_path() {
	local path="$1"
	if [ "${path:0:1}" != '/' ]; then
		path="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
	fi
	echo ${path}
}

print_header() {
	echo -e "${C_LBLUE}"
	cat <<_EOF_
           #
      ##   #
    ##  ## #        #              ##                                        #
  ##      ##        #             #         #                                #
  #   ##   #   #### #    ####   #####   ####    #     #    ####    ###  #### #
  # ##  ##    #    ##   #    ##   #    #    #   #     #   #    #  #    #    ##
  ##      ##  #     #  ########   #    #    #   #     #        #  #    #     #
  # ##  ## #  #     #  ##         #    #####    #     #   ######  #    #     #
  #   ##   #  #    ##   #     #   #    #        #     #  #     #  #    #    ##
  ##      ##   #### #    #####    #    #######   #### #   #### #  #     #### #
    ##  ## #                          #       #
      ##   #                           #######
          #
_EOF_
	echo -e "${C_END}"
	echo
	echo "Defguard docker-compose deployment setup script v${VERSION}"
	echo -e "Copyright ©2023-2025 ${C_BOLD}defguard sp. z o.o.${C_END} <${C_BG_GREY}${C_YELLOW}https://defguard.net/${C_END}>"
	echo
}

print_confirmation() {
	echo -e " ${C_LGREEN}${TXT_CHECK}${C_END} "
}

print_usage() {

	echo "Usage: ${BASENAME} [options]"
	echo
	echo 'Available options:'
	echo
	echo -e "\t--help                         this help message"
	echo -e "\t--non-interactive              run in non-interactive mode - !REQUIRES SETTING all options/env vars"
	echo -e "\t--domain <domain>              domain where Defguard web UI will be available"
	echo -e "\t--enrollment-domain <domain>   domain where enrollment service will be available"
	echo -e "\t--use-https                    configure reverse proxy to use HTTPS"
	echo -e "\t--volume <directory>           Docker volumes directory - default: ${VOLUME_DIR}"
	echo -e "\t--vpn-name <name>              VPN location name"
	echo -e "\t--vpn-ip <address>             VPN server address & netmask (e.g. 10.0.50.1/24)"
	echo -e "\t--vpn-gateway-ip <ip>          VPN gateway external IP (! NOT DOMAIN - IP)"
	echo -e "\t--vpn-gateway-port <port>      VPN gateway external port (your clients connect here)"
	echo -e "\t--dev                          use development images"
	echo -e "\t--pre-release                  use pre-release images"
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
		exit 2
	fi
}

check_environment() {
	echo -n " ${TXT_BEGIN} Checking if all required tools are available..."
	# compose can be provided by newer docker versions or a separate docker-compose
	docker compose version >/dev/null 2>&1
	if [ $? = 0 ]; then
		COMPOSE_CMD="docker compose"
	else
		if command_exists docker-compose; then
			COMPOSE_CMD="docker-compose"
		else
			echo
			echo >&2 "ERROR: docker-compose or docker compose command not found"
			echo >&2 "ERROR: dependency failed, exiting..."
			exit 3
		fi
	fi

	command_exists_check openssl
	command_exists_check curl
	command_exists_check grep

	# Check if the volume dir is an absolute path since docker requires it
	VOLUME_DIR=$(to_absolute_path "${VOLUME_DIR}")

	if [ -d ${VOLUME_DIR} ]; then
		echo
		echo >&2 "ERROR: volume directory: ${VOLUME_DIR} exists."
		echo >&2 "ERROR: this means the configuration, database and certificates would be overwritten."
		echo >&2 "ERROR: please backup or remove the volume directory."
		exit 3
	fi

	if [ -f "$PROD_COMPOSE_FILE" ]; then
		echo
		echo >&2 "ERROR: docker compose file: ${PROD_COMPOSE_FILE} already exists."
		echo >&2 "ERROR: this means the previous configuration would be overwritten."
		echo >&2 "ERROR: please backup or remove the docker compose file."
		exit 3
	fi

	# create all necessary directories
	for dir in ${VOLUME_DIR} ${SSL_DIR} ${RSA_DIR}; do
		mkdir ${dir}
		if [ $? -ne 0 ]; then
			echo >&2 "ERROR: cloud not create volume directory: ${dir}"
			exit 3
		fi
	done

	print_confirmation
}

setup_docker_image_version() {
	if [[ $CFG_DEV == 1 ]]; then
		IMAGE_TYPE_NAME="${C_RED}development${C_END}"
		CORE_IMAGE_TAG="dev"
		GATEWAY_IMAGE_TAG="dev"
		PROXY_IMAGE_TAG="dev"
	elif [[ $CFG_PRE_RELEASE == 1 ]]; then
		IMAGE_TYPE_NAME="${C_YELLOW}pre-release${C_END}"
		CORE_IMAGE_TAG="pre-release"
		GATEWAY_IMAGE_TAG="pre-release"
		PROXY_IMAGE_TAG="pre-release"
	else
		IMAGE_TYPE_NAME="${C_GREEN}latest production${C_END}"
		CORE_IMAGE_TAG="${CORE_IMAGE_TAG:-latest}"
		GATEWAY_IMAGE_TAG="${GATEWAY_IMAGE_TAG:-latest}"
		PROXY_IMAGE_TAG="${PROXY_IMAGE_TAG:-latest}"
	fi

	echo -e " ${TXT_BEGIN} ${IMAGE_TYPE_NAME} Docker images will be used"
}

load_configuration_from_env() {
	echo -n " ${TXT_BEGIN} Loading configuration from environment variables... "
	# required variables
	CFG_DOMAIN="$DEFGUARD_DOMAIN"

	# optional variables
	CFG_VOLUME_DIR="$DEFGUARD_VOLUME_DIR"
	CFG_VPN_NAME="$DEFGUARD_VPN_NAME"
	CFG_VPN_IP="$DEFGUARD_VPN_IP"
	CFG_VPN_GATEWAY_IP="$DEFGUARD_VPN_GATEWAY_IP"
	CFG_VPN_GATEWAY_PORT="$DEFGUARD_VPN_GATEWAY_PORT"
	CFG_ENROLLMENT_DOMAIN="$DEFGUARD_ENROLLMENT_DOMAIN"
	CFG_PRE_RELEASE="$DEFGUARD_PRE_RELEASE"
	CFG_DEV="$DEFGUARD_DEV"
	if ! [ $CFG_USE_HTTPS ]; then
		CFG_USE_HTTPS="$DEFGUARD_USE_HTTPS"
	fi

	print_confirmation
}

load_configuration_from_cli() {
	echo -n " ${TXT_BEGIN} Loading configuration from CLI arguments... "

	# ":" means that the option has to have an argument (e.g. --domain example.com)
	ARGUMENT_LIST=(
		"domain:"
		"enrollment-domain:"
		"volume:"
		"vpn-name:"
		"vpn-ip:"
		"vpn-gateway-ip:"
		"vpn-gateway-port:"
		"dev"
		"pre-release"
	)

	# read arguments
	opts=$(
		getopt \
			--longoptions "$(printf "%s," "${ARGUMENT_LIST[@]}")" \
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

		--volume)
			CFG_VOLUME_DIR=$2
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

		--pre-release)
			CFG_PRE_RELEASE=1
			shift
			;;

		--dev)
			CFG_DEV=1
			shift
			;;

		*)
			break
			;;
		esac
	done

	if [ $CFG_DEV ] && [ $CFG_PRE_RELEASE ]; then
		echo >&2 "ERROR: both --dev and --pre-release flags cannot be set at the same time. You can only either use the dev builds or the pre-release builds."
		exit 4
	fi

	print_confirmation
}

load_configuration_from_input() {
	echo -ne "${C_ITALICS}${C_LBLUE}"
	cat <<_EOF_

Please provide the values to configure your Defguard instance. If you've
already configured some options by setting environment variables or through
CLI options, those will be used as defaults.

If you prefer to disable this user input section, please restart the script
with --non-interactive CLI flag.

_EOF_

	echo -ne "${C_GREY}"
	cat <<_EOF_

Choose domains that will be used to expose your instance through Caddy
reverse proxy. Defguard uses a separate domain for the Web UI, and for
the optional enrollment/desktop client configuration/password reset
service.

If you don't provide any domain for the enrollment service, the service
itself will not be deployed.

You can also enable HTTPS here (highly recommended), which will configure
Caddy to automatically provision SSL certificates.
_EOF_

	echo -ne "${C_BOLD}"
	cat <<_EOF_

Please note that this requires your server to have a public IP address
and public DNS records for your chosen domains to be configured
correctly (pointing to your server's IP address).

_EOF_

	echo -ne "${C_END}"

	echo -e "  ${C_BOLD}${C_GREEN}${TXT_STAR} General config ${TXT_STAR}${C_END}\n"

	while [ X${domain} = "X" ]; do
		echo -ne "${C_YELLOW}${TXT_INPUT}${C_END} "
		read -p "Enter Defguard domain [default: ${CFG_DOMAIN}]: " domain
		if [ "$domain" ]; then
			CFG_DOMAIN="$domain"
		fi
	done

	echo -ne "${C_YELLOW}${TXT_INPUT}${C_END} "
	read -p "Enter enrollment domain [default: ${CFG_ENROLLMENT_DOMAIN}]: " enroll
	if [ "$enroll" ]; then
		CFG_ENROLLMENT_DOMAIN="$enroll"
	fi

	use_https_bool_value="false"
	if [ $CFG_USE_HTTPS ]; then use_https_bool_value="true"; fi
	echo -ne "${C_YELLOW}${TXT_INPUT}${C_END} "
	read -p "Use HTTPS [default: ${use_https_bool_value}]: " https
	if [ "$https" ]; then
		CFG_USE_HTTPS=1
	fi

	echo
	echo -e "  ${C_BOLD}${C_GREEN}${TXT_STAR} WireGuard VPN${TXT_STAR}${C_END}\n"

	echo -ne "${C_ITALICS}${C_GREY}"
	cat <<_EOF_

If you wish to configure and deploy WireGuard VPN gateway, please
provide your VPN location name. To skip, just press enter and VPN will
not be configured.
_EOF_

	echo -ne "${C_END}\n"

	echo -ne "${C_YELLOW}${TXT_INPUT}${C_END} "
	read -p "Enter VPN location name [default: ${CFG_VPN_NAME}]: " vpn_name
	if [ "$vpn_name" ]; then
		CFG_VPN_NAME="$vpn_name"
	fi

	if [ "$CFG_VPN_NAME" ]; then
		while [ X${vpn_ip} = "X" ]; do
			echo -ne "${C_YELLOW}${TXT_INPUT}${C_END} "
			read -p "Enter VPN server address and subnet (e.g. 10.0.60.1/24) [default: ${CFG_VPN_IP}]: " vpn_ip
			if [ "$vpn_ip" ]; then
				CFG_VPN_IP="$vpn_ip"
			fi
		done

		echo -ne "${C_ITALICS}${C_GREY}"
		cat <<_EOF_

Now we'll configure a public endpoint (IP + port) that your WireGuard
client devices will use to safely connect to your gateway from the
public internet.

Since we'll be starting the gateway on this server the IP address should
be the same as your server's public IP address.
_EOF_
		echo -ne "${C_BOLD}"
		cat <<_EOF_
Please also remember that your firewall should be configured
to allow incoming UDP traffic on the chosen WireGuard port.
_EOF_

		echo -ne "${C_END}"

		while [ X${public_ip} = "X" ]; do
			echo -ne "${C_YELLOW}${TXT_INPUT}${C_END} "
			read -p "Enter VPN gateway public IP (no domains!) [default: ${CFG_VPN_GATEWAY_IP}]: " public_ip
			if [ "$public_ip" ]; then
				CFG_VPN_GATEWAY_IP="$public_ip"
			fi
		done

		while [ X${public_port} = "X" ]; do
			echo -ne "${C_YELLOW}${TXT_INPUT}${C_END} "
			read -p "Enter VPN gateway public port [default: ${CFG_VPN_GATEWAY_PORT}]: " public_port
			if [ "$public_port" ]; then
				CFG_VPN_GATEWAY_PORT="$public_port"
			fi
		done

	else
		echo -e "  ${C_BOLD}${C_RED}${TXT_X} ${C_GREY} WireGuard VPN skipped${C_END}\n"
	fi

	echo
	echo -e "${C_BOLD}${C_GREEN}Thank you. We'll now proceed with the deployment using provided values.${C_END}"
}

check_required_variable() {
	local var_name="$1"
	if [ -z "${!var_name}" ]; then
		echo >&2 "ERROR: ${var_name} configuration option not set"
		exit 4
	fi
}

validate_required_variables() {
	echo -n " ${TXT_BEGIN} Validating configuration options..."
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
	# prepare full Defguard URL
	if [ $CFG_USE_HTTPS ]; then
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
	echo
	echo " ${TXT_BEGIN} Setting up your Defguard instance with following config:"
	echo
	echo -e "   ${TXT_SUB} data volume: ${C_BOLD}${VOLUME_DIR}${C_END}"
	echo
	echo -e "   ${TXT_SUB} domain: ${C_BOLD}${CFG_DOMAIN}${C_END}"
	echo -e "   ${TXT_SUB} web UI URL: ${C_BOLD}${CFG_DEFGUARD_URL}${C_END}"

	if [ "$CFG_VPN_NAME" ]; then
		echo -e "   ${TXT_SUB} VPN location name: ${C_BOLD}${CFG_VPN_NAME}${C_END}"
		echo -e "   ${TXT_SUB} VPN address: ${C_BOLD}${CFG_VPN_IP}${C_END}"
		echo -e "   ${TXT_SUB} VPN gateway IP: ${C_BOLD}${CFG_VPN_GATEWAY_IP}${C_END}"
		echo -e "   ${TXT_SUB} VPN gateway port: ${C_BOLD}${CFG_VPN_GATEWAY_PORT}${C_END}"
	fi

	if [ "$CFG_ENROLLMENT_DOMAIN" ]; then
		echo -e "   ${TXT_SUB} Enrollment service domain: ${C_BOLD}${CFG_ENROLLMENT_DOMAIN}${C_END}"
		echo -e "   ${TXT_SUB} Enrollment service URL: ${C_BOLD}${CFG_ENROLLMENT_URL}${C_END}"
	fi
	echo
	echo -e " ${TXT_BEGIN} All executed command's results are in log file: ${C_BOLD}${LOG_FILE}${C_END}"
	echo
}

setup_keys() {
	echo " ${TXT_BEGIN} Setting up SSL certificates and RSA keys..."
	if [ -d ${SSL_DIR} -a "$(ls -A ${SSL_DIR})" ]; then
		echo "   ${TXT_SUB} Using existing SSL certificates from ${SSL_DIR}"
	else
		generate_certs
	fi

	if [ -d ${RSA_DIR} -a "$(ls -A ${RSA_DIR})" ]; then
		echo "   ${TXT_SUB} Using existing RSA keys from ${RSA_DIR}."
	else
		generate_rsa
	fi
}

generate_certs() {
	echo " ${TXT_BEGIN} Creating new SSL certificates in ${SSL_DIR}..."
	mkdir -p ${SSL_DIR}

	PASSPHRASE=$(generate_secret)

	echo "PEM passphrase for SSL certificates set to '${PASSPHRASE}'."

	# generate private key for CA
	openssl genrsa -des3 -out ${SSL_DIR}/defguard-ca.key -passout pass:"${PASSPHRASE}" 2048 2>&1 >>${LOG_FILE}
	# generate Root Certificate
	#	TODO: allow configuring CA parameters
	openssl req -x509 -new -nodes -key ${SSL_DIR}/defguard-ca.key -sha256 -days 1825 -out ${SSL_DIR}/defguard-ca.pem -passin pass:"${PASSPHRASE}" -subj "/CN=${CFG_DOMAIN}" 2>&1 >>${LOG_FILE}

	# generate CA-signed certificate for Defguard gRPC
	openssl genrsa -out ${SSL_DIR}/defguard-grpc.key 2048 2>&1 >>${LOG_FILE}

	openssl req -new -key ${SSL_DIR}/defguard-grpc.key -out ${SSL_DIR}/defguard-grpc.csr -subj "/CN=${CFG_DOMAIN}" 2>&1 >>${LOG_FILE}
	cat >${SSL_DIR}/defguard-grpc.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${CFG_DOMAIN}
DNS.2 = core
DNS.3 = localhost
EOF
	openssl x509 -req -in ${SSL_DIR}/defguard-grpc.csr -CA ${SSL_DIR}/defguard-ca.pem -CAkey ${SSL_DIR}/defguard-ca.key -passin pass:"${PASSPHRASE}" -CAcreateserial \
		-out ${SSL_DIR}/defguard-grpc.crt -days 1000 -sha256 -extfile ${SSL_DIR}/defguard-grpc.ext 2>&1 >>${LOG_FILE}

	# generate CA-signed certificate for Defguard proxy gRPC
	openssl genrsa -out ${SSL_DIR}/defguard-proxy-grpc.key 2048 2>&1 >>${LOG_FILE}

	openssl req -new -key ${SSL_DIR}/defguard-proxy-grpc.key -out ${SSL_DIR}/defguard-proxy-grpc.csr -subj "/CN=${CFG_DOMAIN}" 2>&1 >>${LOG_FILE}
	cat >${SSL_DIR}/defguard-proxy-grpc.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = proxy
DNS.2 = localhost
EOF
	openssl x509 -req -in ${SSL_DIR}/defguard-proxy-grpc.csr -CA ${SSL_DIR}/defguard-ca.pem -CAkey ${SSL_DIR}/defguard-ca.key -passin pass:"${PASSPHRASE}" -CAcreateserial \
		-out ${SSL_DIR}/defguard-proxy-grpc.crt -days 1000 -sha256 -extfile ${SSL_DIR}/defguard-proxy-grpc.ext 2>&1 >>${LOG_FILE}
}

generate_rsa() {
	echo "Generating RSA keys in ${RSA_DIR}..."
	mkdir -p ${RSA_DIR}
	openssl genpkey -out ${RSA_DIR}/rsakey.pem -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>&1 >>${LOG_FILE}

}

generate_secret() {
	generate_secret_inner "${SECRET_LENGTH}"
}

generate_password() {
	generate_secret_inner "${PASSWORD_LENGTH}"
}

generate_secret_inner() {
	local length="$1"
	openssl rand -base64 ${length} | tr -d '=+/' | tr -d '\n' | cut -c1-${length-1}
}

create_caddyfile() {
	caddy_volume_path="${VOLUME_DIR}/caddy"
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
	echo -n " ${TXT_BEGIN} Fetching base compose file to ${PROD_COMPOSE_FILE}... "

	curl --proto '=https' --tlsv1.2 -sSf "${BASE_COMPOSE_FILE_URL}" -o "${PROD_COMPOSE_FILE}" 2>&1 >>${LOG_FILE}

	print_confirmation
}

generate_env_file() {
	PROD_ENV_FILE="${WORK_DIR_PATH}/${ENV_FILE}"
	fetch_base_env_file
	update_env_file

	print_confirmation
}

fetch_base_env_file() {
	echo -e " ${TXT_BEGIN} Fetching base ${ENV_FILE} file for compose stack..."

	curl --proto '=https' --tlsv1.2 -sSf "${BASE_ENV_FILE_URL}" -o "${PROD_ENV_FILE}" 2>&1 >>${LOG_FILE}
	print_confirmation
}

update_env_file() {
	echo -n " ${TXT_BEGIN} Setting environment variables in ${ENV_FILE} file for compose stack..."

	# set image versions
	set_env_file_value "CORE_IMAGE_TAG" "${CORE_IMAGE_TAG}"
	set_env_file_value "PROXY_IMAGE_TAG" "${PROXY_IMAGE_TAG}"
	set_env_file_value "GATEWAY_IMAGE_TAG" "${GATEWAY_IMAGE_TAG}"

	# fill in values
	set_env_file_secret "DEFGUARD_AUTH_SECRET"
	set_env_file_secret "DEFGUARD_YUBIBRIDGE_SECRET"
	set_env_file_secret "DEFGUARD_GATEWAY_SECRET"
	set_env_file_secret "DEFGUARD_SECRET_KEY"

	# use existing password if set in env variable
	if [ "$DEFGUARD_DB_PASSWORD" ]; then
		set_env_file_value "DEFGUARD_DB_PASSWORD" "${DEFGUARD_DB_PASSWORD}"
	else
		set_env_file_password "DEFGUARD_DB_PASSWORD"
	fi

	DEFGUARD_DEFAULT_ADMIN_PASSWORD="$(generate_password)"
	set_env_file_value "DEFGUARD_DEFAULT_ADMIN_PASSWORD" "${DEFGUARD_DEFAULT_ADMIN_PASSWORD}"

	set_env_file_value "DEFGUARD_URL" "${CFG_DEFGUARD_URL}"
	set_env_file_value "DEFGUARD_WEBAUTHN_RP_ID" "${CFG_DOMAIN}"
	print_confirmation
}

set_env_file_value() {
	# make sure variable exists in file
	grep -qF "${1}=" "${PROD_ENV_FILE}" || echo "${1}=" >>"${PROD_ENV_FILE}"
	"${SED[@]}" "s@\(${1}\)=.*@\1=${2}@" "${PROD_ENV_FILE}"
}

set_env_file_secret() {
	set_env_file_value "${1}" "$(generate_secret)" "${PROD_ENV_FILE}"
}

set_env_file_password() {
	set_env_file_value "${1}" "$(generate_password)" "${PROD_ENV_FILE}"
}

uncomment_feature() {
	"${SED[@]}" "s@# \(.*\) # \[${1}\]@\1@" "${2}"
}

enable_enrollment() {
	echo -n " ${TXT_BEGIN} Enabling enrollment proxy service in compose file..."

	# update .env file
	uncomment_feature "ENROLLMENT" "${PROD_ENV_FILE}"
	set_env_file_value "DEFGUARD_ENROLLMENT_URL" "${CFG_ENROLLMENT_URL}"

	# update compose file
	uncomment_feature "ENROLLMENT" "${PROD_COMPOSE_FILE}"

	print_confirmation
}

enable_vpn_gateway() {
	echo " ${TXT_BEGIN} Enabling VPN gateway service..."

	uncomment_feature "VPN" "${PROD_COMPOSE_FILE}"
	uncomment_feature "VPN" "${PROD_ENV_FILE}"

	# fetch image
	echo -e "   ${TXT_SUB} Fetching ${IMAGE_TYPE_NAME} gateway image..."
	$COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" pull gateway

	# create VPN location
	echo " ${TXT_BEGIN} Adding VPN to core & generating gateway token..."
	VPN_NETWORK=$(echo ${CFG_VPN_IP} | awk -F'[./]' '{print $1"."$2"."$3".0/"$5}')
	token=$($COMPOSE_CMD -f "${PROD_COMPOSE_FILE}" --env-file "${PROD_ENV_FILE}" run core init-vpn-location --name "${CFG_VPN_NAME}" --address "${CFG_VPN_IP}" --endpoint "${CFG_VPN_GATEWAY_IP}" --port "${CFG_VPN_GATEWAY_PORT}" --allowed-ips "${VPN_NETWORK}" | tail -n 1)
	if [ $? -ne 0 ]; then
		echo >&2 "ERROR: failed to create VPN network"
		exit 1
	fi

	# add gateway token to .env file
	set_env_file_value "DEFGUARD_TOKEN" "${token}"
}

print_instance_summary() {
	echo
	echo -e "${C_LGREEN} ${TXT_CHECK} Defguard setup finished successfully${C_END}. The Docker image version used for the setup was: ${IMAGE_TYPE_NAME}"
	echo
	echo "If your DNS configuration is correct your Defguard instance should be available at:"
	echo
	echo -e "\t${TXT_SUB} Web UI: ${C_BOLD}${CFG_DEFGUARD_URL}${C_END}"
	if [ "$CFG_ENABLE_ENROLLMENT" ]; then
		echo -e "\t${TXT_SUB} Enrollment service: ${C_BOLD}${CFG_ENROLLMENT_URL}${C_END}"
	fi
	echo
	echo -e " ${TXT_BEGIN} You can log into the UI using the default admin user:"
	echo
	echo -e "\t${TXT_SUB} username: ${C_BOLD}admin${C_END}"
	echo -e "\t${TXT_SUB} password: ${C_BOLD}${DEFGUARD_DEFAULT_ADMIN_PASSWORD}${C_END}"
	echo
	if [ "$CFG_ENABLE_VPN" ]; then
		echo -e "\t\tVPN server public endpoint is ${C_BOLD}${CFG_VPN_GATEWAY_IP}:${CFG_VPN_GATEWAY_PORT}${C_END}"
		echo -e "\t\tVPN network is ${C_BOLD}${VPN_NETWORK}${C_END}"
		echo -e "\t\t! Make sure your firewall allows external UDP traffic to port ${C_BOLD}${CFG_VPN_GATEWAY_PORT}${C_END} !"
		echo
		echo -e "\t\tTo test if the VPN is working: ping ${CFG_VPN_IP} (after connecting to VPN)"
	fi
	echo
	echo -e "Files used to deploy your instance are stored in:"
	echo -e "\t docker compose file: ${C_BOLD}${PROD_COMPOSE_FILE}${C_END}"
	echo -e "\t docker compose environment: ${C_BOLD}${PROD_ENV_FILE}${C_END}"
	echo
	echo -e "Persistent data (docker volumes) is stored in ${C_BOLD}${VOLUME_DIR}${C_END}"
	echo
	echo -e " ${C_YELLOW}${TXT_STAR} To support our work, please star us on GitHub! ${TXT_STAR}${C_END}"
	echo -e " ${C_YELLOW}${TXT_STAR} https://github.com/defguard/defguard ${TXT_STAR}${C_END}"
	echo
}

# run main function
main "$@" || exit 1
