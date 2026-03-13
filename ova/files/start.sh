#!/bin/bash
# Starts defguard via docker compose.
# Default (no active-profiles file): starts the full all-in-one stack.
# To select specific components, create /opt/defguard/active-profiles with a
# space or newline-separated list of profiles: core, gateway, edge

PROFILES_FILE="/opt/defguard/active-profiles"

if [ ! -f "$PROFILES_FILE" ]; then
  docker compose -f /opt/defguard/docker-compose.yaml up -d
else
  COMPOSE_PROFILES=$(tr '[:space:]' ',' < "$PROFILES_FILE" | tr -s ',' | sed 's/,$//')
  if [ -z "$COMPOSE_PROFILES" ]; then
    echo "Warning: $PROFILES_FILE is empty or contains only whitespace; starting full all-in-one stack."
    unset COMPOSE_PROFILES
    docker compose -f /opt/defguard/docker-compose.yaml up -d
  else
    export COMPOSE_PROFILES
    docker compose -f /opt/defguard/docker-compose.standalone.yaml up -d
  fi
fi
