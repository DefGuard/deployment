#!/bin/bash

VERSION="0.0.1"
BASENAME=$(basename $0)
ENV_TEMPLATE=".env.template"
ENV_PRODUCTION=".env"
COMPOSE="docker-compose.yaml"
CFG_LENGTH=64
SSL_DIR="./.volumes/ssl"

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
    echo -e "\t-d <defguard_domaiin>    domain/url under which to configure defguard instance"
    echo -e "\t-p [vpn_port]            port number under which to expose your VPN - if not set, gateway will not be configured"
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

  if [ $? -ne 0 ]; then
    echo "ERROR: openssl command not found"
    echo "ERROR: dependency failed, exiting..."
    exit 4
  fi
}

function set_env_file_value
{
  sed -i~ "s@\(${1}\)=.*@\1=${2}@" ${3}
  echo "Set value for ${1} in ${3} file"
}

function set_env_file_secret
{
  set_env_file_value ${1} $(generate_secret) ${2}
}

function generate_secret
{
  echo `openssl rand -base64 ${CFG_LENGTH} | tr -d '[:blank:]' | tr -d '\n'`
}

function create_env_file
{
  echo "Creating ${ENV_PRODUCTION} file based on ${ENV_TEMPLATE}"

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
  set_env_file_value "DEFGUARD_URL" "https://${CFG_DOMAIN}" ${ENV_PRODUCTION}
  set_env_file_value "DEFGUARD_WEBAUTHN_RP_ID" ${CFG_DOMAIN} ${ENV_PRODUCTION}
}

function generate_certs
{
  echo "Creating new SSL certificates in ${SSL_DIR}"
  mkdir -p ${SSL_DIR}

  while true; do
    read -s -p "Enter PEM pass phrase:" PASSPHRASE
    echo
    read -s -p "Verifying - Enter PEM pass phrase:" PASSPHRASE2
    echo
    [ "$PASSPHRASE" = "$PASSPHRASE2" ] && break
    echo "Please try again"
  done

  openssl genrsa -des3 -out ${SSL_DIR}/myCA.key -passout pass:${PASSPHRASE} 2048
  openssl req -x509 -new -nodes -key ${SSL_DIR}/myCA.key -sha256 -days 1825 -out ${SSL_DIR}/myCA.pem -passin pass:${PASSPHRASE}
}

# GET OPTIONS {{{
if [ $? != 0 ]; then
    usage
    exit 1
fi

while getopts ":hd:p:s:" arg; do
  case $arg in
    d)
      CFG_DOMAIN="${OPTARG}"
      ;;
    p)
      CFG_PORT="${OPTARG}"
      if [ ${CFG_PORT} -lt 1 -o ${CFG_PORT} -gt 65535 ]; then
        echo "Port must be between 1-65535"
        echo "Length: ${CFG_PORT} is bogus..."
        exit 1
      fi
      ;;
    s)
      CFG_LENGTH="${OPTARG}"
      if [ ${CFG_LENGTH} -lt 8 -o ${CFG_LENGTH} -gt 128 ]; then
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

if [ "X${CFG_DOMAIN}" == "X" ]; then
  echo "ERROR: no defguard domain set. "
  usage
  exit 2
fi

print_header

echo " + defguard domain: ${CFG_DOMAIN}"

if [ "X${CFG_PORT}" == "X" ]; then
  echo " - no VPN port was set, will not configure defguard VPN gateway, just the core..."
else
  echo " + defguard vpn port: ${CFG_PORT}, will include VPN gateway"
fi
echo " + secrets length will be: ${CFG_LENGTH}"
echo

if [ -f ${ENV_PRODUCTION} ]
then
  echo "Using existing ${ENV_PRODUCTION} file"
else
  create_env_file
fi

if [ -d ${SSL_DIR} ] && [ "$(ls -A ${SSL_DIR})" ]
then
  echo "Using existing SSL certificates from ${SSL_DIR}"
else
  generate_certs
fi
