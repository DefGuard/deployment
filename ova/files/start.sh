#!/bin/bash
# Starts defguard via docker compose.
# Default (no active-profiles file): starts the full all-in-one stack.
# To select specific components, create /opt/stacks/defguard/active-profiles with a
# space or newline-separated list of profiles: core, gateway, edge
#
# To enable the Dockge docker management UI (port 5001), create the file:
#   /opt/stacks/defguard/enable-docker-management
# Example cloud-init:
#   write_files:
#     - path: /opt/stacks/defguard/enable-docker-management
#       content: ""

STACK_DIR="${DEFGUARD_STACK_DIR:-/opt/stacks/defguard}"
PROFILES_FILE="$STACK_DIR/active-profiles"
ENABLE_DOCKER_MGMT_FILE="$STACK_DIR/enable-docker-management"

# Append the dockge profile if the opt-in flag file is present
_maybe_add_dockge() {
  local profiles="$1"
  if [ -f "$ENABLE_DOCKER_MGMT_FILE" ]; then
    if [ -z "$profiles" ]; then
      echo "dockge"
    else
      echo "${profiles},dockge"
    fi
  else
    echo "$profiles"
  fi
}

if [ ! -f "$PROFILES_FILE" ]; then
  COMPOSE_PROFILES=$(_maybe_add_dockge "")
  if [ -n "$COMPOSE_PROFILES" ]; then
    export COMPOSE_PROFILES
  fi
  docker compose -f "$STACK_DIR/docker-compose.yaml" up -d
else
  COMPOSE_PROFILES=$(tr '[:space:]' ',' < "$PROFILES_FILE" | tr -s ',' | sed 's/,$//')
  if [ -z "$COMPOSE_PROFILES" ]; then
    echo "Warning: $PROFILES_FILE is empty or contains only whitespace; starting full all-in-one stack."
    COMPOSE_PROFILES=$(_maybe_add_dockge "")
    if [ -n "$COMPOSE_PROFILES" ]; then
      export COMPOSE_PROFILES
    else
      unset COMPOSE_PROFILES
    fi
    docker compose -f "$STACK_DIR/docker-compose.yaml" up -d
  else
    COMPOSE_PROFILES=$(_maybe_add_dockge "$COMPOSE_PROFILES")
    export COMPOSE_PROFILES
    docker compose -f "$STACK_DIR/docker-compose.standalone.yaml" up -d
  fi
fi
