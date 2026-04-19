# v0.2 Refactor Plan

## Repo Structure

```
defaults.env                    ← project-level variable defaults (committed)
hosts.ini                       ← host inventory in INI format (committed)
Makefile                        ← build, deploy, test-server, test targets
template/
  config/
    clients.conf.tmpl
    radiusd.conf.tmpl
    sites-available/default.tmpl
  Dockerfile.debian.tmpl        ← CapRover on aarch64
  Dockerfile.freeradius.tmpl    ← CapRover on amd64
  captain-definition.tmpl       ← CapRover deployment descriptor
  docker-compose.yml.tmpl       ← Compose deployments (volume-mount, no build)
scripts/
  detect-arch.sh
  build.sh <host>               ← envsubst → build/<host>/
  deploy.sh <host>              ← dispatches to caprover or compose
  deploy-caprover.sh <host>     ← tarball → caprover deploy (builds on server)
  deploy-compose.sh <host>      ← rsync build/<host>/ → SSH docker compose up
tests/
  requirements.txt
  .gitignore
  test_laa_blocking.py
hosts/
  host-1/
    .env.example                ← committed, all keys, no secret
    .env                        ← gitignored, operator fills in
  host-2/
    .env.example
    .env
build/                          ← gitignored entirely
deployments/                    ← gitignored entirely
```

## `hosts.ini` (INI format, committed)

```ini
[host-1]
deploy_method = caprover
arch = aarch64
environment = production

[host-2]
deploy_method = caprover
arch = aarch64
environment = development
```

All other per-host values (`RADIUS_LAA_BLOCKER_PORT`, `RADIUS_LAA_BLOCKER_CAPROVER_APP`, etc.) live
in `hosts/<host>/.env`. `hosts.ini` is purely the structural inventory — what scripts iterate over
and how to classify each host.

## Variable System

**`defaults.env`** (committed):
```
RADIUS_LAA_BLOCKER_PORT=1812
RADIUS_LAA_BLOCKER_SYSLOG_HOST=
RADIUS_LAA_BLOCKER_SYSLOG_PORT=514
RADIUS_LAA_BLOCKER_DEPLOY_METHOD=compose
RADIUS_LAA_BLOCKER_TARGET_ARCH=auto
RADIUS_LAA_BLOCKER_CAPROVER_APP=
RADIUS_LAA_BLOCKER_CAPROVER_TOKEN=
```

**`hosts/<host>/.env`** (gitignored, with a committed `.env.example`):
```
RADIUS_LAA_BLOCKER_SECRET=CHANGE_ME
RADIUS_LAA_BLOCKER_PORT=1812
RADIUS_LAA_BLOCKER_DEPLOY_METHOD=caprover
RADIUS_LAA_BLOCKER_CAPROVER_APP=radius_laa_blocker
RADIUS_LAA_BLOCKER_CAPROVER_TOKEN=
RADIUS_LAA_BLOCKER_SYSLOG_HOST=
```

The deploy script merges `defaults.env` then overlays the host `.env`, so only overrides need to be
in the host file.

## Build Process

**`scripts/build.sh <host>`:**
1. Load `defaults.env`, overlay `hosts/<host>/.env`
2. Call `detect-arch.sh` (or use `RADIUS_LAA_BLOCKER_TARGET_ARCH` override) → exports `BASE_IMAGE`,
   `FREERADIUS_CONFIG_PATH`
3. `envsubst` all `.tmpl` files → `build/<host>/`
4. No local `docker build` — CapRover builds on the server; Compose volume-mounts, no build needed

**Two deployment paths, no local `docker build`:**

| Method | What gets built where |
|--------|-----------------------|
| CapRover | tarball sent to CapRover; server runs `docker build` using arch-appropriate Dockerfile |
| Compose | config files rsynced to target host; base image pulled by Docker on the host; no build step |

Compose hosts use volume-mounted config and pull the base image on the target host.
CapRover hosts bake config into the image via the Dockerfile.

## Deploy Process

**CapRover (`deploy-caprover.sh <host>`):**
1. Load merged env
2. Push all `RADIUS_LAA_BLOCKER_*` vars to CapRover app via REST API (token from `.env`)
3. Set "Do not expose as web-app" via API
4. `tar -czf deployments/<host>.tar.gz -C build/<host> .`
5. `caprover deploy --appName $APP --tarFile deployments/<host>.tar.gz`

