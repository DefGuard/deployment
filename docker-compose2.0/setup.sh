#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# Defguard setup script
# Usage: bash <(curl -sSL https://raw.githubusercontent.com/defguard/deployment/main/docker-compose2.0/setup.sh)
#
# Options:
#   --dev           use development images
#   --pre-release   use pre-release images
#   --help          show this help and exit

COMPOSE_FILE_URL="https://raw.githubusercontent.com/defguard/deployment/one-liner-2.0/docker-compose2.0/docker-compose.setup.yaml"
COMPOSE_FILE="./docker-compose.setup.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
COMPOSE_FILE_LOCAL="${SCRIPT_DIR}/docker-compose.setup.yaml"

DEFGUARD_CORE_TAG="latest"
DEFGUARD_PROXY_TAG="latest"
DEFGUARD_GATEWAY_TAG="latest"
IMAGE_MODE="latest"

check_character_support() {
  echo -e "$1" | grep -q "$1"
}

init_term() {
  if check_character_support "√"; then
    TXT_CHECK="✓"
    TXT_BEGIN="▶"
    TXT_SUB="▷"
    TXT_X="✗"
  else
    TXT_CHECK="+"
    TXT_BEGIN=">>"
    TXT_SUB=">"
    TXT_X="x"
  fi

  if [[ $TERM == *"256"* ]]; then
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_LRED="\033[91m"
    C_LGREEN="\033[92m"
    C_LYELLOW="\033[93m"
    C_LBLUE="\033[94m"
    C_BOLD="\033[1m"
    C_BG_GREY="\033[100m"
    C_END="\033[0m"
  else
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_LRED=""
    C_LGREEN=""
    C_LYELLOW=""
    C_LBLUE=""
    C_BOLD=""
    C_BG_GREY=""
    C_END=""
  fi
}

info()    { echo -e " ${TXT_BEGIN} $*"; }
success() { echo -e " ${C_LGREEN}${TXT_CHECK}${C_END} $*"; }
warn()    { echo -e " ${C_LYELLOW}${TXT_X}${C_END} $*"; }
error()   { echo -e " ${C_LRED}${TXT_X}${C_END} $*" >&2; }
die()     { error "$*"; exit 1; }
section() { echo -e "\n${C_BOLD}$*${C_END}\n"; }

print_header() {
  echo -e "${C_LBLUE}"
  cat << 'LOGO'
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
LOGO
  echo -e "${C_END}"
  echo "Defguard docker-compose 2.0 setup script"
  echo -e "Copyright ©2023-2026 ${C_BOLD}defguard sp. z o.o.${C_END} <${C_BG_GREY}${C_YELLOW}https://defguard.net/${C_END}>"
  echo
}

usage() {
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo
  echo "Available options:"
  echo "  --dev           use development images"
  echo "  --pre-release   use pre-release images"
  echo "  --help          show this help and exit"
  echo
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev)
        IMAGE_MODE="dev"
        DEFGUARD_CORE_TAG="dev"
        DEFGUARD_PROXY_TAG="dev"
        DEFGUARD_GATEWAY_TAG="dev"
        shift ;;
      --pre-release)
        IMAGE_MODE="pre-release"
        DEFGUARD_CORE_TAG="pre-release"
        DEFGUARD_PROXY_TAG="pre-release"
        DEFGUARD_GATEWAY_TAG="pre-release"
        shift ;;
      --help|-h)
        usage ;;
      *)
        die "Unknown option: $1. Run with --help for usage." ;;
    esac
  done
}

gen_secret() {
  if command -v openssl &>/dev/null; then
    openssl rand -hex 32
  else
    tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 64
  fi
}

get_host_ip() {
  local ip=""
  if command -v ip &>/dev/null; then
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
  fi
  if [[ -z "$ip" ]] && command -v ipconfig &>/dev/null; then
    ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
  fi
  if [[ -z "$ip" ]]; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  printf '%s' "${ip:-127.0.0.1}"
}

