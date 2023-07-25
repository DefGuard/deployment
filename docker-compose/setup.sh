#!/bin/bash

VERSION="0.0.1"
BASENAME=$(basename $0)
ENV_TEMPLATE=".env.template"
ENV_PRODUCTION=".env"
COMPOSE="docker-compose.yaml"
CFG_LENGTH=64

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

if [ ! -f ${ENV_TEMPLATE} ]; then
  echo "ERROR: no enviroment template configuration found at: ${ENV_TEMPLATE}"
  echo "ERROR: are you in the right directory?"
  exit 3
fi

if [ ! -f ${COMPOSE} ]; then
  echo "ERROR: no enviroment template configuration found at: ${COMPOSE}"
  echo "ERROR: are you in the right directory?"
  exit 4
fi


OPENSSL=$(openssl version 2>&1 &> /dev/null)

if [ $? -ne 0 ]; then
  echo "ERROR: openssl command not found"
  echo "ERROR: dependency failed, exiting..."
  exit 5
fi

print_header

echo " + defguard domain: ${CFG_DOMAIN}"

if [ "X${CFG_PORT}" == "X" ]; then
  echo "- no VPN port was set, will not configure defguard VPN gateway, just the core..."
else
  echo " + defguard vpn port: ${CFG_PORT}, will include VPN gateway"
fi
echo " + secrets length will be: ${CFG_LENGTH}"

OPENSSL="openssl rand -base64 ${CFG_LENGTH} | tr -d '[:blank:]' | tr -d '\n'"
PASS1=$(eval ${OPENSSL})
echo example secret: $PASS1
echo $PASS1 | wc -c
