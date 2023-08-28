#!/bin/sh
# shellcheck shell=dash

# This is a script that sets up an entire defguard instance (including core, gateway, enrollment proxy
# and reverse proxy). It's goal is to prepare a working instance by running a single command.

# Global variables
VERSION="0.0.1"
BASENAME=$(basename "$0")
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"
SECRET_LENGTH=64
SSL_DIR=".volumes/ssl"
RSA_DIR=".volumes/core"

main() {
  # check if necessary tools are available
  check_environment

  # load configuration from env variables

  # generate docker-compose file

  # start docker stack

  # print out instance info

}

### HELPER FUNCTIONS ###
check_environment() {
  DOCKER_COMPOSE=$(docker-compose --version 2>&1 &> /dev/null)
  if [ ! -f ${COMPOSE} ]; then
    echo "ERROR: docker-compose command not found"
    echo "ERROR: dependency failed, exiting..."
    exit 4
  fi

  OPENSSL=$(openssl version 2>&1 &> /dev/null)
  if [ "${OPENSSL}" -ne 0 ]; then
    echo "ERROR: openssl command not found"
    echo "ERROR: dependency failed, exiting..."
    exit 4
  fi
}

# run main function
main "$@" || exit 1
