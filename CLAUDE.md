# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A FreeRADIUS-based MAC Authentication Bypass (MAB) solution for UniFi wireless networks that rejects clients using Locally Administered Addresses (randomized MACs) at the 802.11 association phase. Prevents DHCP pool exhaustion from randomized MACs on non-guest SSIDs.

## Architecture

Two separate FreeRADIUS deployments across two physical hosts:

| Host | Role | Deployment |
|------|------|------------|
| Host A | Primary RADIUS Blocker | CapRover (Docker Swarm) |
| Host B | Secondary Fail-Open | docker-compose |

Both listen on UDP `1812`. UniFi queries Host A first; Host B is only queried when Host A is unreachable.

### Host A — Primary Blocker Logic
- Inspects `User-Name` attribute (UniFi sends MAC as 12-char hex, e.g. `AABBCCDDEEFF`)
- LAA detection regex: `^.[26aeAE].*` (second character indicates locally administered bit)
- Rejects LAA MACs with Reply-Message "Randomized MAC Rejected"
- Accepts all universally administered MACs (`Auth-Type := Accept`)

### Host B — Fail-Open Logic
- Blindly sets `Auth-Type := Accept` for all requests
- Pure disaster-recovery fallback; no filtering logic

## Key Configuration Details

- **RADIUS clients:** `clients.conf` uses `ipaddr = 0.0.0.0/0`. On Host B (docker-compose), all requests arrive from the Docker bridge NAT gateway (typically `192.168.65.1`) — the real UniFi IP is never visible to the container. `0.0.0.0/0` is intentional; the shared secret is the real auth barrier. Set `require_message_authenticator = yes` in the client block — UniFi sends it and FreeRADIUS will warn loudly at startup until you do.
- **MAC format from UniFi:** Configurable per-SSID in UniFi Network (Settings → WiFi → [SSID] → RADIUS MAC Auth → MAC Address Format). Options include `aa:bb:cc:dd:ee:ff` (lowercase colon, the default), `AA-BB-CC-DD-EE-FF` (uppercase dash), and `aabbccddeeff` (no separator). The LAA regex `^.[26aeAE]` is format-agnostic — position 1 is always the second nibble of the first octet regardless of separator style. UniFi sends the MAC in both `User-Name` and `User-Password` (MAB convention), and also in `Calling-Station-Id`.
- **FreeRADIUS version:** `freeradius/freeradius-server` Docker image
- **UniFi RADIUS profile:** Host A = Primary Server, Host B = Secondary Server, both port 1812
- The custom reject/accept logic lives in `sites-available/default` → `authorize` section using `unlang`

## Repository Structure

```
host-a-primary/          ← Deploy via CapRover
  captain-definition     ← Tells CapRover to use the Dockerfile
  Dockerfile             ← Builds freeradius image with config baked in
  config/
    clients.conf
    clients.conf.example ← Template (no secret); copy to clients.conf to deploy
    sites-available/default

host-b-secondary/        ← Deploy via docker-compose
  docker-compose.yml     ← Mounts config files as read-only volumes
  config/
    clients.conf
    clients.conf.example ← Template (no secret); copy to clients.conf to deploy
    radiusd.conf         ← Full radiusd.conf with auth logging enabled
    sites-available/default
```

## Deployment Notes

### Before deploying either host
1. Replace `CHANGE_ME_SHARED_SECRET` in **both** `clients.conf` files with the same strong secret. This same value goes into the UniFi RADIUS profile.
2. Optionally restrict `ipaddr = 0.0.0.0/0` in `clients.conf` to your actual management subnet once you know it.

### Host A — Primary (CapRover)
- Config is **baked into the Docker image** at build time (via `COPY` in the Dockerfile). To change config: edit files, then redeploy the app in CapRover (triggers a rebuild).
- CapRover expects `captain-definition` and `Dockerfile` at the **root of the deployed archive**. When using `caprover deploy` CLI or uploading a tar.gz via the UI, archive the *contents* of `host-a-primary/`, not the directory itself.
- CapRover app must have UDP port 1812 exposed. In the CapRover UI: App Config → "Ports" → add UDP 1812.
- Enable "Has Persistent Data" only if you later switch to a volume-mount config strategy (not currently needed).
- FreeRADIUS logs to a file inside the container, **not** to stdout. To view auth events: CapRover UI → App Logs won't show them. Instead exec into the container: `docker exec <container_id> tail -f /var/log/freeradius/radius.log`

