# radius-laa-blocker

> **⚠️ Status: Pre-release / Experimental** — Host B (secondary fail-open) is operational. Host A (primary LAA blocker) pending deployment.

---

FreeRADIUS-based MAC Authentication Bypass (MAB) solution for UniFi wireless networks. Rejects clients using Locally Administered Addresses (randomized/private MACs) at the 802.11 association phase, preventing DHCP pool exhaustion from MAC randomization on non-guest SSIDs.

## How it works

When a client connects to a WPA2/3 Personal SSID with RADIUS MAC Authentication enabled, the UniFi AP fires a RADIUS `Access-Request` with the client's MAC address as `User-Name` before granting network access. The primary server (Host A) inspects the second character of the MAC — if it indicates the locally administered bit is set, the client is rejected. If Host A is unreachable, UniFi falls over to the secondary server (Host B), which accepts everything, keeping the network available.

| Host | Role | Deployment |
|------|------|------------|
| Host A | Primary — rejects randomized MACs | CapRover (Dockerfile baked image) |
| Host B | Secondary fail-open — accepts all | docker-compose |

## Prerequisites

- Both hosts must be reachable from the UniFi controller on **UDP port 1812**
- Host A: CapRover instance running on the host
- Host B: Docker and Docker Compose installed on the host
- A strong shared secret (any long random string) ready to use

## First-time setup (both hosts)

Each host has a `clients.conf.example` template. You must create the real file from it before deploying:

```bash
# Host A
cp host-a-primary/config/clients.conf.example host-a-primary/config/clients.conf

# Host B
cp host-b-secondary/config/clients.conf.example host-b-secondary/config/clients.conf
```

Then edit **both** `clients.conf` files and replace `CHANGE_ME_SHARED_SECRET` with the same strong secret. The `clients.conf` files are gitignored and will never be committed.

**Note on `ipaddr`:** Host B runs under docker-compose, so all requests arrive from the Docker bridge NAT gateway rather than the real controller IP. `0.0.0.0/0` is intentional — the shared secret is the real auth barrier. On Host A (CapRover/Docker Swarm), the same applies. If you run either host natively (not in Docker), you can restrict `ipaddr` to your controller's subnet.

---

## Host B — Secondary (deploy first, simpler)

```bash
cd host-b-secondary
docker compose up -d
```

To verify it's running:
```bash
docker compose ps
# FreeRADIUS logs to a file inside the container, not stdout.
# To watch auth events (accepts/rejects):
docker exec host-b-secondary-freeradius-1 tail -f /var/log/freeradius/radius.log
```

To apply config changes later (no rebuild needed — config is volume-mounted):
```bash
docker compose restart
```

---

## Host A — Primary (CapRover)

Config is baked into the Docker image at build time. Changes to config files require a redeploy.

### 1. Create the CapRover app

In the CapRover web UI:
1. Apps → Create New App → name it (e.g. `radius-blocker`)
2. App Configs → **Ports** → add port mapping: `1812` → `1812`, protocol **UDP**
3. Save

### 2. Package and deploy

Using the CapRover CLI (install once with `npm install -g caprover`):

```bash
cd host-a-primary
tar -czf ../deploy-host-a.tar.gz .
caprover deploy -t ../deploy-host-a.tar.gz -a radius-blocker
```

Or via the CapRover web UI: Apps → [your app] → Deployment → upload the tar.gz.

> **Important:** The tar.gz must contain `captain-definition` and `Dockerfile` at its root — achieved by running `tar` from *inside* `host-a-primary/`, as shown above.

### 3. Verify

CapRover app logs (UI → Apps → [your app] → Logs) will show FreeRADIUS startup — look for `Ready to process requests`. Note that FreeRADIUS writes auth events (accepts/rejects) to a file inside the container, not stdout, so they won't appear in the CapRover log UI. To watch live auth events, exec into the container:

```bash
docker exec <container_id> tail -f /var/log/freeradius/radius.log
```

---

## UniFi RADIUS profile setup

1. UniFi Network → Settings → Profiles → RADIUS → **Create New**
2. Set:
   - **Primary Server:** Host A IP address, port `1812`, shared secret
   - **Secondary Server:** Host B IP address, port `1812`, same shared secret
3. Save the profile
4. For each non-guest SSID you want to protect:
   - Settings → WiFi → [SSID] → Advanced
   - Enable **RADIUS MAC Authentication**
   - Select the profile you just created
   - Choose a **MAC Address Format** (any format works — the regex is format-agnostic; lowercase with colons `aa:bb:cc:dd:ee:ff` is the default)

Do **not** apply this profile to the guest SSID — randomized MACs are intentionally allowed there.

---

## Verifying the filter is working

After applying the profile, attempt to connect with a device that has MAC randomization enabled. It should be rejected at association (not just blocked from DHCP — the AP will refuse the connection). Check FreeRADIUS logs for the `User-Name` value and the reject decision:

- Host A: CapRover app logs
- Host B: `docker exec host-b-secondary-freeradius-1 tail -f /var/log/freeradius/radius.log`

A successful reject looks like:
```
Auth: (N) Login incorrect (rlm_policy: Randomized MAC Rejected): [<mac>] ...
```

---

## Failover behavior

UniFi/hostapd retries the primary server several times before falling over to the secondary. This is **sequential failover**, not load balancing. Host B only receives requests when Host A is genuinely unreachable.
