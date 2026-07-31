#!/bin/bash
# shellcheck shell=bash
# Shared helpers for generate-env.sh and generate-compose.sh.

# Prints the resolved profile list (one per line): the contents of
# $1/active-profiles if present (falling back to the full stack if empty or
# whitespace-only), otherwise core+edge+gateway. Appends "dockge" if
# $1/enable-docker-management exists.
resolve_profiles() {
  local stack_dir="$1"
  local profiles_file="$stack_dir/active-profiles"
  local dockge_file="$stack_dir/enable-docker-management"
  local -a profiles=()

  if [ -f "$profiles_file" ]; then
    mapfile -t profiles < <(tr '[:space:]' '\n' < "$profiles_file" | sed '/^$/d')
  fi

  if [ "${#profiles[@]}" -eq 0 ]; then
    if [ -f "$profiles_file" ]; then
      echo "Warning: $profiles_file is empty or contains only whitespace; using full all-in-one stack." >&2
    fi
    profiles=(core edge gateway)
  fi

  if [ -f "$dockge_file" ]; then
    profiles+=(dockge)
  fi

  printf '%s\n' "${profiles[@]}"
}

# True (exit 0) only if core, edge, and gateway are ALL present among the given
# profiles (dockge and ordering are irrelevant) - i.e. this is a genuine
# same-host all-in-one deployment, not a segmented one.
is_full_stack() {
  local has_core=0 has_edge=0 has_gateway=0 p
  for p in "$@"; do
    case "$p" in
      core) has_core=1 ;;
      edge) has_edge=1 ;;
      gateway) has_gateway=1 ;;
    esac
  done
  [ "$has_core" = 1 ] && [ "$has_edge" = 1 ] && [ "$has_gateway" = 1 ]
}

# Reads the persisted deployment mode used by generate-compose.sh. Older
# layouts have no marker, so callers fall back to profile-based inference.
deployment_mode() {
  local init_dir="$1" mode=""
  if [ -f "$init_dir/.deployment-mode" ]; then
    mode="$(tr -d '[:space:]' < "$init_dir/.deployment-mode")"
  fi
  case "$mode" in
    "") echo auto ;;
    full|segmented) echo "$mode" ;;
    *) return 1 ;;
  esac
}
