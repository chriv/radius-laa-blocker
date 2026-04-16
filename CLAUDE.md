# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A FreeRADIUS-based MAC Authentication Bypass (MAB) solution for UniFi wireless networks that rejects clients using Locally Administered Addresses (randomized MACs) at the 802.11 association phase. Prevents DHCP pool exhaustion from randomized MACs on non-guest SSIDs.

## Architecture

Two separate FreeRADIUS deployments across two physical hosts:

| Host | Role | Hardware | Deployment |
|------|------|----------|------------|
| Host A | Primary RADIUS Blocker | Raspberry Pi | CapRover (Docker Swarm) |
| Host B | Secondary Fail-Open | Mac Mini | docker-compose |

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

- **RADIUS clients:** `clients.conf` uses `0.0.0.0/0` or `10.0.0.0/8` with a shared secret
- **MAC format from UniFi:** Configurable per-SSID in UniFi Network (Settings → WiFi → [SSID] → RADIUS MAC Auth → MAC Address Format). Options include `aa:bb:cc:dd:ee:ff` (lowercase colon, the default), `AA-BB-CC-DD-EE-FF` (uppercase dash), and `aabbccddeeff` (no separator). The LAA regex `^.[26aeAE]` is format-agnostic — position 1 is always the second nibble of the first octet regardless of separator style. UniFi sends the MAC in both `User-Name` and `User-Password` (MAB convention), and also in `Calling-Station-Id`.
- **FreeRADIUS version:** `freeradius/freeradius-server` Docker image
- **UniFi RADIUS profile:** Host A = Primary Server, Host B = Secondary Server, both port 1812
- The custom reject/accept logic lives in `sites-available/default` → `authorize` section using `unlang`

## Repository Structure

```
host-a-primary/          ← Deploy to Raspberry Pi via CapRover
  captain-definition     ← Tells CapRover to use the Dockerfile
  Dockerfile             ← Builds freeradius image with config baked in
  config/
    clients.conf
    sites-available/default

host-b-secondary/        ← Deploy to Mac Mini via docker-compose
  docker-compose.yml     ← Mounts config files as read-only volumes
  config/
    clients.conf
    sites-available/default
```

## Deployment Notes

### Before deploying either host
1. Replace `CHANGE_ME_SHARED_SECRET` in **both** `clients.conf` files with the same strong secret. This same value goes into the UniFi RADIUS profile.
2. Optionally restrict `ipaddr = 0.0.0.0/0` in `clients.conf` to your actual management subnet once you know it.

### Host A — Raspberry Pi (CapRover)
- Config is **baked into the Docker image** at build time (via `COPY` in the Dockerfile). To change config: edit files, then redeploy the app in CapRover (triggers a rebuild).
- CapRover expects `captain-definition` and `Dockerfile` at the **root of the deployed archive**. When using `caprover deploy` CLI or uploading a tar.gz via the UI, archive the *contents* of `host-a-primary/`, not the directory itself.
- CapRover app must have UDP port 1812 exposed. In the CapRover UI: App Config → "Ports" → add UDP 1812.
- Enable "Has Persistent Data" only if you later switch to a volume-mount config strategy (not currently needed).

### Host B — Mac Mini (docker-compose)
- Config is **volume-mounted** (not baked in). Edit files in `host-b-secondary/config/` and run `docker compose restart` to apply changes — no rebuild required.
- Run from the `host-b-secondary/` directory: `docker compose up -d`
- To view logs: `docker compose logs -f`

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

### FreeRADIUS config path caveat
Both deployments assume config lives at `/etc/freeradius/3.0/` (standard for the official Debian-based Docker image). If the container fails to start, exec in and run `find /etc -name radiusd.conf` to locate the actual path, then update the Dockerfile COPY paths or docker-compose volume mount paths accordingly.

### Guest SSID
Intentionally excluded from this RADIUS profile — randomized MACs are acceptable on the guest SSID.
