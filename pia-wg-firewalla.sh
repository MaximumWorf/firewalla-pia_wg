#!/usr/bin/env bash
# =============================================================================
# pia-wg-firewalla.sh
# PIA WireGuard VPN for Firewalla — dedicated IP support + auto token refresh
# Sources: pia-foss/manual-connections, triffid/pia-wg, JasonMeudt/Firewalla-pia-wireguard
# =============================================================================
set -euo pipefail

readonly VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── PIA API endpoints ──────────────────────────────────────────────────────────
readonly PIA_TOKEN_URL="https://www.privateinternetaccess.com/api/client/v2/token"
readonly PIA_SERVER_LIST_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"
readonly PIA_DIP_API_URL="https://www.privateinternetaccess.com/api/client/v2/dedicated_ip"
readonly WG_KEY_PORT=1337

# ── Firewalla profile paths ────────────────────────────────────────────────────
readonly FW_PROFILE_DIR="/home/pi/.firewalla/run/wg_profile"
readonly FW_OVERLAY_DIR="/media/home-rw/overlay/pi/.firewalla/run/wg_profile"

# ── Embedded PIA CA certificate (RSA 4096) ─────────────────────────────────────
# Source: https://github.com/pia-foss/manual-connections/blob/master/ca.rsa.4096.crt
readonly PIA_CA_CERT='-----BEGIN CERTIFICATE-----
MIIHqzCCBZOgAwIBAgIJAJ0u+vODZJntMA0GCSqGSIb3DQEBDQUAMIHoMQswCQYD
VQQGEwJVUzELMAkGA1UECBMCQ0ExEzARBgNVBAcTCkxvc0FuZ2VsZXMxIDAeBgNV
BAoTF1ByaXZhdGUgSW50ZXJuZXQgQWNjZXNzMSAwHgYDVQQLExdQcml2YXRlIElu
dGVybmV0IEFjY2VzczEgMB4GA1UEAxMXUHJpdmF0ZSBJbnRlcm5ldCBBY2Nlc3Mx
IDAeBgNVBCkTF1ByaXZhdGUgSW50ZXJuZXQgQWNjZXNzMS8wLQYJKoZIhvcNAQkB
FiBzZWN1cmVAcHJpdmF0ZWludGVybmV0YWNjZXNzLmNvbTAeFw0xNDA0MTcxNzQw
MzNaFw0zNDA0MTIxNzQwMzNaMIHoMQswCQYDVQQGEwJVUzELMAkGA1UECBMCQ0Ex
EzARBgNVBAcTCkxvc0FuZ2VsZXMxIDAeBgNVBAoTF1ByaXZhdGUgSW50ZXJuZXQg
QWNjZXNzMSAwHgYDVQQLExdQcml2YXRlIEludGVybmV0IEFjY2VzczEgMB4GA1UE
AxMXUHJpdmF0ZSBJbnRlcm5ldCBBY2Nlc3MxIDAeBgNVBCkTF1ByaXZhdGUgSW50
ZXJuZXQgQWNjZXNzMS8wLQYJKoZIhvcNAQkBFiBzZWN1cmVAcHJpdmF0ZWludGVy
bmV0YWNjZXNzLmNvbTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALVk
hjumaqBbL8aSgj6xbX1QPTfTd1qHsAZd2B97m8Vw31c/2yQgZNf5qZY0+jOIHULN
De4R9TIvyBEbvnAg/OkPw8n/+ScgYOeH876VUXzjLDBnDb8DLr/+w9oVsuDeFJ9K
V2UFM1OYX0SnkHnrYAN2QLF98ESK4NCSU01h5zkcgmQ+qKSfA9Ny0/UpsKPBFqsQ
25NvjDWFhCpeqCHKUJ4Be27CDbSl7lAkBuHMPHJs8f8xPgAbHRXZOxVCpayZ2SND
fCwsnGWpWFoMGvdMbygngCn6jA/W1VSFOlRlfLuuGe7QFfDwA0jaLCxuWt/BgZyl
p7tAzYKR8lnWmtUCPm4+BtjyVDYtDCiGBD9Z4P13RFWvJHw5aapx/5W/CuvVyI7p
Kwvc2IT+KPxCUhH1XI8ca5RN3C9NoPJJf6qpg4g0rJH3aaWkoMRrYvQ+5PXXYUzj
tRHImghRGd/ydERYoAZXuGSbPkm9Y/p2X8unLcW+F0xpJD98+ZI+tzSsI99Zs5wi
jSUGYr9/j18KHFTMQ8n+1jauc5bCCegN27dPeKXNSZ5riXFL2XX6BkY68y58UaNz
meGMiUL9BOV1iV+PMb7B7PYs7oFLjAhh0EdyvfHkrh/ZV9BEhtFa7yXp8XR0J6vz
1YV9R6DYJmLjOEbhU8N0gc3tZm4Qz39lIIG6w3FDAgMBAAGjggFUMIIBUDAdBgNV
HQ4EFgQUrsRtyWJftjpdRM0+925Y6Cl08SUwggEfBgNVHSMEggEWMIIBEoAUrsRt
yWJftjpdRM0+925Y6Cl08SWhge6kgeswgegxCzAJBgNVBAYTAlVTMQswCQYDVQQI
EwJDQTETMBEGA1UEBxMKTG9zQW5nZWxlczEgMB4GA1UEChMXUHJpdmF0ZSBJW50Z
cm5ldCBBY2Nlc3MxIDAeBgNVBAsTF1ByaXZhdGUgSW50ZXJuZXQgQWNjZXNzMSAw
HgYDVQQDExdQcml2YXRlIEludGVybmV0IEFjY2VzczEgMB4GA1UEKRMXUHJpdmF0
ZSBJbnRlcm5ldCBBY2Nlc3MxLzAtBgkqhkiG9w0BCQEWIHNlY3VyZUBwcml2YXRl
aW50ZXJuZXRhY2Nlc3MuY29tggkAnS7684Nkme0wDAYDVR0TBAUwAwEB/zANBgkq
hkiG9w0BAQ0FAAOCAgEAJsfhsPk3r8kLXLxY+v+vHzbr4ufNtqnL9/1Uuf8NrsCt
pXAoyZ0YqfbkWx3NHTZ7OE9ZRhdMP/RqHQE1p4N4Sa1nZKhTKasV6KhHDqSCt/dv
Em89xWm2MVA7nyzQxVlHa9AkcBaemcXEiyT19XdpiXOP4Vhs+J1R5m8zQOxZlV1G
tF9vsXmJqWZpOVPmZ8f35BCsYPvv4yMewnrtAC8PFEK/bOPeYcKN50bol22QYaZu
LfpkHfNiFTnfMh8sl/ablPyNY7DUNiP5DRcMdIwmfGQxR5WEQoHL3yPJ42LkB5zs
6jIm26DGNXfwura/mi105+ENH1CaROtRYwkiHb08U6qLXXJz80mWJkT90nr8Asj3
5xN2cUppg74nG3YVav/38P48T56hG1NHbYF5uOCske19F6wi9maUoto/3vEr0rnX
JUp2KODmKdvBI7co245lHBABWikk8VfejQSlCtDBXn644ZMtAdoxKNfR2WTFVEwJ
iyd1Fzx0yujuiXDROLhISLQDRjVVAvawrAtLZWYK31bY7KlezPlQnl/D9Asxe85l
8jO5+0LdJ6VyOs/Hd4w52alDW/MFySDZSfQHMTIc30hLBJ8OnCEIvluVQQ2UQvoW
+no177N9L2Y+M9TcTA62ZyMXShHQGeh20rb4kK8f+iFX8NxtdHVSkxMEFSfDDyQ=
-----END CERTIFICATE-----'

