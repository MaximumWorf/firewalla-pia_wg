# PIA WireGuard for Firewalla

A self-contained WireGuard VPN manager for [Firewalla](https://firewalla.com) that connects to [Private Internet Access (PIA)](https://www.privateinternetaccess.com). Supports **standard accounts** and **Dedicated IP**, with automatic **token refresh** and an always-on **watchdog** that reconnects the tunnel if it ever drops.

---

## Features

| | |
|---|---|
| **Standard & Dedicated IP** | Full support for PIA Dedicated IP tokens |
| **Auto token refresh** | PIA tokens expire after ~24 h — the watchdog detects this and re-authenticates transparently |
| **Always-on watchdog** | Checks handshake age every 60 s; reconnects with exponential back-off if the tunnel drops |
| **Firewalla app integration** | Updates the profile the Firewalla app created — VPN appears and is controllable in the app |
| **Docker — no clone needed** | Pull a pre-built image, fill in two fields, run |
| **Web UI** | Browser dashboard at `http://<firewalla-ip>:8080` — status, logs, settings, generate config |
| **Latency-aware server selection** | Pings every server in the region, picks the fastest |
| **Persistent keys** | WireGuard keypair and token cache survive restarts |

---

## Deployment options

| Method | Best for |
|---|---|
| [Docker](#option-a--docker-easiest) | Easiest — one file to edit, one command to run |
| [Native Firewalla (systemd)](#option-b--native-firewalla-systemd) | VPN appears in the Firewalla app; survives reboots automatically |
| [Manual script](#option-c--manual-script) | Testing or custom setups |

---

## Option A — Docker (easiest)

A pre-built multi-arch image (`amd64` / `arm64` / `armv7`) is published to GitHub Container Registry automatically on every push to `main`. You only need the compose file — no repo clone, no build step.

### 1. Download the compose file

```bash
mkdir pia-wg && cd pia-wg
curl -fsSL https://raw.githubusercontent.com/MaximumWorf/firewalla-pia_wg/main/docker-compose.yml \
  -o docker-compose.yml
```

### 2. Edit it — fill in your credentials

Open `docker-compose.yml` and set `PIA_USER` and `PIA_PASS` (and `DIP_TOKEN` if you have a Dedicated IP):

```yaml
environment:
  PIA_USER: "p1234567"        # ← your PIA username
  PIA_PASS: "supersecret"     # ← your PIA password
  DIP_TOKEN: ""               # ← leave blank for standard account
  PIA_REGION: "us_east"       # ← ignored when DIP_TOKEN is set
```

### 3. Start

```bash
docker compose up -d
docker compose logs -f
```

The container pulls the image, authenticates with PIA, selects the fastest server in the region, and brings up the WireGuard tunnel. The watchdog then runs forever inside the container.

### Web UI

Once the container is running, open **`http://<firewalla-ip>:8080`** in any browser for a dashboard that shows:

- Tunnel status (up/down, last handshake, token TTL, key refresh countdown)
- **Generate Config for App** — registers a fresh key and shows the wg-quick block to paste into the Firewalla app
- **Reconnect** button — triggers an immediate key refresh
- **Settings** editor — saves to `/data/pia-wg/.env`; restart the container to apply
- **Logs** — tailing the live container log

To disable the web UI, set `WEB_PORT: "0"` in `docker-compose.yml`.

> **Security note:** The web UI has no authentication. It is accessible to any device on your LAN but is **not** exposed to the internet — Firewalla's firewall blocks unsolicited inbound connections from the WAN by default. Do not set up a port forward for port 8080. The Settings page can read and write your PIA credentials, so treat access to this port the same as SSH access to the Firewalla.

### Useful commands

```bash
# Check tunnel health, token TTL, and server info
docker compose exec pia-wg /app/pia-wg-firewalla.sh status

# Force an immediate reconnect with a fresh token
docker compose exec pia-wg /app/pia-wg-firewalla.sh reconnect

# See all available PIA regions
docker compose exec pia-wg /app/pia-wg-firewalla.sh list-regions

# Follow live logs
docker compose logs -f --tail 50

# Update to the latest image
docker compose pull && docker compose up -d
```

### Full docker-compose.yml examples

#### Standard account (Firewalla app-integration mode)

```yaml
version: "3.9"

services:
  pia-wg:
    image: ghcr.io/maximumworf/firewalla-pia_wg:latest
    container_name: pia-wg
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - pia-wg-data:/data/pia-wg
      - /home/pi/.firewalla/run/wg_profile:/home/pi/.firewalla/run/wg_profile
      - /media/home-rw/overlay/pi/.firewalla/run/wg_profile:/media/home-rw/overlay/pi/.firewalla/run/wg_profile
    environment:
      PIA_USER: "p1234567"
      PIA_PASS: "supersecret"
      PIA_REGION: "us_east"
      FIREWALLA_PROFILE_ID: "ABC12_ABC12F"  # set after pasting config into Firewalla app
      WG_MANAGED_BY_FIREWALLA: "true"
      WEB_PORT: "8080"
      DATA_DIR: "/data/pia-wg"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  pia-wg-data:
```

#### Dedicated IP account (Firewalla app-integration mode)

`DIP_TOKEN` is the token string from your PIA account dashboard. `PIA_REGION` is ignored when a DIP token is set — the server is fixed by PIA.

```yaml
version: "3.9"

services:
  pia-wg:
    image: ghcr.io/maximumworf/firewalla-pia_wg:latest
    container_name: pia-wg
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - pia-wg-data:/data/pia-wg
      - /home/pi/.firewalla/run/wg_profile:/home/pi/.firewalla/run/wg_profile
      - /media/home-rw/overlay/pi/.firewalla/run/wg_profile:/media/home-rw/overlay/pi/.firewalla/run/wg_profile
    environment:
      PIA_USER: "p1234567"
      PIA_PASS: "supersecret"
      DIP_TOKEN: "pia_dip_abc123xyz..."    # from PIA account dashboard
      FIREWALLA_PROFILE_ID: "ABC12_ABC12F" # set after pasting config into Firewalla app
      WG_MANAGED_BY_FIREWALLA: "true"
      WEB_PORT: "8080"
      DATA_DIR: "/data/pia-wg"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  pia-wg-data:
```

> **Security note:** `docker-compose.yml` will contain your PIA password. Don't commit it to a public repository — add it to `.gitignore` if your working directory is a git repo.

---

## Option B — Native Firewalla (systemd)

This puts the VPN under Firewalla's own WireGuard subsystem so the profile appears in the Firewalla app under **VPN Client → WireGuard**.

```bash
# SSH into your Firewalla
ssh pi@firewalla.local

# One-command installer (prompts for credentials, installs systemd service)
curl -fsSL https://raw.githubusercontent.com/MaximumWorf/firewalla-pia_wg/main/install.sh \
  | sudo bash
```

The installer:
1. Installs `wireguard-tools`, `curl`, and `jq` if missing
2. Prompts for your PIA username, password, region, and optional DIP token
3. Registers and starts a systemd service that runs on every boot

After install, activate the VPN once in the **Firewalla app → VPN Client → WireGuard → PIA_WG → Enable**. From that point the watchdog keeps the tunnel alive automatically.

```bash
# Service management
sudo systemctl status  pia-wg
sudo journalctl -u pia-wg -f
sudo systemctl restart pia-wg

# Manual commands
sudo /home/pi/pia-wg/pia-wg-firewalla.sh status
sudo /home/pi/pia-wg/pia-wg-firewalla.sh reconnect
sudo /home/pi/pia-wg/pia-wg-firewalla.sh list-regions
```

---

## Option C — Manual script

```bash
git clone https://github.com/MaximumWorf/firewalla-pia_wg
cd firewalla-pia_wg

cp .env.example .env
nano .env   # set PIA_USER, PIA_PASS, and optionally DIP_TOKEN

chmod +x pia-wg-firewalla.sh
sudo ./pia-wg-firewalla.sh setup   # one-time: register key, write configs
sudo ./pia-wg-firewalla.sh start   # setup + watchdog (runs in foreground)
```

---

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `PIA_USER` | — | PIA username (e.g. `p1234567`) **required** |
| `PIA_PASS` | — | PIA password **required** |
| `DIP_TOKEN` | *(blank)* | Dedicated IP token from your PIA account; blank = standard shared-IP account |
| `DIP_HOSTNAME` | *(blank)* | Manual server override — only needed if the automatic API lookup fails |
| `DIP_SERVER_IP` | *(blank)* | Manual server IP override — only needed if the automatic API lookup fails |
| `DIP_PORT` | `1337` | WireGuard port for Dedicated IP connections |
| `PIA_REGION` | `us_east` | Server region; ignored when `DIP_TOKEN` is set |
| `FIREWALLA_PROFILE_ID` | *(blank)* | Hash-based profile ID assigned by Firewalla (e.g. `ABC12_ABC12F`); set after pasting the config into the app |
| `WG_MANAGED_BY_FIREWALLA` | `true` | `true` = Firewalla owns the interface (recommended); `false` = script uses wg-quick directly |
| `PROFILE_NAME` | `PIA_WG` | Legacy fallback profile name; only used when `FIREWALLA_PROFILE_ID` is blank |
| `WG_DNS_OVERRIDE` | *(blank)* | Override DNS (e.g. `1.1.1.1,1.0.0.1`); blank uses PIA's servers |
| `WEB_PORT` | `8080` | Port for the web UI dashboard; set to `0` to disable |
| `WATCHDOG_INTERVAL` | `60` | Seconds between watchdog health checks |
| `HANDSHAKE_MAX_AGE` | `120` | Stale handshake threshold in seconds |
| `MAX_DOWN_TIME` | `300` | Seconds of continuous downtime before reconnecting |
| `MAX_RECONNECT_ATTEMPTS` | `5` | Reconnect attempts before a 5-minute back-off pause |
| `KEY_REFRESH_INTERVAL` | `150` | Seconds between PIA key re-registrations when interface is managed by Firewalla |
| `VPN_CHECK_IP` | `9.9.9.9` | IP to ping through the tunnel for connectivity checks (standalone mode only) |
| `DATA_DIR` | `/data/pia-wg` | State directory (keys, token, server list cache) |

---

## Script commands

```
./pia-wg-firewalla.sh <command> [options]

Commands:
  start            Setup + run watchdog (use for Docker / systemd)
  generate-config  Register a key with PIA and print the wg-quick config
                   block to paste into the Firewalla app (first-time setup)
  setup            One-time setup only
  reconnect        Force fresh token + reconnect immediately
  watchdog         Run watchdog loop only (VPN must already be active)
  status           Show tunnel health, handshake age, token TTL, server info
  list-regions     List all available PIA WireGuard regions

Options:
  --new-keys     Regenerate WireGuard keypair
  --new-token    Force PIA token refresh
  --region R     Override PIA_REGION for this run
  --profile N    Override PROFILE_NAME for this run
```

---

## How it works

```
pia-wg-firewalla.sh start
│
├─ 1. Generate or reuse WireGuard keypair      →  /data/pia-wg/private.key
├─ 2. Authenticate with PIA API                →  token cached for 20 h
├─ 3a. Standard: fetch server list, ping all servers, pick fastest
│   3b. Dedicated IP: query PIA DIP API for assigned server
├─ 4. Register WireGuard pubkey with PIA server
├─ 5a. FIREWALLA_PROFILE_ID set:
│       Update the app-created profile files in place:
│         <ID>.conf / <ID>.json / <ID>.settings / <ID>.endpoint_routes
│       If interface is up: hot-reload (ip addr + bypass route + wg syncconf)
│   5b. FIREWALLA_PROFILE_ID blank:
│       Log first-time setup instructions and wait
│
└─ Watchdog loop (runs forever)
     every 60 s:
       ├─ interface down (Firewalla mode)?
       │    key age > 150 s → re-register key so it's fresh when user connects
       ├─ handshake age < 120 s?  ──── yes ──► healthy, reset down_time
       └─ no / stale              ──────────► down_time += 60
            at 300 s total:
              force new PIA token + reconnect
              exponential back-off on repeated failure (2 s, 4 s, 8 s … 120 s)
              after 5 failures: pause 5 min, then reset
```

### Firewalla profile files

When `FIREWALLA_PROFILE_ID` is set, the container updates the four files Firewalla created in `/home/pi/.firewalla/run/wg_profile/` on every key refresh:

| File | Purpose |
|---|---|
| `<ID>.conf` | wg-quick format config with `Address =` — Firewalla uses this to bring up the tunnel and assign the interface IP |
| `<ID>.json` | Peer metadata: public key, endpoint, allowed IPs, addresses |
| `<ID>.settings` | Routing policy including `serverDDNS` (endpoint bypass route) and `serverVPNPort` |
| `<ID>.endpoint_routes` | Static host route ensuring handshake packets reach the PIA server outside the tunnel |

### Token and key refresh

PIA tokens last ~24 hours; WireGuard key registrations expire if no handshake arrives within ~3 minutes. The container handles both:
- **Key registration** is refreshed every 150 s while the interface is down, so it's always fresh when Firewalla connects
- **Token refresh** is forced when the watchdog triggers a reconnect after `MAX_DOWN_TIME` of continuous downtime

---

## Troubleshooting

**`Operation not permitted` when bringing up WireGuard**
The process needs `NET_ADMIN`. In Docker, verify `cap_add: [NET_ADMIN]` is present. When running natively, use `sudo`.

**`Key registration failed (status=unauthorized)`**
Wrong credentials, or the cached token expired mid-setup. Run:
```bash
docker compose exec pia-wg /app/pia-wg-firewalla.sh reconnect
# or natively:
sudo ./pia-wg-firewalla.sh reconnect --new-token
```

**`FIREWALLA_PROFILE_ID is not set` in logs / VPN not starting**
Follow the first-time setup flow: open the web UI → **Generate Config for App** → paste into Firewalla app (VPN Client → Add VPN → WireGuard) → **enable the VPN once** in the app → run `ls -t ~/.firewalla/run/wg_profile/*.conf | head -1` to find the profile ID → set `FIREWALLA_PROFILE_ID` in `docker-compose.yml` → `docker compose up -d`.

**Handshake never completes**
UDP port 1337 may be blocked by your ISP or upstream router. Try a different region:
```bash
docker compose exec pia-wg /app/pia-wg-firewalla.sh reconnect --region us_west
```

**Dedicated IP token rejected**
`DIP_TOKEN` is the token string from your PIA account — it's separate from your password. `PIA_USER` and `PIA_PASS` are still required alongside it for the initial authentication step.

---

## Credits

- [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections) — official PIA API and Dedicated IP auth reference
- [triffid/pia-wg](https://github.com/triffid/pia-wg) — token caching and multi-tier auth fallback approach
- [JasonMeudt/Firewalla-pia-wireguard](https://github.com/JasonMeudt/Firewalla-pia-wireguard) — Firewalla profile file format and watchdog design
