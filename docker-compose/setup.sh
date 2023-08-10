#!/bin/bash

VERSION="0.0.1"
BASENAME=$(basename "$0")
ENV_TEMPLATE=".env.template"
ENV_PRODUCTION=".env"
COMPOSE="docker-compose.yaml"
CFG_LENGTH=64
SSL_DIR=".volumes/ssl"
RSA_DIR=".volumes/core"

function print_header
{
  echo
  echo "defguard deployment setup v${VERSION}"
  echo "Copyright (C) 2023 teonite <https://teonite.com>"
  echo
}

function usage
{
    print_header
    echo
    echo "Usage: ${BASENAME} [options]"
    echo
    echo 'Available options:'
    echo
    echo -e "\t-h                       this help message"
    echo -e "\t-u <defguard_url>        url under which to configure defguard instance"
    echo -e "\t-e <enrollment_url>      url under which to configure enrollment service"
    echo -e "\t-s [pass length]         generated secrets length, default: 64"
    echo
}

function check_environment
{
  if [ ! -f ${COMPOSE} ]; then
    echo "ERROR: no docker compose configuration found at: ${COMPOSE}"
    echo "ERROR: are you in the right directory?"
    exit 3
  fi

  OPENSSL=$(openssl version 2>&1 &> /dev/null)

  if [ "${OPENSSL}" -ne 0 ]; then
    echo "ERROR: openssl command not found"
    echo "ERROR: dependency failed, exiting..."
    exit 4
  fi
}

function set_env_file_value
{
  sed -i~ "s@\(${1}\)=.*@\1=${2}@" "${3}"
  echo "Set value for ${1} in ${3} file."
}

function set_env_file_secret
{
  set_env_file_value "${1}" "$(generate_secret)" "${2}"
}

function generate_secret
{
  openssl rand -base64 ${CFG_LENGTH} | tr -d "=+/"  | tr -d '\n' | cut -c1-${CFG_LENGTH-1}
}

function create_env_file
{
  echo "Creating ${ENV_PRODUCTION} file based on ${ENV_TEMPLATE}..."

  if [ ! -f ${ENV_TEMPLATE} ]; then
    echo "ERROR: no environment template configuration found at: ${ENV_TEMPLATE}"
    echo "ERROR: are you in the right directory?"
    exit 5
  fi

  cp ${ENV_TEMPLATE} ${ENV_PRODUCTION}

  set_env_file_secret "DEFGUARD_AUTH_SECRET" ${ENV_PRODUCTION}
  set_env_file_secret "DEFGUARD_YUBIBRIDGE_SECRET" ${ENV_PRODUCTION}
  set_env_file_secret "DEFGUARD_GATEWAY_SECRET" ${ENV_PRODUCTION}
  set_env_file_secret "DEFGUARD_SECRET_KEY" ${ENV_PRODUCTION}
  set_env_file_secret "DEFGUARD_DB_PASSWORD" ${ENV_PRODUCTION}
  set_env_file_value "DEFGUARD_URL" "${CFG_DEFGUARD_URL}" ${ENV_PRODUCTION}
  DEFGUARD_DOMAIN=$(echo "${CFG_DEFGUARD_URL}" | sed -e 's/^http:\/\///g' -e 's/^https:\/\///g')
  set_env_file_value "DEFGUARD_WEBAUTHN_RP_ID" "${DEFGUARD_DOMAIN}" ${ENV_PRODUCTION}
  set_env_file_value "DEFGUARD_ENROLLMENT_URL" "${CFG_ENROLLMENT_URL}" ${ENV_PRODUCTION}
}

function generate_certs
{
  echo "Creating new SSL certificates in ${SSL_DIR}..."
  mkdir -p ${SSL_DIR}

  PASSPHRASE=$(generate_secret)

  echo "PEM pass phrase for set to '${PASSPHRASE}'."

  openssl genrsa -des3 -out ${SSL_DIR}/myCA.key -passout pass:"${PASSPHRASE}" 2048
  openssl req -x509 -new -nodes -key ${SSL_DIR}/myCA.key -sha256 -days 1825 -out ${SSL_DIR}/myCA.pem -passin pass:"${PASSPHRASE}" -subj "/C=PL/ST=Zachodniopomorskie/L=Szczecin/O=Example/OU=IT Department/CN=example.com"
}

function generate_rsa
{
  echo "Generating RSA keys in ${RSA_DIR}..."
  mkdir -p ${RSA_DIR}
  openssl genpkey -out ${RSA_DIR}/rsakey.pem -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -quiet
}

function uncomment_feature
{
  sed -i~ "s@# \(.*\) # \[${1}\]@\1@" "${2}"
}

function print_followup
{
  echo "Your environment is set up correctly!"
  echo "To start the stack run 'docker compose up -d'."
  echo "defguard should be then running on port 80 of your server."
  echo "Default admin credentials are admin/pass123. Please change the password after signing in."
}

# GET OPTIONS {{{
if [ $? != 0 ]; then
    usage
    exit 1
fi

while getopts ":hu:s:" arg; do
  case $arg in
    u)
      CFG_DEFGUARD_URL="${OPTARG}"
      ;;
    e)
      CFG_ENROLLMENT_URL="${OPTARG}"
      ;;
    s)
      CFG_LENGTH="${OPTARG}"
      if [ "${CFG_LENGTH}" -lt 8 ] || [ "${CFG_LENGTH}" -gt 128 ]; then
        echo "Recommended secrets length is more then 8 and less then 128"
        echo "Length: ${CFG_LENGTH} is bogus..."
        exit 1
      fi
      ;;
    h | *)
      usage
      exit 0
      ;;
  esac
done
# end: get options }}}

if [ "X${CFG_DEFGUARD_URL}" == "X" ]; then
  echo "ERROR: no defguard URL set. "
  usage
  exit 2
fi

if [ "X${CFG_ENROLLMENT_URL}" == "X" ]; then
  echo "ERROR: no enrollment service URL set. "
  usage
  exit 2
fi

print_header

echo " + defguard URL: ${CFG_DEFGUARD_URL}"
echo " + enrollment service URL: ${CFG_ENROLLMENT_URL}"
echo " + secrets length will be: ${CFG_LENGTH}"
echo

if [ -f ${ENV_PRODUCTION} ]
then
  echo "Using existing ${ENV_PRODUCTION} file."
else
  create_env_file
fi
echo

if [ -d ${SSL_DIR} ] && [ "$(ls -A ${SSL_DIR})" ]
then
  echo "Using existing SSL certificates from ${SSL_DIR}."
else
  generate_certs
fi
echo

if [ -d ${RSA_DIR} ] && [ "$(ls -A ${RSA_DIR})" ]
then
  echo "Using existing RSA keys from ${RSA_DIR}."
else
  generate_rsa
fi
uncomment_feature "RSA" ${COMPOSE}
echo "Enabled RSA support in ${COMPOSE}."

echo

print_followup