# ── Configurable defaults (all overridable via .env) ───────────────────────────
DATA_DIR="${DATA_DIR:-/data/pia-wg}"
PIA_REGION="${PIA_REGION:-us_east}"
PROFILE_NAME="${PROFILE_NAME:-PIA_WG}"
TOKEN_TTL="${TOKEN_TTL:-72000}"            # 20 h — PIA tokens valid ~24 h
SERVER_LIST_TTL="${SERVER_LIST_TTL:-86400}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-60}"
HANDSHAKE_MAX_AGE="${HANDSHAKE_MAX_AGE:-120}"
MAX_DOWN_TIME="${MAX_DOWN_TIME:-300}"
MAX_RECONNECT_ATTEMPTS="${MAX_RECONNECT_ATTEMPTS:-5}"
# In Firewalla mode: re-register WireGuard key this often (seconds) while the
# interface is down, so the PIA server always has a fresh peer entry ready.
KEY_REFRESH_INTERVAL="${KEY_REFRESH_INTERVAL:-150}"
VPN_CHECK_IP="${VPN_CHECK_IP:-9.9.9.9}"
WG_DNS_OVERRIDE="${WG_DNS_OVERRIDE:-}"
# Set to "true" when Firewalla manages the WireGuard interface (no wg-quick)
WG_MANAGED_BY_FIREWALLA="${WG_MANAGED_BY_FIREWALLA:-false}"
# Hash-based profile ID created by the Firewalla app (e.g. "682D_682DF").
# Obtain it after pasting the output of 'generate-config' into the Firewalla
# app: VPN Client → Add VPN → WireGuard → paste config.
# Then run: ls -t ~/.firewalla/run/wg_profile/*.conf | head -1
# Set to the filename without the .conf extension.
# When blank, the script creates profile files itself (legacy mode).
FIREWALLA_PROFILE_ID="${FIREWALLA_PROFILE_ID:-}"
# Credentials — must be set in .env or environment
PIA_USER="${PIA_USER:-}"
PIA_PASS="${PIA_PASS:-}"
# Leave blank for standard accounts; set to your PIA Dedicated IP token for DIP
DIP_TOKEN="${DIP_TOKEN:-}"
# Optional manual DIP server override — skips the API lookup entirely.
# Find these in your PIA account portal next to your Dedicated IP.
DIP_HOSTNAME="${DIP_HOSTNAME:-}"
DIP_SERVER_IP="${DIP_SERVER_IP:-}"
DIP_PORT="${DIP_PORT:-1337}"

# ── Derive interface name (max 15 chars, Linux IFNAMSIZ limit) ─────────────────
WG_IFACE="$(echo "${PROFILE_NAME}" | tr -cd 'A-Za-z0-9_-' | cut -c1-15)"
# WG_IFACE_ACTUAL is the real kernel interface name.
# In Firewalla mode it is vpn_${PROFILE_NAME} (Firewalla's naming); updated after load_env.
WG_IFACE_ACTUAL="${WG_IFACE}"

# ── Terminal colours (disabled when not a tty) ─────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

log()  { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" >&2; }
info() { echo -e "${GREEN}[INFO ]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN ]${NC} $*" >&2; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# ── Graceful shutdown ──────────────────────────────────────────────────────────
_shutdown() {
  log "Shutting down..."
  if [[ "${WG_MANAGED_BY_FIREWALLA}" != "true" ]]; then
    wg_down 2>/dev/null || true
  fi
  exit 0
}
trap _shutdown SIGTERM SIGINT

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

check_deps() {
  local missing=()
  for cmd in curl jq wg ip; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -gt 0 ]] && die "Missing required tools: ${missing[*]}. Install wireguard-tools, curl, jq."
  if [[ "${WG_MANAGED_BY_FIREWALLA}" != "true" ]]; then
    command -v wg-quick &>/dev/null || die "wg-quick not found (required for standalone mode)"
  fi
}

load_env() {
  # Load .env from script dir, then from DATA_DIR (Docker volume wins)
  [[ -f "${SCRIPT_DIR}/.env" ]]  && { info "Loading ${SCRIPT_DIR}/.env"; source "${SCRIPT_DIR}/.env"; }
  [[ -f "${DATA_DIR}/.env" ]]    && { info "Loading ${DATA_DIR}/.env";    source "${DATA_DIR}/.env";    }
  # Re-derive interface names after env load in case PROFILE_NAME or mode changed
  WG_IFACE="$(echo "${PROFILE_NAME}" | tr -cd 'A-Za-z0-9_-' | cut -c1-15)"
  if [[ "${WG_MANAGED_BY_FIREWALLA}" == "true" ]]; then
    if [[ -n "${FIREWALLA_PROFILE_ID}" ]]; then
      # App-created profile: Firewalla prefixes the hash-based ID with vpn_
      WG_IFACE_ACTUAL="vpn_${FIREWALLA_PROFILE_ID}"
    else
      # Legacy external-profile mode: Firewalla prefixes PROFILE_NAME with vpn_
      WG_IFACE_ACTUAL="vpn_${PROFILE_NAME}"
    fi
  else
    WG_IFACE_ACTUAL="${WG_IFACE}"
  fi
}

init_data_dir() {
  mkdir -p "${DATA_DIR}"
  chmod 700 "${DATA_DIR}"
  printf '%s' "${PIA_CA_CERT}" > "${DATA_DIR}/ca.rsa.4096.crt"
  # Required by wg-quick for fwmark-based routing rules.
  # Silently ignored if the kernel doesn't permit it (already set by host).
  sysctl -qw net.ipv4.conf.all.src_valid_mark=1 2>/dev/null || true
}

# Returns seconds since file was last modified, or 999999 if it doesn't exist.
file_age() {
  local f="$1"
  [[ -f "$f" ]] || { echo 999999; return; }
  echo $(( $(date +%s) - $(stat -c %Y "$f") ))
}

# Retry curl up to 3 times with increasing delays.
# Usage: curl_retry [curl args...]  — stdout is the response body
curl_retry() {
  local attempt=1 max=3 out
  while (( attempt <= max )); do
    out=$(curl "$@" 2>/dev/null) && { echo "${out}"; return 0; }
    warn "curl attempt ${attempt}/${max} failed — retrying in ${attempt}s..."
    sleep "${attempt}"
    (( attempt++ )) || true
  done
  warn "curl failed after ${max} attempts"
  return 1
}

