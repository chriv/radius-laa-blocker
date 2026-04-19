# radius-laa-blocker

> **⚠️ Status: Experimental — considered a failure for the intended use case.**
>
> The premise of this project is that UniFi Network supports RADIUS MAC Authentication alongside WPA2/3 Personal (PSK) SSIDs. In practice, the only path to triggering a RADIUS server in UniFi Network appears to require enabling WPA2/3 **Enterprise**, which forces full 802.1X EAP authentication on clients (certificates, user/password prompts, EAP type configuration, etc.) — defeating the point of a transparent MAC-based filter on a PSK network.
>
> The FreeRADIUS configuration and deployment structures here are architecturally sound and left intact for reference. If a future UniFi firmware version exposes RADIUS MAC Auth on Personal SSIDs independently of Enterprise mode, this project should work as designed. Pull requests with findings welcome.

---

FreeRADIUS-based MAC Authentication Bypass (MAB) solution for UniFi wireless networks. Rejects clients using Locally Administered Addresses (randomized/private MACs) at the 802.11 association phase, preventing DHCP pool exhaustion from MAC randomization on non-guest SSIDs.

## How it works

When a client connects to a WPA2/3 Personal SSID with RADIUS MAC Authentication enabled, the UniFi AP fires a RADIUS `Access-Request` with the client's MAC address as `User-Name` before granting network access. The primary server (Host A) inspects the second character of the MAC — if it indicates the locally administered bit is set, the client is rejected. If Host A is unreachable, UniFi falls over to the secondary server (Host B), which accepts everything, keeping the network available.

| Host | Hardware | Role | Deployment |
|------|----------|------|------------|
| Host A | Raspberry Pi (CapRover) | Primary — rejects randomized MACs | Dockerfile baked image |
| Host B | Mac Mini | Secondary fail-open — accepts all | docker-compose |

## Prerequisites

- Both hosts must be reachable from the UniFi UDR7 on **UDP port 1812**
- Host A: CapRover instance already running on the Pi
- Host B: Docker and Docker Compose installed on the Mac Mini
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

Optionally, also restrict `ipaddr = 0.0.0.0/0` to your management subnet (e.g. `10.0.1.0/24`) once you know which IP the UDR7 sends RADIUS requests from.

---

## Host B — Mac Mini (deploy first, simpler)

```bash
cd host-b-secondary
docker compose up -d
```

To verify it's running:
```bash
docker compose ps
docker compose logs -f
```

To apply config changes later (no rebuild needed — config is volume-mounted):
```bash
docker compose restart
```

---

## Host A — Raspberry Pi (CapRover)

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

Check the app logs in the CapRover UI (Apps → [your app] → Logs). You should see FreeRADIUS start up and report it is ready to process requests.

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
- Host B: `docker compose logs -f` from `host-b-secondary/`

A successful reject looks like:
```
Auth: (N) Login incorrect (rlm_policy: Randomized MAC Rejected): [<mac>] ...
```

---

## Failover behavior

UniFi/hostapd retries the primary server several times before falling over to the secondary. This is **sequential failover**, not load balancing. Host B only receives requests when Host A is genuinely unreachable.
