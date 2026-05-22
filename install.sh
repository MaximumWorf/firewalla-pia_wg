#!/usr/bin/env bash
# =============================================================================
# install.sh — one-command installer for Firewalla (native / systemd mode)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/maximumworf/firewalla-pia_wg/main/install.sh | bash
#
# Or clone first then run:
#   git clone https://github.com/maximumworf/firewalla-pia_wg
#   cd firewalla-pia_wg && bash install.sh
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/maximumworf/firewalla-pia_wg"
INSTALL_DIR="/home/pi/pia-wg"
DATA_DIR="/data/pia-wg"
SERVICE_NAME="pia-wg"
SYSTEMD_DIR="/etc/systemd/system"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${BLUE}[install]${NC} $*"; }
info() { echo -e "${GREEN}[  ok  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn ]${NC} $*"; }
die()  { echo -e "${RED}[error ]${NC} $*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Please run as root: sudo bash install.sh"
}

detect_platform() {
  if [[ -f /etc/firewalla_version ]] || [[ -d /home/pi/.firewalla ]]; then
    echo "firewalla"
  elif grep -qi "raspberry" /proc/cpuinfo 2>/dev/null; then
    echo "raspbian"
  else
    echo "linux"
  fi
}

install_deps() {
  log "Checking dependencies..."
  local missing=()
  for cmd in wg wg-quick curl jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Missing: ${missing[*]} — attempting to install..."
    if command -v apt-get &>/dev/null; then
      apt-get update -qq
      apt-get install -y -qq wireguard-tools curl jq
    elif command -v opkg &>/dev/null; then
      opkg update
      opkg install wireguard-tools curl jq
    else
      die "Cannot auto-install dependencies on this system. Please install manually: ${missing[*]}"
    fi
  fi
  info "All dependencies present"
}

copy_scripts() {
  log "Installing scripts to ${INSTALL_DIR}..."
  mkdir -p "${INSTALL_DIR}"

  # If we're being piped from curl, fetch the files; otherwise copy from CWD
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

  if [[ -f "${script_dir}/pia-wg-firewalla.sh" ]]; then
    cp "${script_dir}/pia-wg-firewalla.sh" "${INSTALL_DIR}/"
    cp "${script_dir}/pia-wg.service"       "${INSTALL_DIR}/"
    [[ -f "${script_dir}/.env.example" ]] && \
      cp "${script_dir}/.env.example" "${INSTALL_DIR}/.env.example"
  else
    log "Downloading scripts from GitHub..."
    local base_url="https://raw.githubusercontent.com/maximumworf/firewalla-pia_wg/main"
    curl -fsSL "${base_url}/pia-wg-firewalla.sh" -o "${INSTALL_DIR}/pia-wg-firewalla.sh"
    curl -fsSL "${base_url}/pia-wg.service"       -o "${INSTALL_DIR}/pia-wg.service"
    curl -fsSL "${base_url}/.env.example"          -o "${INSTALL_DIR}/.env.example"
  fi

  chmod +x "${INSTALL_DIR}/pia-wg-firewalla.sh"
  info "Scripts installed to ${INSTALL_DIR}"
}

create_data_dir() {
  log "Creating data directory ${DATA_DIR}..."
  mkdir -p "${DATA_DIR}"
  chmod 700 "${DATA_DIR}"
  info "Data directory ready"
}

configure_env() {
  local env_file="${INSTALL_DIR}/.env"

  if [[ -f "${env_file}" ]]; then
    warn ".env already exists — skipping interactive configuration"
    warn "Edit ${env_file} to change settings"
    return 0
  fi

  echo
  echo -e "${BOLD}── PIA Credentials ──────────────────────────────────────────${NC}"
  read -rp "  PIA username (e.g. p1234567): " PIA_USER
  read -rsp "  PIA password: "                  PIA_PASS; echo

  echo
  echo -e "${BOLD}── Dedicated IP (press Enter to skip) ──────────────────────${NC}"
  read -rp "  DIP token (from PIA dashboard, blank = standard account): " DIP_TOKEN

  echo
  echo -e "${BOLD}── Region (ignored if using Dedicated IP) ───────────────────${NC}"
  read -rp "  PIA region [us_east]: " PIA_REGION
  PIA_REGION="${PIA_REGION:-us_east}"

  echo
  echo -e "${BOLD}── Profile name ─────────────────────────────────────────────${NC}"
  read -rp "  Firewalla profile name [PIA_WG]: " PROFILE_NAME
  PROFILE_NAME="${PROFILE_NAME:-PIA_WG}"

  cat > "${env_file}" <<EOF
PIA_USER=${PIA_USER}
PIA_PASS=${PIA_PASS}
DIP_TOKEN=${DIP_TOKEN}
PIA_REGION=${PIA_REGION}
PROFILE_NAME=${PROFILE_NAME}
WG_MANAGED_BY_FIREWALLA=true
DATA_DIR=${DATA_DIR}
EOF
  chmod 600 "${env_file}"
  info ".env written to ${env_file}"
}

install_service() {
  log "Installing systemd service..."
  # Patch WorkingDirectory in the service file to match INSTALL_DIR
  sed "s|/home/pi/pia-wg|${INSTALL_DIR}|g" \
    "${INSTALL_DIR}/pia-wg.service" > "${SYSTEMD_DIR}/${SERVICE_NAME}.service"

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
  info "Service installed and enabled"
}

start_service() {
  log "Starting ${SERVICE_NAME}..."
  systemctl start "${SERVICE_NAME}"
  sleep 3
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    info "Service is running"
  else
    warn "Service may have failed — check: journalctl -u ${SERVICE_NAME} -n 50"
  fi
}

print_next_steps() {
  local platform="$1"
  echo
  echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Installation complete!${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo
  echo -e "  ${BOLD}Service commands:${NC}"
  echo    "    sudo systemctl status  ${SERVICE_NAME}"
  echo    "    sudo journalctl -u ${SERVICE_NAME} -f"
  echo    "    sudo systemctl restart ${SERVICE_NAME}"
  echo
  echo -e "  ${BOLD}Manual commands:${NC}"
  echo    "    ${INSTALL_DIR}/pia-wg-firewalla.sh status"
  echo    "    ${INSTALL_DIR}/pia-wg-firewalla.sh reconnect"
  echo    "    ${INSTALL_DIR}/pia-wg-firewalla.sh list-regions"
  echo
  if [[ "${platform}" == "firewalla" ]]; then
    echo -e "  ${BOLD}Activate the VPN in Firewalla:${NC}"
    echo    "    Firewalla app → VPN Client → WireGuard → ${PROFILE_NAME:-PIA_WG} → Enable"
    echo
  fi
  echo -e "  ${BOLD}Config file:${NC} ${INSTALL_DIR}/.env"
  echo -e "  ${BOLD}State/keys:${NC}  ${DATA_DIR}/"
  echo
}

main() {
  require_root

  local platform; platform=$(detect_platform)
  log "Detected platform: ${platform}"

  install_deps
  copy_scripts
  create_data_dir
  configure_env
  install_service
  start_service
  print_next_steps "${platform}"
}

main "$@"