**Compose (`deploy-compose.sh <host>`):**
1. Load merged env
2. `rsync build/<host>/ <ssh-target>:<remote-path>/`
3. `ssh <target> "cd <remote-path> && docker compose up -d"`

SSH target (hostname/user/path) comes from the host `.env` file for Compose deployments.

## Makefile Targets

```makefile
build HOST=      # build.sh <host>
deploy HOST=     # deploy.sh <host>
test-server      # start long-running test container (generic test build)
test             # run test suite against running test-server
test-all         # test-server + test + teardown
```

`test-server` starts a container from a known-good test build and leaves it running. `test` sends
RADIUS packets against it. Re-running `test-server` restarts the container if config changes are
needed.

## Integration Tests

**`pyrad`** is the right choice: a Python library that sends RADIUS `Access-Request` packets and
returns parsed responses (`Access-Accept` / `Access-Reject`). Allows proper assertions and
parameterization over MAC formats — unlike `radtest` (a CLI tool requiring subprocess wrapping).

**Test matrix:**
- Each LAA second-nibble value (`2`, `6`, `a`, `A`, `e`, `E`) → `Access-Reject`
- Same MACs in all three common formats (colon, dash, no separator) → `Access-Reject`
- Valid OUI MACs (several samples) → `Access-Accept`
- Boundary cases (e.g., `02:...`, `f2:...`) to confirm the bit check, not just nibble values

## Syslog

If `RADIUS_LAA_BLOCKER_SYSLOG_HOST` is non-empty, the generated `docker-compose.yml` includes:
```yaml
logging:
  driver: syslog
  options:
    syslog-address: "udp://${SYSLOG_HOST}:${SYSLOG_PORT}"
```
For CapRover, the equivalent logging config goes into the deployment. If the variable is empty, no
logging block is added.

## Architecture Detection (`scripts/detect-arch.sh`)

Runs `uname -m` (on the build host, or overridden by `RADIUS_LAA_BLOCKER_TARGET_ARCH`):

| Arch | Base image | FreeRADIUS config path |
|------|-----------|----------------------|
| `aarch64` / `arm64` | `debian:bookworm-slim` + apt `freeradius` | `/etc/freeradius/3.0/` |
| `x86_64` / `amd64` | `freeradius/freeradius-server:latest` | `/etc/freeradius/` |

The script exports `BASE_IMAGE` and `FREERADIUS_CONFIG_PATH`, which are substituted into Dockerfile
templates and config templates by `build.sh`.

## All Hosts as Enforcers

Single `template/sites-available/default.tmpl` with LAA blocking logic. No fail-open variant.
Every deployed instance rejects LAA MACs. The fail-open secondary concept is retired.

Rationale: there is no true fail-open in the upstream network infrastructure (UniFi or otherwise).
A non-enforcing secondary only creates false negatives. Deploy N enforcing instances; point the AP
controller at all of them.

## Comprehensive `.gitignore`

```gitignore
# Sensitive host configs — commit only .example versions
hosts/*/.env
hosts/*/*.ini

# All build and deployment artifacts (contain substituted secrets)
build/
deployments/
*.tar
*.tar.gz
*.tgz

# Python
tests/.venv/
**/__pycache__/
**/*.pyc
.pytest_cache/

# Keys and certs
*.pem
*.key
*.crt
*.p12

# macOS
.DS_Store
```

Template files (`.tmpl`) and `.example` files are always committed. The `build/` output (which
contains substituted secrets) is never committed. Tarballs (`deployments/`) are never committed.

## Documentation Goals

- **README:** Vendor-agnostic framing. Purpose section articulating L2 MAC randomization as a false
  security measure (DHCP exhaustion is a secondary concern). UniFi-specific notes in a "Tested With"
  section.
- **UniFi gotcha:** Document the Multicast Filtering trap — "Hi-Capacity Tuning → Multicast
  Filtering must be Off (not Auto)" to use RADIUS MAC Auth. The misleading mDNS/Dynamic VLAN error
  message is a red herring unrelated to the actual problem.
- **Variable reference table:** All `RADIUS_LAA_BLOCKER_*` vars with types, defaults,
  required/optional.
- **CLAUDE.md:** Updated throughout to reflect new structure.