is_iface_up() {
  ip link show "${WG_IFACE_ACTUAL}" &>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# PIA authentication
# ─────────────────────────────────────────────────────────────────────────────

get_pia_token() {
  local force="${1:-false}"
  local token_file="${DATA_DIR}/token"

  if [[ "$force" != "true" && -f "$token_file" ]]; then
    local age; age=$(file_age "$token_file")
    if (( age < TOKEN_TTL )); then
      info "Reusing cached PIA token (age ${age}s / TTL ${TOKEN_TTL}s)"
      cat "$token_file"
      return 0
    fi
    info "Token expired (${age}s old), refreshing..."
  fi

  [[ -z "${PIA_USER}" ]] && die "PIA_USER is not set"
  [[ -z "${PIA_PASS}" ]] && die "PIA_PASS is not set"

  log "Authenticating with PIA (v2 API)..."
  local resp token
  resp=$(curl_retry -s --max-time 20 \
    --location \
    --request POST \
    --form "username=${PIA_USER}" \
    --form "password=${PIA_PASS}" \
    "${PIA_TOKEN_URL}") || true
  token=$(echo "${resp}" | jq -r '.token // empty' 2>/dev/null || true)

  [[ -z "${token}" ]] && die "PIA authentication failed. Last response: ${resp}"

  printf '%s' "${token}" > "${token_file}"
  chmod 600 "${token_file}"
  info "PIA token obtained and cached"
  echo "${token}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Dedicated IP — find server CN and IP for the DIP assignment
# ─────────────────────────────────────────────────────────────────────────────

get_dip_server() {
  local auth_token="$1"

  # Allow manual override — skip API entirely if the user already knows their server
  if [[ -n "${DIP_HOSTNAME:-}" && -n "${DIP_SERVER_IP:-}" ]]; then
    info "Using manually specified DIP server: ${DIP_HOSTNAME} (${DIP_SERVER_IP})"
    echo "${DIP_HOSTNAME}|${DIP_SERVER_IP}"
    return 0
  fi

  # Cache the DIP server info — your dedicated IP's server never changes.
  # This avoids a redundant API call on every key refresh in the watchdog.
  local cache="${DATA_DIR}/dip_server.json"
  if [[ -f "${cache}" ]]; then
    local cached_cn cached_ip
    cached_cn=$(jq -r '.cn // empty' "${cache}" 2>/dev/null || true)
    cached_ip=$(jq -r '.ip // empty' "${cache}" 2>/dev/null || true)
    if [[ -n "${cached_cn}" && -n "${cached_ip}" ]]; then
      info "Using cached DIP server: ${cached_cn} (${cached_ip})"
      echo "${cached_cn}|${cached_ip}"
      return 0
    fi
  fi

  log "Resolving Dedicated IP server via PIA API..."
  local resp http_code

  # Capture HTTP status code alongside the body for better error messages
  # Use --data-raw with shell interpolation to match the working reference script exactly
  resp=$(curl_retry -s --max-time 20 --location \
    --request POST \
    --write-out "\n%{http_code}" \
    --header "Content-Type: application/json" \
    --header "Authorization: Token ${auth_token}" \
    --data-raw '{"tokens":["'"${DIP_TOKEN}"'"]}' \
    "${PIA_DIP_API_URL}") || {
      die "curl could not reach ${PIA_DIP_API_URL}. Check connectivity, or set DIP_HOSTNAME and DIP_SERVER_IP manually."
    }

  http_code=$(echo "${resp}" | tail -1)
  resp=$(echo "${resp}" | head -n -1)

  if [[ "${http_code}" != "200" ]]; then
    err "DIP API returned HTTP ${http_code}. Body: ${resp}"
    die "DIP API failed (HTTP ${http_code}). Verify DIP_TOKEN is correct, or set DIP_HOSTNAME and DIP_SERVER_IP to skip this call."
  fi

  local status
  status=$(echo "${resp}" | jq -r '.[0].status // empty' 2>/dev/null || true)
  if [[ "${status}" != "active" ]]; then
    err "DIP API response: ${resp}"
    die "Dedicated IP status='${status}' (expected 'active'). Verify DIP_TOKEN is correct and the IP is active in your PIA account."
  fi

  local dip_cn dip_ip
  dip_cn=$(echo "${resp}" | jq -r '.[0].cn')
  dip_ip=$(echo "${resp}" | jq -r '.[0].ip')
  info "Dedicated IP server: ${dip_cn} (${dip_ip})"

  echo "${resp}" | jq '.[0]' > "${DATA_DIR}/dip_server.json"
  echo "${dip_cn}|${dip_ip}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Server list & region selection
# ─────────────────────────────────────────────────────────────────────────────

fetch_server_list() {
  local force="${1:-false}"
  local cache="${DATA_DIR}/servers.json"

  if [[ "$force" != "true" && -f "$cache" ]]; then
    local age; age=$(file_age "$cache")
    if (( age < SERVER_LIST_TTL )); then
      info "Reusing cached server list (age ${age}s)"
      cat "$cache"
      return 0
    fi
  fi

  log "Fetching PIA server list..."
  # The server list has a signature on the second line — strip it
  local resp
  resp=$(curl -s --max-time 20 "${PIA_SERVER_LIST_URL}" | head -1) \
    || die "Failed to fetch PIA server list"

  echo "${resp}" > "$cache"
  info "Server list cached"
  echo "${resp}"
}

select_server() {
  local region="$1"
  local servers; servers=$(fetch_server_list)

  local region_json
  region_json=$(echo "${servers}" | jq -r --arg r "$region" \
    '[.regions[] | select(.id==$r)] | .[0]')

  [[ -z "${region_json}" || "${region_json}" == "null" ]] && \
    die "Region '${region}' not found. Run '$0 list-regions' to see available regions."

  local wg_servers
  wg_servers=$(echo "${region_json}" | jq -r '.servers.wg // empty')
  [[ -z "${wg_servers}" || "${wg_servers}" == "null" ]] && \
    die "No WireGuard servers in region '${region}'"

  # WireGuard port — read from server list groups (reference: pia-wg.sh)
  local wg_port
  wg_port=$(echo "${servers}" | jq -r '.groups.wg[0].ports[0] // 1337')

  # Pick the server with lowest latency (ping all, take fastest)
  local best_cn best_ip best_ms=9999
  while IFS='|' read -r cn ip; do
    local ms
    ms=$(ping -c 1 -W 1 -q "${ip}" 2>/dev/null | awk -F'/' '/avg/{print int($5)}' || echo 9999)
    if (( ms < best_ms )); then
      best_ms=$ms; best_cn=$cn; best_ip=$ip
    fi
  done < <(echo "${wg_servers}" | jq -r '.[] | "\(.cn)|\(.ip)"')

  # Fall back to first server if all pings failed
  if [[ -z "${best_cn:-}" ]]; then
    best_cn=$(echo "${wg_servers}" | jq -r '.[0].cn')
    best_ip=$(echo "${wg_servers}" | jq -r '.[0].ip')
    best_ms="N/A"
  fi

  info "Selected server: ${best_cn} (${best_ip}) port ${wg_port} — ${best_ms}ms"
  echo "${best_cn}|${best_ip}|${wg_port}"
}

list_regions() {
  local servers; servers=$(fetch_server_list)
  echo -e "\n${BOLD}Available PIA WireGuard regions:${NC}\n"
  echo "${servers}" | jq -r \
    '[.regions[] | select(.servers.wg != null)] | sort_by(.name)[] | "  \(.id)\t\(.name)"' \
    | column -t -s $'\t'
  echo
}

# ─────────────────────────────────────────────────────────────────────────────
# WireGuard key management
# ─────────────────────────────────────────────────────────────────────────────

ensure_wg_keys() {
  local force="${1:-false}"
  local privkey_file="${DATA_DIR}/private.key"
  local pubkey_file="${DATA_DIR}/public.key"

  if [[ "$force" != "true" && -f "${privkey_file}" && -f "${pubkey_file}" ]]; then
    info "Reusing existing WireGuard keypair"
    cat "${pubkey_file}"
    return 0
  fi

  log "Generating new WireGuard keypair..."
  local privkey pubkey
  privkey=$(wg genkey)
  pubkey=$(echo "${privkey}" | wg pubkey)
  printf '%s' "${privkey}" > "${privkey_file}"
  printf '%s' "${pubkey}"  > "${pubkey_file}"
  chmod 600 "${privkey_file}"
  chmod 644 "${pubkey_file}"
  info "WireGuard keypair generated"
  echo "${pubkey}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Key registration with PIA
# ─────────────────────────────────────────────────────────────────────────────

register_key() {
  local auth_token="$1"
  local server_cn="$2"
  local server_ip="$3"
  local pubkey="$4"
  local is_dip="${5:-false}"
  local server_port="${6:-1337}"

  log "Registering WireGuard key with ${server_cn} (${server_ip}:${server_port})..."

  local auth_args=()
  if [[ "${is_dip}" == "true" ]]; then
    # DIP auth: HTTP Basic with "dedicated_ip_{token}" as user, server IP as password
    # This matches the pia-foss/manual-connections reference implementation
    auth_args=(--user "dedicated_ip_${DIP_TOKEN}:${server_ip}")
  else
    auth_args=(--data-urlencode "pt=${auth_token}")
  fi

  local resp
  # Use --connect-to (matches working reference scripts) — routes TLS to server_ip
  # while preserving the correct SNI hostname for certificate verification.
  resp=$(curl_retry -sS --max-time 15 -G \
    --connect-to "${server_cn}::${server_ip}:" \
    --cacert "${DATA_DIR}/ca.rsa.4096.crt" \
    "${auth_args[@]}" \
    --data-urlencode "pubkey=${pubkey}" \
    "https://${server_cn}:1337/addKey") \
    || die "curl failed during WireGuard key registration with ${server_cn}"

  local status
  status=$(echo "${resp}" | jq -r '.status // empty')
  if [[ "${status}" != "OK" ]]; then
    err "addKey response: ${resp}"
    die "Key registration failed (status='${status}'). If you see an auth error, run with --new-token."
  fi

  echo "${resp}" > "${DATA_DIR}/server.json"
  info "Key registered — assigned peer IP: $(echo "${resp}" | jq -r '.peer_ip')"
  echo "${resp}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Config file builders
# ─────────────────────────────────────────────────────────────────────────────

# Resolve DNS list: honour override, fall back to PIA servers, then hardcoded fallback.
_resolve_dns() {
  local server_resp="$1"
  if [[ -n "${WG_DNS_OVERRIDE}" ]]; then
    echo "${WG_DNS_OVERRIDE}"
    return
  fi
  local dns
  dns=$(echo "${server_resp}" | jq -r '[.dns_servers[]?] | join(",")' 2>/dev/null || true)
  [[ -z "${dns}" || "${dns}" == "null" ]] && dns="10.0.0.243,10.0.0.242"
  echo "${dns}"
}

# Write the standard wg-quick .conf used in standalone mode (interface = WG_IFACE)
write_wg_conf() {
  local server_resp="$1"
  local server_ip="$2"

  local privkey peer_ip server_key server_port dns
  privkey=$(cat "${DATA_DIR}/private.key")
  peer_ip=$(echo "${server_resp}"    | jq -r '.peer_ip')
  # PIA sometimes omits the prefix length — wg-quick requires CIDR notation
  [[ "${peer_ip}" != */* ]] && peer_ip="${peer_ip}/32"
  server_key=$(echo "${server_resp}" | jq -r '.server_key')
  server_port=$(echo "${server_resp}"| jq -r '.server_port')
  dns=$(_resolve_dns "${server_resp}")

  for var in peer_ip server_key server_port; do
    val="${!var}"
    [[ -z "$val" || "$val" == "null" ]] && die "Missing ${var} in server response"
  done

  local conf="${DATA_DIR}/${WG_IFACE}.conf"
  cat > "${conf}" <<EOF
[Interface]
Address = ${peer_ip}
PrivateKey = ${privkey}
DNS = ${dns}

[Peer]
PublicKey = ${server_key}
AllowedIPs = 0.0.0.0/0
Endpoint = ${server_ip}:${server_port}
PersistentKeepalive = 25
EOF
  chmod 600 "${conf}"

  # Persist connection metadata for watchdog / status
  cat > "${DATA_DIR}/connection.json" <<EOF
{
  "profile_name":  "${PROFILE_NAME}",
  "wg_iface":      "${WG_IFACE}",
  "server_cn":     "${server_ip}",
  "server_ip":     "${server_ip}",
  "server_port":   ${server_port},
  "peer_ip":       "${peer_ip}",
  "dns":           "${dns}",
  "established_at": $(date +%s)
}
EOF
  info "WireGuard config written: ${conf}"
  echo "${conf}"
}

# Build Firewalla-specific profile files (.conf + .json + .settings)
build_firewalla_profiles() {
  local server_resp="$1"
  local server_ip="$2"
  local server_cn="${3:-${server_ip}}"

  local privkey peer_ip server_key server_port dns dns_json
  privkey=$(cat "${DATA_DIR}/private.key")
  peer_ip=$(echo "${server_resp}"    | jq -r '.peer_ip')
  # PIA sometimes omits the prefix length
  [[ "${peer_ip}" != */* ]] && peer_ip="${peer_ip}/32"
  server_key=$(echo "${server_resp}" | jq -r '.server_key')
  server_port=$(echo "${server_resp}"| jq -r '.server_port')
  dns=$(_resolve_dns "${server_resp}")
  dns_json=$(echo "${dns}" | tr ',' '\n' | jq -R . | jq -sc .)

  local name="${PROFILE_NAME}"

  # .conf — WireGuard native format (no wg-quick extensions).
  # Firewalla reads this with plain wg commands; Address and DNS are managed
  # via .json and Firewalla's own subsystem.
  printf '[Interface]\nPrivateKey = %s\n[Peer]\nPublicKey = %s\nEndpoint = %s:%s\nPersistentKeepalive = 25\nAllowedIPs = 0.0.0.0/0\n' \
    "${privkey}" "${server_key}" "${server_ip}" "${server_port}" \
    > "${DATA_DIR}/${name}.conf"
  chmod 600 "${DATA_DIR}/${name}.conf"

  # .json — Firewalla VPN peer metadata (compact single-line, matches Firewalla format)
  printf '{"peers":[{"publicKey":"%s","endpoint":"%s:%s","persistentKeepalive":25,"allowedIPs":["0.0.0.0/0"]}],"addresses":["%s"],"privateKey":"%s","dns":%s}\n' \
    "${server_key}" "${server_ip}" "${server_port}" "${peer_ip}" "${privkey}" "${dns_json}" \
    > "${DATA_DIR}/${name}.json"
  chmod 600 "${DATA_DIR}/${name}.json"

  # .settings — Firewalla routing policy (compact single-line, matches working profiles)
  # routeDNS:false — "true" causes iptables chain name to exceed 29-char kernel limit
  # strictVPN:false — avoids routing conflicts during tunnel establishment
  # serverDDNS must resolve to the VPN server IP so Firewalla can add the endpoint route
  # (bypassing the tunnel for handshake packets).  PIA's short CN ("chicago424") isn't a
  # resolvable FQDN, so we use the numeric IP — getaddrinfo() handles IP strings directly.
  local created_date; created_date="$(date +%s).0"
  printf '{"serverSubnets":[],"overrideDefaultRoute":true,"routeDNS":false,"c2sSNATDisabled":false,"strictVPN":false,"createdDate":%s,"displayName":"%s","serverVPNPort":%s,"serverDDNS":"%s","subtype":"wireguard"}\n' \
    "${created_date}" "${PROFILE_NAME}" "${server_port}" "${server_ip}" \
    > "${DATA_DIR}/${name}.settings"
  chmod 644 "${DATA_DIR}/${name}.settings"

  # .endpoint_routes — tells Firewalla to route traffic to the VPN server IP via
  # the normal gateway rather than through the not-yet-up tunnel (prevents handshake loop)
  local gw dev pref=8192
  gw=$(ip route show default 2>/dev/null | awk '/default via/{print $3; exit}')
  dev=$(ip route show default 2>/dev/null | awk '/default via/{print $5; exit}')
  # Borrow the lowest pref from any existing endpoint_routes (= primary WAN priority)
  local ep_file p
  for ep_file in "${FW_PROFILE_DIR}"/*.endpoint_routes; do
    [[ -f "${ep_file}" ]] || continue
    p=$(jq -r '.[0].pref // empty' "${ep_file}" 2>/dev/null || true)
    [[ -n "${p}" && "${p}" -lt "${pref}" ]] && pref="${p}"
  done

  if [[ -n "${gw}" && -n "${dev}" ]]; then
    printf '[{"ip":"%s","gw":"%s","dev":"%s","pref":%s}]' \
      "${server_ip}" "${gw}" "${dev}" "${pref}" \
      > "${DATA_DIR}/${name}.endpoint_routes"
    info "Endpoint routes: ${server_ip} via ${gw} dev ${dev} pref ${pref}"
  else
    warn "Could not detect default gateway — .endpoint_routes not written; Firewalla may fail to connect"
  fi

  info "Firewalla profile files written: ${name}.{conf,json,settings,endpoint_routes}"
  echo "${name}"
}

deploy_to_firewalla() {
  local name="$1"
  local deployed=0

  for fw_dir in "${FW_PROFILE_DIR}" "${FW_OVERLAY_DIR}"; do
    # Only deploy if the parent directory exists (i.e. we're on Firewalla)
    if [[ -d "$(dirname "${fw_dir}")" ]]; then
      mkdir -p "${fw_dir}"
      cat "${DATA_DIR}/${name}.conf"     > "${fw_dir}/${name}.conf"
      cat "${DATA_DIR}/${name}.json"     > "${fw_dir}/${name}.json"
      cat "${DATA_DIR}/${name}.settings" > "${fw_dir}/${name}.settings"
      [[ -f "${DATA_DIR}/${name}.endpoint_routes" ]] && \
        cat "${DATA_DIR}/${name}.endpoint_routes" > "${fw_dir}/${name}.endpoint_routes"
      # Use numeric UID/GID — the container (Alpine) has no "pi" user
      chown 1000:1000 "${fw_dir}/${name}".* 2>/dev/null || true
      info "Deployed to ${fw_dir}"
      (( deployed++ )) || true
    fi
  done

  if (( deployed == 0 )); then
    warn "Firewalla profile directories not found — profile files remain in ${DATA_DIR}"
    warn "Copy ${PROFILE_NAME}.{conf,json,settings} to ${FW_PROFILE_DIR} manually."
  else
    info "────────────────────────────────────────────────────────────"
    info "Profile '${name}' deployed to Firewalla."
    info "Activate it: Firewalla app → VPN Client → WireGuard → ${name}"
    info "────────────────────────────────────────────────────────────"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# App-integration mode: update a Firewalla-app-created profile in place
# ─────────────────────────────────────────────────────────────────────────────

# Update the .conf (and .json) of a profile the user created via the Firewalla
# app.  The app assigns a hash-based profile ID (e.g. "682D_682DF"); set
# FIREWALLA_PROFILE_ID to that value.
#
# Why this works better than creating profiles externally:
#   When the user pastes a WireGuard config into the Firewalla app, Firewalla
#   fully registers the profile in its internal state, including IP assignment
#   and routing.  Subsequent updates to the same .conf/.json files are then
#   picked up cleanly on the next connect (or via wg syncconf if already up).
#
# .conf format: wg-quick (includes Address = ...) so Firewalla knows what IP
#   to assign to the interface via `ip addr add`.
update_existing_profile() {
  local server_resp="$1"
  local server_ip="$2"

  local privkey peer_ip server_key server_port dns dns_json
  privkey=$(cat "${DATA_DIR}/private.key")
  peer_ip=$(echo "${server_resp}"    | jq -r '.peer_ip')
  [[ "${peer_ip}" != */* ]] && peer_ip="${peer_ip}/32"
  server_key=$(echo "${server_resp}" | jq -r '.server_key')
  server_port=$(echo "${server_resp}"| jq -r '.server_port')
  dns=$(_resolve_dns "${server_resp}")
  dns_json=$(echo "${dns}" | tr ',' '\n' | jq -R . | jq -sc .)

  local deployed=0
  for fw_dir in "${FW_PROFILE_DIR}" "${FW_OVERLAY_DIR}"; do
    local target_conf="${fw_dir}/${FIREWALLA_PROFILE_ID}.conf"
    local target_json="${fw_dir}/${FIREWALLA_PROFILE_ID}.json"
    [[ -f "${target_conf}" ]] || continue

    # Write wg-quick format conf WITH Address.
    # Firewalla parses Address to run `ip addr add <peer_ip> dev <iface>` before
    # calling `wg setconf` (which strips wg-quick extensions).
    {
      printf '[Interface]\nPrivateKey = %s\nAddress = %s\n' "${privkey}" "${peer_ip}"
      # Preserve any DNS line the user may have added via the app
      grep -E '^DNS[[:space:]]*=' "${target_conf}" 2>/dev/null || true
      printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = 0.0.0.0/0\nEndpoint = %s:%s\nPersistentKeepalive = 25\n' \
        "${server_key}" "${server_ip}" "${server_port}"
    } > "${target_conf}.new"
    mv "${target_conf}.new" "${target_conf}"
    chmod 600 "${target_conf}"

    # Update .json — peer public key and endpoint change on each registration
    if [[ -f "${target_json}" ]]; then
      printf '{"peers":[{"publicKey":"%s","endpoint":"%s:%s","persistentKeepalive":25,"allowedIPs":["0.0.0.0/0"]}],"addresses":["%s"],"privateKey":"%s","dns":%s}\n' \
        "${server_key}" "${server_ip}" "${server_port}" "${peer_ip}" "${privkey}" "${dns_json}" \
        > "${target_json}.new"
      mv "${target_json}.new" "${target_json}"
      chmod 600 "${target_json}"
    fi

    # Update .settings — serverDDNS is used by Firewalla to add the endpoint
    # bypass route (traffic to the VPN server must NOT go through the tunnel).
    # serverVPNPort drives the same route; both must reflect the current server.
    # We patch only these two fields so we don't clobber the user's app settings
    # (displayName, device routing rules, overrideDefaultRoute, strictVPN, etc.).
    local target_settings="${fw_dir}/${FIREWALLA_PROFILE_ID}.settings"
    if [[ -f "${target_settings}" ]]; then
      jq --arg ip "${server_ip}" --argjson port "${server_port}" \
        '.serverDDNS = $ip | .serverVPNPort = $port' \
        "${target_settings}" > "${target_settings}.new"
      mv "${target_settings}.new" "${target_settings}"
      chmod 644 "${target_settings}"
    fi

    chown 1000:1000 "${fw_dir}/${FIREWALLA_PROFILE_ID}".* 2>/dev/null || true
    info "Updated Firewalla profile '${FIREWALLA_PROFILE_ID}' in ${fw_dir}"
    (( deployed++ )) || true
  done

  if (( deployed == 0 )); then
    err "Profile '${FIREWALLA_PROFILE_ID}.conf' not found in Firewalla profile directories."
    err "Run 'generate-config', paste the output into the Firewalla app"
    err "(VPN Client → Add VPN → WireGuard → paste config), then set FIREWALLA_PROFILE_ID."
    return 1
  fi

  # Hot-reload if the interface is already active (no connection drop)
  if is_iface_up; then
    info "Interface ${WG_IFACE_ACTUAL} active — hot-reloading config via wg syncconf"
    _wg_syncconf "${FW_PROFILE_DIR}/${FIREWALLA_PROFILE_ID}.conf"
  fi
}

# Generate a wg-quick format config for initial import into the Firewalla app.
# Usage: ./pia-wg-firewalla.sh generate-config [--new-keys] [--new-token]
generate_wg_config() {
  local force_keys="${1:-false}"
  local force_token="${2:-false}"

  log "=== Generating PIA WireGuard config (for Firewalla app import) ==="
  [[ -n "${DIP_TOKEN}" ]] && info "Mode: Dedicated IP" || info "Mode: Standard (region: ${PIA_REGION})"

  init_data_dir

  local pubkey; pubkey=$(ensure_wg_keys "${force_keys}")
  local auth_token; auth_token=$(get_pia_token "${force_token}")

  local server_cn server_ip server_port=1337 is_dip=false
  if [[ -n "${DIP_TOKEN}" ]]; then
    is_dip=true
    local pair; pair=$(get_dip_server "${auth_token}")
    server_cn="${pair%%|*}"; server_ip="${pair#*|}"
    server_port="${DIP_PORT:-1337}"
  else
    local pair; pair=$(select_server "${PIA_REGION}")
    IFS='|' read -r server_cn server_ip server_port <<< "${pair}"
  fi

  local server_resp
  server_resp=$(register_key "${auth_token}" "${server_cn}" "${server_ip}" "${pubkey}" "${is_dip}" "${server_port}")

  local peer_ip server_key
  peer_ip=$(echo "${server_resp}"    | jq -r '.peer_ip')
  [[ "${peer_ip}" != */* ]] && peer_ip="${peer_ip}/32"
  server_key=$(echo "${server_resp}" | jq -r '.server_key')

  touch "${DATA_DIR}/last_setup"
  echo "${server_resp}" > "${DATA_DIR}/server.json"

  # Print to stdout for the user to copy
  cat <<EOF

══════════════════════════════════════════════════════════════
 STEP 1 — Copy this WireGuard config:
══════════════════════════════════════════════════════════════

[Interface]
PrivateKey = $(cat "${DATA_DIR}/private.key")
Address = ${peer_ip}

[Peer]
PublicKey = ${server_key}
AllowedIPs = 0.0.0.0/0
Endpoint = ${server_ip}:${server_port}
PersistentKeepalive = 25

══════════════════════════════════════════════════════════════
 STEP 2 — Paste into the Firewalla app:
   Network → VPN Client → Add VPN → WireGuard → paste above
   Give it any name (e.g. "PIA-DIP"), then Save (don't enable yet).

 STEP 3 — Find the profile ID Firewalla assigned:
   ls -t ~/.firewalla/run/wg_profile/*.conf | head -1
   (use the filename without .conf, e.g. "682D_682DF")

 STEP 4 — Set it in docker-compose.yml:
   FIREWALLA_PROFILE_ID: "682D_682DF"

 STEP 5 — Restart the container and enable VPN in app:
   docker compose up -d
   Then: Firewalla app → VPN Client → [your profile] → Enable
══════════════════════════════════════════════════════════════

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# WireGuard interface management (standalone mode only)
# ─────────────────────────────────────────────────────────────────────────────

wg_up() {
  local conf="${DATA_DIR}/${WG_IFACE}.conf"
  [[ -f "${conf}" ]] || die "Config not found: ${conf}"

  if is_iface_up; then
    log "Interface ${WG_IFACE} already exists — syncing config"
    _wg_syncconf "${conf}"
    return 0
  fi

  log "Bringing up ${WG_IFACE}..."
  wg-quick up "${conf}" || die "wg-quick failed to bring up ${WG_IFACE}"
  info "${WG_IFACE} is up"
}

wg_down() {
  local conf="${DATA_DIR}/${WG_IFACE}.conf"
  if is_iface_up; then
    log "Bringing down ${WG_IFACE}..."
    wg-quick down "${conf}" 2>/dev/null \
      || ip link delete "${WG_IFACE}" 2>/dev/null \
      || true
  fi
}

# Strip wg-quick directives so `wg syncconf` accepts the file
_wg_syncconf() {
  local conf="$1"
  local stripped
  stripped=$(grep -v -E '^\s*(Address|DNS|MTU|Table|PreUp|PostUp|PreDown|PostDown|SaveConfig)\s*=' \
    "${conf}")
  wg syncconf "${WG_IFACE_ACTUAL}" <(echo "${stripped}")
}

# ─────────────────────────────────────────────────────────────────────────────
# Core setup orchestration
# ─────────────────────────────────────────────────────────────────────────────

do_setup() {
  local force_keys="${1:-false}"
  local force_token="${2:-false}"

  log "=== PIA WireGuard Setup (v${VERSION}) ==="
  [[ -n "${DIP_TOKEN}" ]] && info "Mode: Dedicated IP" || info "Mode: Standard (region: ${PIA_REGION})"

  init_data_dir

  local pubkey
  pubkey=$(ensure_wg_keys "${force_keys}")

  local auth_token
  auth_token=$(get_pia_token "${force_token}")

  local server_cn server_ip server_port=1337 is_dip=false
  if [[ -n "${DIP_TOKEN}" ]]; then
    is_dip=true
    local pair; pair=$(get_dip_server "${auth_token}")
    server_cn="${pair%%|*}"
    server_ip="${pair#*|}"
    # DIP port: use override if set, otherwise default 1337
    server_port="${DIP_PORT:-1337}"
  else
    local pair; pair=$(select_server "${PIA_REGION}")
    IFS='|' read -r server_cn server_ip server_port <<< "${pair}"
  fi

  local server_resp
  server_resp=$(register_key "${auth_token}" "${server_cn}" "${server_ip}" "${pubkey}" "${is_dip}" "${server_port}")

  if [[ "${WG_MANAGED_BY_FIREWALLA}" == "true" && -n "${FIREWALLA_PROFILE_ID}" ]]; then
    # ── App-integration mode ──────────────────────────────────────────────────
    # Update the existing Firewalla-app-created profile files in place.
    # The user created this profile by pasting the 'generate-config' output into
    # the Firewalla app; we just keep its keys/endpoint/address up to date.
    update_existing_profile "${server_resp}" "${server_ip}"

  elif [[ "${WG_MANAGED_BY_FIREWALLA}" == "true" ]]; then
    # ── Legacy external-profile mode ─────────────────────────────────────────
    # Create Firewalla profile files from scratch (no FIREWALLA_PROFILE_ID set).
    local fw_name
    fw_name=$(build_firewalla_profiles "${server_resp}" "${server_ip}" "${server_cn}")
    deploy_to_firewalla "${fw_name}"
    if is_iface_up; then
      local fw_conf="${DATA_DIR}/${PROFILE_NAME}.conf"
      info "Interface ${WG_IFACE_ACTUAL} is active — syncing new config"
      _wg_syncconf "${fw_conf}"
    fi

  else
    # ── Standalone mode ───────────────────────────────────────────────────────
    # wg-quick manages the interface directly (no Firewalla app involvement).
    write_wg_conf "${server_resp}" "${server_ip}"
    wg_up
  fi

  # Record timestamp so the watchdog knows when keys were last registered
  touch "${DATA_DIR}/last_setup"
  log "=== Setup complete ==="
}

# ─────────────────────────────────────────────────────────────────────────────
# Watchdog
# ─────────────────────────────────────────────────────────────────────────────

get_handshake_age() {
  local ts
  ts=$(wg show "${WG_IFACE_ACTUAL}" latest-handshakes 2>/dev/null \
    | awk 'NF>=2{print $2; exit}')
  [[ -z "${ts}" || "${ts}" == "0" ]] && echo 999999 && return
  echo $(( $(date +%s) - ts ))
}

check_connectivity() {
  ping -c 2 -W 3 -I "${WG_IFACE_ACTUAL}" "${VPN_CHECK_IP}" &>/dev/null
}

do_reconnect() {
  local attempt="${1:-1}"
  local backoff=$(( 2 ** (attempt - 1) ))
  (( backoff > 120 )) && backoff=120

  warn "Reconnect attempt ${attempt}/${MAX_RECONNECT_ATTEMPTS} (backoff ${backoff}s)..."
  (( attempt > 1 )) && sleep "${backoff}"

  # Bring down cleanly before re-setup (standalone only)
  if [[ "${WG_MANAGED_BY_FIREWALLA}" != "true" ]]; then
    wg_down 2>/dev/null || true
    sleep 2
  fi

  # Force a fresh token on every reconnect attempt
  do_setup "false" "true"
}

run_watchdog() {
  local down_time=0
  local reconnect_attempts=0

  log "Watchdog active — interface ${WG_IFACE_ACTUAL} | interval ${WATCHDOG_INTERVAL}s | handshake_max ${HANDSHAKE_MAX_AGE}s | reconnect_after ${MAX_DOWN_TIME}s"

  while true; do
    sleep "${WATCHDOG_INTERVAL}"

    if ! is_iface_up; then
      if [[ "${WG_MANAGED_BY_FIREWALLA}" == "true" ]]; then
        # Interface down is normal in Firewalla mode — the app controls it.
        # However, PIA expires key registrations if no handshake arrives within
        # ~3 minutes of addKey. Refresh periodically so the registration is always
        # fresh when the user taps Connect in the Firewalla app.
        local key_age; key_age=$(file_age "${DATA_DIR}/last_setup")
        if (( key_age >= KEY_REFRESH_INTERVAL )); then
          log "Key registration is ${key_age}s old (limit ${KEY_REFRESH_INTERVAL}s) — refreshing..."
          do_setup "false" "false"
        else
          log "Interface ${WG_IFACE_ACTUAL} not up — Firewalla manages connection (key registered ${key_age}s ago, refresh in $(( KEY_REFRESH_INTERVAL - key_age ))s)"
        fi
      else
        warn "Interface ${WG_IFACE_ACTUAL} is not up"
        (( down_time += WATCHDOG_INTERVAL ))
      fi
    else
      local hs_age
      hs_age=$(get_handshake_age)

      if (( hs_age > HANDSHAKE_MAX_AGE )); then
        warn "Stale handshake: ${hs_age}s (max ${HANDSHAKE_MAX_AGE}s)"
        (( down_time += WATCHDOG_INTERVAL ))
      elif ! check_connectivity; then
        warn "No ping response from ${VPN_CHECK_IP} through ${WG_IFACE_ACTUAL}"
        (( down_time += WATCHDOG_INTERVAL ))
      else
        (( down_time > 0 )) && info "VPN connectivity restored after ${down_time}s"
        down_time=0
        reconnect_attempts=0
        log "VPN healthy — handshake ${hs_age}s ago"
        continue
      fi
    fi

    log "Cumulative down time: ${down_time}s / ${MAX_DOWN_TIME}s"

    if (( down_time >= MAX_DOWN_TIME )); then
      (( reconnect_attempts++ ))

      if (( reconnect_attempts > MAX_RECONNECT_ATTEMPTS )); then
        err "Exhausted ${MAX_RECONNECT_ATTEMPTS} reconnect attempts — cooling off 5 min"
        sleep 300
        reconnect_attempts=0
        down_time=0
        continue
      fi

      do_reconnect "${reconnect_attempts}"
      down_time=0
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Status display
# ─────────────────────────────────────────────────────────────────────────────

show_status() {
  echo -e "\n${BOLD}PIA WireGuard Status${NC}"
  echo    "──────────────────────────────────────────────"

  if is_iface_up; then
    local hs_age; hs_age=$(get_handshake_age)
    local hs_color; (( hs_age < HANDSHAKE_MAX_AGE )) && hs_color="${GREEN}" || hs_color="${YELLOW}"
    echo -e "Interface:    ${GREEN}UP${NC} (${WG_IFACE})"
    echo -e "Handshake:    ${hs_color}${hs_age}s ago${NC}"
    if check_connectivity; then
      echo -e "Connectivity: ${GREEN}OK${NC} (${VPN_CHECK_IP} reachable)"
    else
      echo -e "Connectivity: ${RED}FAIL${NC} (${VPN_CHECK_IP} unreachable)"
    fi
    wg show "${WG_IFACE}" 2>/dev/null | grep -E '(endpoint|transfer)' | sed 's/^/  /' || true
  else
    echo -e "Interface:    ${RED}DOWN${NC} (${WG_IFACE})"
  fi

  local token_file="${DATA_DIR}/token"
  if [[ -f "${token_file}" ]]; then
    local age; age=$(file_age "${token_file}")
    local ttl_remain=$(( TOKEN_TTL - age ))
    if (( ttl_remain > 0 )); then
      echo -e "Token:        ${GREEN}Valid${NC} (expires in ~$(( ttl_remain / 3600 ))h $(( (ttl_remain % 3600) / 60 ))m)"
    else
      echo -e "Token:        ${RED}Expired${NC}"
    fi
  else
    echo -e "Token:        ${YELLOW}Not cached${NC}"
  fi

  local conn="${DATA_DIR}/connection.json"
  if [[ -f "${conn}" ]]; then
    echo "Server IP:    $(jq -r '.server_ip'  "${conn}")"
    echo "Peer IP:      $(jq -r '.peer_ip'    "${conn}")"
    local ts; ts=$(jq -r '.established_at' "${conn}")
    echo "Established:  $(date -d "@${ts}" 2>/dev/null || echo "${ts}")"
  fi

  echo "Profile:      ${PROFILE_NAME}"
  if [[ -n "${DIP_TOKEN}" ]]; then
    echo -e "Account type: ${CYAN}Dedicated IP${NC}"
  else
    echo    "Region:       ${PIA_REGION}"
  fi
  echo "──────────────────────────────────────────────"
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF

${BOLD}pia-wg-firewalla.sh${NC} v${VERSION}
PIA WireGuard VPN for Firewalla — dedicated IP support, automatic token refresh

${BOLD}USAGE${NC}
  $0 <command> [options]

${BOLD}COMMANDS${NC}
  generate-config  Generate initial WireGuard config to paste into the Firewalla app
  start            Setup + launch watchdog (use for Docker / systemd)
  setup            One-time setup / key refresh
  reconnect        Force fresh token + reconnect
  watchdog         Run watchdog loop (assumes VPN already active)
  status           Show VPN health, token TTL, and connection info
  list-regions     List all available PIA WireGuard regions

${BOLD}RECOMMENDED WORKFLOW (Firewalla app integration)${NC}
  1.  docker compose exec pia-wg /app/pia-wg-firewalla.sh generate-config
  2.  Paste the printed config into Firewalla app → VPN Client → Add VPN → WireGuard
  3.  ls -t ~/.firewalla/run/wg_profile/*.conf | head -1   # find the profile ID
  4.  Set FIREWALLA_PROFILE_ID in docker-compose.yml and restart the container
  5.  Enable the VPN once in the Firewalla app — watchdog keeps it fresh

${BOLD}OPTIONS${NC}
  --new-keys     Regenerate WireGuard private/public keypair
  --new-token    Force PIA token refresh
  --region R     Override PIA_REGION for this run
  --profile N    Override PROFILE_NAME for this run

${BOLD}KEY ENVIRONMENT VARIABLES${NC}  (set in docker-compose.yml or .env)
  PIA_USER                  PIA username (required)
  PIA_PASS                  PIA password (required)
  DIP_TOKEN                 Dedicated IP token (omit for standard account)
  PIA_REGION                Server region, default: us_east
  FIREWALLA_PROFILE_ID      Hash-based profile ID from Firewalla app (recommended)
  WG_MANAGED_BY_FIREWALLA   true = Firewalla owns wg interface, default: false
  DATA_DIR                  State directory, default: /data/pia-wg
  WG_DNS_OVERRIDE           Comma-separated DNS servers (overrides PIA DNS)
  WATCHDOG_INTERVAL         Seconds between checks, default: 60
  MAX_DOWN_TIME             Seconds before reconnect, default: 300
  VPN_CHECK_IP              Ping target for connectivity check, default: 9.9.9.9

EOF
}

main() {
  local cmd="${1:-help}"
  shift || true

  # Parse flags
  local force_keys=false force_token=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --new-keys)   force_keys=true ;;
      --new-token)  force_token=true ;;
      --region)     PIA_REGION="$2";   shift ;;
      --profile)    PROFILE_NAME="$2"; WG_IFACE="$(echo "${PROFILE_NAME}" | tr -cd 'A-Za-z0-9_-' | cut -c1-15)"; shift ;;
      --help|-h)    usage; exit 0 ;;
      *) warn "Unknown option: $1" ;;
    esac
    shift
  done

  case "${cmd}" in
    generate-config)
      load_env; check_deps
      generate_wg_config "${force_keys}" "${force_token}"
      ;;
    start)
      load_env; check_deps

      # Tee all output (stdout + stderr) to a persistent log file so the web UI
      # can serve it, while still showing in `docker compose logs`.
      local log_file="${DATA_DIR}/pia-wg.log"
      exec > >(tee -a "${log_file}") 2>&1

      # ── Web UI ──────────────────────────────────────────────────────────
      local web_port="${WEB_PORT:-8080}"
      if [[ "${web_port}" != "0" ]]; then
        python3 /app/web_ui.py 2>&1 &
        log "Web UI started on port ${web_port} — open http://<firewalla-ip>:${web_port}"
      fi

      # Give the host network a moment to be ready before the first API call
      log "Waiting 5s for network to initialise..."
      sleep 5
      do_setup "${force_keys}" "${force_token}"
      run_watchdog
      ;;
    setup)
      load_env; check_deps
      do_setup "${force_keys}" "${force_token}"
      ;;
    reconnect)
      load_env; check_deps
      do_setup "false" "true"
      ;;
    watchdog)
      load_env; check_deps
      run_watchdog
      ;;
    status)
      load_env
      show_status
      ;;
    list-regions)
      load_env; check_deps
      list_regions
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      err "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
