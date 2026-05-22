# PIA WireGuard for Firewalla

A self-contained WireGuard VPN manager for [Firewalla](https://firewalla.com) that connects to [Private Internet Access (PIA)](https://www.privateinternetaccess.com). Supports **standard accounts**, **Dedicated IP**, automatic **token refresh**, and an always-on **watchdog** — deployable as a native systemd service or a Docker container.

---

## Features

| Feature | Details |
|---|---|
| **Standard & Dedicated IP** | Full support for PIA Dedicated IP tokens |
| **Auto token refresh** | Detects expired PIA tokens and re-authenticates transparently |
| **Watchdog** | Monitors handshake age + ping-through-VPN; reconnects after configurable downtime |
| **Firewalla native** | Generates `.conf` / `.json` / `.settings` profile files for Firewalla's VPN Client UI |
| **Docker** | Single `docker compose up -d` for containerised deployment |
| **Latency-aware server selection** | Pings all region servers, picks the fastest one |
| **One-command install** | `install.sh` handles deps, config, service registration |
| **Persistent keys** | WireGuard keypair survives restarts; token & server list are cached |

---

## Quick Start

### Option A — Native Firewalla (recommended)

```bash
# SSH into your Firewalla (default password: firewalla)
ssh pi@firewalla.local

# One-command install (interactive — prompts for credentials)
curl -fsSL https://raw.githubusercontent.com/maximumworf/firewalla-pia_wg/main/install.sh \
  | sudo bash

# After install: activate the profile in the Firewalla app
# → VPN Client → WireGuard → PIA_WG → Enable
```

### Option B — Docker (any Linux host, no repo clone needed)

A multi-arch image (`amd64` / `arm64` / `armv7`) is published automatically to GitHub Container Registry on every push to `main`. You only need two files:

```bash
mkdir pia-wg && cd pia-wg

# Grab the compose file and config template — that's all you need
curl -fsSL https://raw.githubusercontent.com/MaximumWorf/firewalla-pia_wg/main/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/MaximumWorf/firewalla-pia_wg/main/.env.example -o .env

# Set your credentials (at minimum PIA_USER and PIA_PASS)
nano .env

# Pull image and start — no build step required
docker compose up -d
docker compose logs -f
```

### Option C — Manual

```bash
git clone https://github.com/maximumworf/firewalla-pia_wg
cd firewalla-pia_wg

cp .env.example .env
nano .env   # add PIA_USER, PIA_PASS, and optionally DIP_TOKEN

chmod +x pia-wg-firewalla.sh
sudo ./pia-wg-firewalla.sh setup   # one-time setup
sudo ./pia-wg-firewalla.sh start   # setup + watchdog (blocks)
```

---

## Configuration

All settings live in `.env`. Copy `.env.example` to get started:

```bash
cp .env.example .env
```

### Minimum required

```dotenv
PIA_USER=p1234567
PIA_PASS=your_password
```

### Dedicated IP

Paste the token from your PIA account dashboard:

```dotenv
DIP_TOKEN=your_dedicated_ip_token_from_pia_dashboard
```

When `DIP_TOKEN` is set, `PIA_REGION` is ignored — the server is determined by the dedicated IP assignment.

### Key settings

| Variable | Default | Description |
|---|---|---|
| `PIA_REGION` | `us_east` | Server region. Run `list-regions` to see all options. |
| `PROFILE_NAME` | `PIA_WG` | WireGuard interface name and Firewalla profile name. |
| `WG_MANAGED_BY_FIREWALLA` | `false` | `true` = Firewalla owns the WG interface; `false` = script uses wg-quick. |
| `DATA_DIR` | `/data/pia-wg` | Directory for keys, token cache, and configs. |
| `WG_DNS_OVERRIDE` | *(empty)* | Override DNS; blank uses PIA's servers. |
| `WATCHDOG_INTERVAL` | `60` | Seconds between watchdog checks. |
| `HANDSHAKE_MAX_AGE` | `120` | Max handshake age (seconds) before considering tunnel stale. |
| `MAX_DOWN_TIME` | `300` | Seconds of continuous downtime before reconnecting. |
| `MAX_RECONNECT_ATTEMPTS` | `5` | Reconnect attempts before 5-minute back-off. |
| `TOKEN_TTL` | `72000` | Cached token lifetime in seconds (PIA tokens last ~24 h). |

---

## Commands

```
./pia-wg-firewalla.sh <command> [options]

Commands:
  start          Setup + run watchdog (use for Docker / systemd)
  setup          One-time setup only
  reconnect      Force fresh token + reconnect now
  watchdog       Run watchdog only (VPN must already be active)
  status         Show VPN health, token TTL, and connection info
  list-regions   List all available PIA WireGuard regions

Options:
  --new-keys     Regenerate WireGuard keypair
  --new-token    Force PIA token refresh
  --region R     Override PIA_REGION for this run
  --profile N    Override PROFILE_NAME for this run
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│ pia-wg-firewalla.sh start                               │
│                                                         │
│  1. Load .env config                                    │
│  2. Generate / reuse WireGuard keypair                  │
│  3. Authenticate → PIA token (cached 20 h)             │
│  4a. Standard: fetch server list, pick fastest server   │
│  4b. DIP: query PIA dedicated IP API for server info    │
│  5. Register WireGuard pubkey with chosen server        │
│  6. Write wg0.conf (wg-quick format)                    │
│  7. Write Firewalla profile: .conf + .json + .settings  │
│  8. Deploy profile to Firewalla dirs                    │
│  9. wg-quick up  (standalone) / wg syncconf (Firewalla) │
│ 10. Watchdog loop ─────────────────────────────────┐    │
│      every 60s:                                    │    │
│        check handshake age < 120s?    ─── OK ──────┘    │
│        ping 9.9.9.9 through VPN?      ─── FAIL ──►      │
│        accumulate down_time                              │
│        at 300s: refresh token + reconnect               │
│        exponential backoff on repeated failure          │
└─────────────────────────────────────────────────────────┘
```

### Firewalla profile files

The script writes three files per profile to `/home/pi/.firewalla/run/wg_profile/` (and the overlay path):

| File | Purpose |
|---|---|
| `PIA_WG.conf` | Standard wg-quick config — Firewalla reads this |
| `PIA_WG.json` | Firewalla peer metadata (endpoints, keys, addresses) |
| `PIA_WG.settings` | Routing policy (`overrideDefaultRoute`, `routeDNS`, `strictVPN`) |

After `setup` or `start`, open the **Firewalla app → VPN Client → WireGuard** to enable the profile. Subsequent reconnects by the watchdog use `wg syncconf` to update the peer without disabling the tunnel.

### Token refresh

PIA tokens are valid for ~24 hours. The watchdog detects that the tunnel is down after `MAX_DOWN_TIME` seconds and automatically calls `get_pia_token --force`, which re-authenticates and re-registers the WireGuard key before reconnecting.

---

## Docker details

The container runs with `network_mode: host` and `cap_add: [NET_ADMIN, SYS_MODULE]` so it can create a real WireGuard interface on the host. The `pia-wg-data` named volume persists keys, the PIA token, and the server list — so container restarts don't trigger a full re-registration.

### Image

Pre-built multi-arch image published on every push to `main`:
```
ghcr.io/maximumworf/firewalla-pia_wg:latest
```
Architectures: `linux/amd64`, `linux/arm64`, `linux/arm/v7` (covers Firewalla Gold/Purple/SE).

### Useful commands

```bash
docker compose exec pia-wg /app/pia-wg-firewalla.sh status
docker compose exec pia-wg /app/pia-wg-firewalla.sh reconnect
docker compose exec pia-wg /app/pia-wg-firewalla.sh list-regions
docker compose logs -f --tail 100
docker compose pull && docker compose up -d   # update to latest image
```

### Optional: also write Firewalla profiles from Docker

Uncomment the two volume mounts in `docker-compose.yml` and add `WG_MANAGED_BY_FIREWALLA=true` to `.env`. The container will deploy profile files into Firewalla's profile directory, and Firewalla's own WireGuard subsystem will own the interface. The watchdog will use `wg syncconf` to update the peer on reconnect.

---

## Troubleshooting

**`wg-quick: PIA_WG: Operation not permitted`**
The process needs `NET_ADMIN`. In Docker, ensure `cap_add: [NET_ADMIN]`. Natively, run as root.

**`Key registration failed (status=unauthorized)`**
Your PIA credentials are wrong, or the token expired mid-setup. Run `./pia-wg-firewalla.sh reconnect --new-token`.

**Profile not appearing in Firewalla app**
Verify the files exist in `/home/pi/.firewalla/run/wg_profile/`. If running in Docker, the Firewalla volume mounts in `docker-compose.yml` must be uncommented.

**Handshake never arrives**
Check that UDP port 1337 is not blocked by your ISP. Try a different region with `--region`.

**Dedicated IP token rejected**
Ensure `DIP_TOKEN` is the raw token string from the PIA dashboard (not your password). The `PIA_USER` and `PIA_PASS` are still required for the initial auth token.

---

## Credits

- [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections) — official PIA API reference
- [triffid/pia-wg](https://github.com/triffid/pia-wg) — token caching and server selection approach
- [JasonMeudt/Firewalla-pia-wireguard](https://github.com/JasonMeudt/Firewalla-pia-wireguard) — Firewalla profile file format and watchdog design
