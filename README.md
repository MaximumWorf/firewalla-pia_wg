# PIA WireGuard for Firewalla

A self-contained WireGuard VPN manager for [Firewalla](https://firewalla.com) that connects to [Private Internet Access (PIA)](https://www.privateinternetaccess.com). Supports **standard accounts** and **Dedicated IP**, with automatic **token refresh** and an always-on **watchdog** that reconnects the tunnel if it ever drops.

---

## Features

| | |
|---|---|
| **Standard & Dedicated IP** | Full support for PIA Dedicated IP tokens |
| **Auto token refresh** | PIA tokens expire after ~24 h — the watchdog detects this and re-authenticates transparently |
| **Always-on watchdog** | Checks handshake age and pings through the tunnel; reconnects with exponential back-off |
| **Firewalla native** | Writes `.conf` / `.json` / `.settings` profile files that appear in the Firewalla VPN Client UI |
| **Docker — no clone needed** | Pull a pre-built image, fill in two fields, run |
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

A multi-arch image (`amd64` / `arm64` / `armv7`) is published automatically to GitHub Container Registry. You only need the compose file — no repo clone, no build step.

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

#### Standard account

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
    environment:
      PIA_USER: "p1234567"
      PIA_PASS: "supersecret"
      DIP_TOKEN: ""
      PIA_REGION: "us_east"
      PROFILE_NAME: "PIA_WG"
      WG_MANAGED_BY_FIREWALLA: "false"
      WG_DNS_OVERRIDE: ""
      WATCHDOG_INTERVAL: "60"
      HANDSHAKE_MAX_AGE: "120"
      MAX_DOWN_TIME: "300"
      MAX_RECONNECT_ATTEMPTS: "5"
      VPN_CHECK_IP: "9.9.9.9"
      DATA_DIR: "/data/pia-wg"
    healthcheck:
      test: ["CMD", "sh", "-c", "ip link show $${PROFILE_NAME:-PIA_WG} | grep -q UP"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0

volumes:
  pia-wg-data:
```

#### Dedicated IP account

The only difference is `DIP_TOKEN` is set and `PIA_REGION` is ignored — the server is fixed by PIA based on which dedicated IP you purchased.

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
    environment:
      PIA_USER: "p1234567"
      PIA_PASS: "supersecret"
      DIP_TOKEN: "pia_dip_abc123xyz..."   # from PIA account dashboard
      PIA_REGION: ""                       # ignored when DIP_TOKEN is set
      PROFILE_NAME: "PIA_DIP"
      WG_MANAGED_BY_FIREWALLA: "false"
      WG_DNS_OVERRIDE: ""
      WATCHDOG_INTERVAL: "60"
      HANDSHAKE_MAX_AGE: "120"
      MAX_DOWN_TIME: "300"
      MAX_RECONNECT_ATTEMPTS: "5"
      VPN_CHECK_IP: "9.9.9.9"
      DATA_DIR: "/data/pia-wg"
    healthcheck:
      test: ["CMD", "sh", "-c", "ip link show $${PROFILE_NAME:-PIA_DIP} | grep -q UP"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0

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
| `DIP_TOKEN` | *(blank)* | Dedicated IP token from PIA dashboard; blank = standard account |
| `PIA_REGION` | `us_east` | Server region; ignored when `DIP_TOKEN` is set |
| `PROFILE_NAME` | `PIA_WG` | WireGuard interface name and Firewalla profile name (max 15 chars) |
| `WG_MANAGED_BY_FIREWALLA` | `false` | `true` = Firewalla owns the interface; `false` = script uses wg-quick |
| `WG_DNS_OVERRIDE` | *(blank)* | Override DNS (e.g. `1.1.1.1,1.0.0.1`); blank uses PIA's servers |
| `WATCHDOG_INTERVAL` | `60` | Seconds between watchdog health checks |
| `HANDSHAKE_MAX_AGE` | `120` | Stale handshake threshold in seconds |
| `MAX_DOWN_TIME` | `300` | Seconds of continuous downtime before reconnecting |
| `MAX_RECONNECT_ATTEMPTS` | `5` | Reconnect attempts before a 5-minute back-off pause |
| `VPN_CHECK_IP` | `9.9.9.9` | IP to ping through the tunnel for connectivity checks |
| `DATA_DIR` | `/data/pia-wg` | State directory (keys, token, server list cache) |

---

## Script commands

```
./pia-wg-firewalla.sh <command> [options]

Commands:
  start          Setup + run watchdog (use for Docker / systemd)
  setup          One-time setup only
  reconnect      Force fresh token + reconnect immediately
  watchdog       Run watchdog loop only (VPN must already be active)
  status         Show tunnel health, handshake age, token TTL, server info
  list-regions   List all available PIA WireGuard regions

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
├─ 1. Generate or reuse WireGuard keypair  →  /data/pia-wg/private.key
├─ 2. Authenticate with PIA API            →  token cached for 20 h
├─ 3a. Standard: fetch server list, ping all servers, pick fastest
│   3b. Dedicated IP: query PIA DIP API for assigned server
├─ 4. Register WireGuard pubkey with server
├─ 5. Write Firewalla profile files:
│       PIA_WG.conf  /  PIA_WG.json  /  PIA_WG.settings
│       → deployed to /home/pi/.firewalla/run/wg_profile/
├─ 6. wg-quick up  (standalone)  /  wg syncconf  (Firewalla mode)
│
└─ Watchdog loop (runs forever)
     every 60 s:
       ├─ handshake age < 120 s?  ──── yes ──► ping 9.9.9.9 through tunnel
       │                                            OK → reset down_time
       │                                            FAIL → down_time += 60
       └─ no / stale              ──────────► down_time += 60
            at 300 s total:
              force new PIA token + reconnect
              exponential back-off on repeated failure (2 s, 4 s, 8 s … 120 s)
              after 5 failures: pause 5 min, then reset
```

### Firewalla profile files

Three files are written per profile and deployed to `/home/pi/.firewalla/run/wg_profile/`:

| File | Purpose |
|---|---|
| `PIA_WG.conf` | wg-quick format config — Firewalla reads this to bring up the tunnel |
| `PIA_WG.json` | Firewalla peer metadata: public key, endpoint, allowed IPs, addresses |
| `PIA_WG.settings` | Routing policy: `overrideDefaultRoute`, `routeDNS`, `strictVPN` |

### Token refresh

PIA tokens last ~24 hours. The watchdog accumulates downtime and, once `MAX_DOWN_TIME` is reached, forces a fresh token and re-registers the WireGuard key before reconnecting — no manual intervention needed.

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

**Profile not appearing in the Firewalla app**
Check that the three profile files exist in `/home/pi/.firewalla/run/wg_profile/`. In Docker, the Firewalla volume mounts in `docker-compose.yml` must be uncommented and `WG_MANAGED_BY_FIREWALLA` set to `true`.

**Handshake never completes**
UDP port 1337 may be blocked by your ISP or upstream router. Try a different region:
```bash
docker compose exec pia-wg /app/pia-wg-firewalla.sh reconnect --region us_west
```

**Dedicated IP token rejected**
`DIP_TOKEN` is the token string from the PIA dashboard — it's separate from your password. `PIA_USER` and `PIA_PASS` are still required alongside it for the initial authentication step.

---

## Credits

- [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections) — official PIA API and Dedicated IP auth reference
- [triffid/pia-wg](https://github.com/triffid/pia-wg) — token caching and multi-tier auth fallback approach
- [JasonMeudt/Firewalla-pia-wireguard](https://github.com/JasonMeudt/Firewalla-pia-wireguard) — Firewalla profile file format and watchdog design