check_deps() {
  section "Checking dependencies"

  if ! command -v docker &>/dev/null; then
    die "Docker is not installed. Please install it first: https://docs.docker.com/get-docker/"
  fi
  success "Docker found: $(docker --version)"

  if ! docker compose version &>/dev/null 2>&1; then
    die "Docker Compose plugin is not installed. Please install it: https://docs.docker.com/compose/install/"
  fi
  success "Docker Compose found: $(docker compose version --short)"

  if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    die "Neither curl nor wget is available. Please install one of them."
  fi
}

check_volumes() {
  if [[ -d ".volumes" ]]; then
    die ".volumes directory already exists. Remove it before running setup, or this may overwrite an existing installation."
  fi
}

download_compose_file() {
  section "Preparing compose file"

  if [[ -f "$COMPOSE_FILE" ]]; then
    success "Found existing ${COMPOSE_FILE} – skipping download."
    return
  fi

  if [[ -f "$COMPOSE_FILE_LOCAL" ]]; then
    cp "$COMPOSE_FILE_LOCAL" "$COMPOSE_FILE"
    success "Loaded compose file from local path."
    return
  fi

  info "Downloading docker-compose.setup.yaml..."
  if command -v curl &>/dev/null; then
    curl -sSfL "$COMPOSE_FILE_URL" -o "$COMPOSE_FILE"
  else
    wget -qO "$COMPOSE_FILE" "$COMPOSE_FILE_URL"
  fi
  success "Compose file downloaded."
}

write_env() {
  section "Generating configuration"

  if [[ -f ".env" ]]; then
    warn ".env already exists – skipping generation. Remove it to regenerate."
    return
  fi

  local secret_key auth_secret gw_secret yubibridge_secret db_password
  secret_key=$(gen_secret)
  auth_secret=$(gen_secret)
  gw_secret=$(gen_secret)
  yubibridge_secret=$(gen_secret)
  db_password=$(gen_secret | head -c 24)

  case "$IMAGE_MODE" in
    dev)         info "Image mode: ${C_RED}development${C_END}" ;;
    pre-release) info "Image mode: ${C_YELLOW}pre-release${C_END}" ;;
    *)           info "Image mode: ${C_GREEN}latest${C_END}" ;;
  esac

  cat > .env << EOF
# Defguard – generated by setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

DEFGUARD_CORE_TAG=${DEFGUARD_CORE_TAG}
DEFGUARD_PROXY_TAG=${DEFGUARD_PROXY_TAG}
DEFGUARD_GATEWAY_TAG=${DEFGUARD_GATEWAY_TAG}

POSTGRES_DB=defguard
POSTGRES_USER=defguard
POSTGRES_PASSWORD=${db_password}

DEFGUARD_DB_NAME=defguard
DEFGUARD_DB_USER=defguard
DEFGUARD_DB_PASSWORD=${db_password}
EOF

  success ".env written."
}

launch() {
  section "Starting Defguard"

  mkdir -p .volumes/certs/edge
  mkdir -p .volumes/certs/gateway
  mkdir -p .volumes/db

  info "Pulling images (this may take a moment)..."
  docker compose -f "$COMPOSE_FILE" pull

  info "Starting services..."
  docker compose -f "$COMPOSE_FILE" up -d

  success "All services started."
}

show_wizard_info() {
  local wizard_url
  wizard_url="http://$(get_host_ip):8000"

  echo
  echo -e " ${TXT_BEGIN} Services status:"
  echo
  docker compose -f "$COMPOSE_FILE" ps
  echo
  echo -e "${C_LGREEN}${C_BOLD} ${TXT_CHECK} All containers are up. ${C_END}"
  echo
  echo -e "${C_LGREEN}${C_BOLD}  ╔══════════════════════════════════════════════════════╗"
  echo -e "  ║                                                      ║"
  echo -e "  ║   Continue setup in your browser:                    ║"
  printf  "  ║   %-51s║\n" "${wizard_url}"
  echo -e "  ║                                                      ║"
  echo -e "  ╚══════════════════════════════════════════════════════╝${C_END}"
  echo
}

main() {
  init_term
  parse_args "$@"
  print_header
  check_deps
  check_volumes
  download_compose_file
  write_env
  launch
  show_wizard_info
}

main "$@"