### Host B — Secondary (docker-compose)
- Config is **volume-mounted** (not baked in). Edit files in `host-b-secondary/config/` and run `docker compose restart` to apply changes — no rebuild required.
- Run from the `host-b-secondary/` directory: `docker compose up -d`
- FreeRADIUS logs to a file inside the container, **not** to stdout. `docker compose logs -f` will be empty. Instead:
  - Auth log (accept/reject events): `docker exec <container> tail -f /var/log/freeradius/radius.log`
  - Or by name: `docker exec host-b-secondary-freeradius-1 tail -f /var/log/freeradius/radius.log`

### UniFi MAC Address Format setting
In UniFi Network, when you enable RADIUS MAC Authentication on an SSID, a **"MAC Address Format"** dropdown appears. Set it to whatever you prefer — the LAA regex in `sites-available/default` works for all standard formats. Lowercase colon-separated (`aa:bb:cc:dd:ee:ff`) is the default and a reasonable choice. After first deployment, confirm by checking container logs for the `User-Name =` value in incoming Access-Request packets:
- Host A: CapRover app logs (or `docker logs <container>`)
- Host B: `docker compose logs -f`

### UniFi RADIUS Profile Setup
1. UniFi Network → Settings → Profiles → RADIUS → Create New
2. Primary Server: Host A IP, port 1812, shared secret
3. Secondary Server: Host B IP, port 1812, same shared secret
4. Apply this profile to target SSIDs (not the guest SSID — randomized MACs are intentionally allowed there)
5. On each target SSID: Settings → WiFi → [SSID] → Advanced → enable "RADIUS MAC Authentication", select your profile, choose a MAC Address Format

**Failover behavior:** UniFi/hostapd retries the primary server several times before falling over to the secondary. This is sequential failover, not load balancing.

**PPSK note:** PPSK (Private Pre-Shared Keys) and RADIUS MAC Authentication are mutually exclusive on the same SSID. However, UniFi's built-in MAC allow/block lists are independent of RADIUS and *can* be combined with PPSK — so a PPSK SSID with a local MAC allow list is a viable alternative for future SSIDs where per-device PSKs are desirable alongside hardware MAC gating.

### FreeRADIUS config paths — Host A vs Host B differ
The two hosts use different base images and therefore different config paths:

| Host | Base image | Config path |
|------|-----------|-------------|
| Host A | `debian:bookworm-slim` + apt `freeradius` | `/etc/freeradius/3.0/` |
| Host B | `freeradius/freeradius-server:latest` | `/etc/freeradius/` |

Host A uses Debian because the official `freeradius/freeradius-server` Docker image is amd64-only and fails with `exec format error` on arm64 hosts. The Debian apt package (v3.2.1) is native arm64 and works correctly.

### sites-available/default must include listen sections
Our custom `sites-available/default` replaces the built-in one entirely, including its socket bindings. The file **must** contain `listen { type = auth ... }` and `listen { type = acct ... }` blocks or FreeRADIUS will start successfully but silently ignore all incoming packets. See the existing file for the required blocks.

### radiusd.conf version pinning
`host-b-secondary/config/radiusd.conf` is a snapshot extracted from `freeradius/freeradius-server:latest` at the time of setup (v3.2.8), edited only to set `auth = yes` in the `log {}` section. Because it is volume-mounted over the image's built-in file, it will diverge if the image is updated. If the container fails to start after pulling a new image version, this file is the first thing to check — diff it against the new image's default (`docker run --rm freeradius/freeradius-server cat /etc/freeradius/radiusd.conf`) and reconcile any breaking changes.

### Guest SSID
Intentionally excluded from this RADIUS profile — randomized MACs are acceptable on the guest SSID.
