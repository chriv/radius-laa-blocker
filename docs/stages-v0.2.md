# v0.2 Implementation Stages

Each stage is self-contained and validates before the next begins. Stages are sequential
unless noted otherwise.

---

## Stage 1 — Security Foundation: `.gitignore` + repo cleanup ✅

**Why first:** Everything else generates sensitive artifacts. The gitignore must be right
before any secrets or build output touches the working tree.

- Update `.gitignore` with comprehensive ruleset (build artifacts, host env files, certs,
  Python artifacts)
- Untrack `host-a-primary/` and `host-b-secondary/` from git — preserve on disk so the
  production docker-compose container keeps running
- Validate: `git status` shows old folders gone from tracking; `ls` confirms files still on disk

---

## Stage 2 — Repo Restructure: scaffold new layout

**Why second:** Everything downstream (scripts, templates, tests) depends on the directory
structure being in place.

- Create `template/config/`, `hosts/host-1/`, `hosts/host-2/`, `scripts/`, `tests/`, `docs/`
- Create `defaults.env` with all `RADIUS_LAA_BLOCKER_*` variables and safe defaults
- Create `hosts.ini` in INI format (inventory: deploy_method, arch, environment per host)
- Create stub `hosts/<host>/.env.example` files for both hosts (all keys, no secrets)
- Move existing FreeRADIUS config into `template/` as `.tmpl` files with variable placeholders
- Delete old `host-a-primary/` and `host-b-secondary/` trees from git (already done in Stage 1;
  this stage creates the replacement structure)
- Update `CLAUDE.md` to reflect new structure
- Validate: tree looks correct, no secrets committed

---

## Stage 3 — Architecture Detection + Build Script

**Why third:** Templates need substitution logic validated before deploy scripts consume them.

- `scripts/detect-arch.sh`: runs `uname -m` (or uses `RADIUS_LAA_BLOCKER_TARGET_ARCH` override);
  exports `BASE_IMAGE` and `FREERADIUS_CONFIG_PATH`

  | Arch | Base image | Config path |
  |------|-----------|-------------|
  | `aarch64` / `arm64` | `debian:bookworm-slim` + apt `freeradius` | `/etc/freeradius/3.0/` |
  | `x86_64` / `amd64` | `freeradius/freeradius-server:latest` | `/etc/freeradius/` |

- `template/Dockerfile.debian.tmpl` (aarch64 path)
- `template/Dockerfile.freeradius.tmpl` (amd64 path)
- `template/captain-definition.tmpl`
- `template/docker-compose.yml.tmpl`
- `scripts/build.sh <host>`:
  1. Load `defaults.env`, overlay `hosts/<host>/.env`
  2. Call `detect-arch.sh` → set `BASE_IMAGE`, `FREERADIUS_CONFIG_PATH`
  3. `envsubst` all `.tmpl` files → `build/<host>/`
  4. No local `docker build` (CapRover builds on server; Compose volume-mounts)
- Validate: run `build.sh host-1` on the Mac mini; inspect `build/host-1/` for correct
  substitutions; confirm `build/` is gitignored

---

## Stage 4 — Deploy Scripts + Makefile

**Why fourth:** Once build produces correct artifacts, wire up deployment end-to-end.

- `scripts/deploy-caprover.sh <host>`:
  1. Load merged env
  2. Push all `RADIUS_LAA_BLOCKER_*` vars to CapRover app via REST API (token from `.env`)
  3. Set "Do not expose as web-app" via API
  4. `tar -czf deployments/<host>.tar.gz -C build/<host> .`
  5. `caprover deploy --appName $APP --tarFile deployments/<host>.tar.gz`

- `scripts/deploy-compose.sh <host>`:
  1. Load merged env
  2. `rsync build/<host>/ <ssh-target>:<remote-path>/`
  3. `ssh <target> "cd <remote-path> && docker compose up -d"`
  SSH target (hostname/user/path) comes from host `.env`

- `scripts/deploy.sh <host>`: reads `RADIUS_LAA_BLOCKER_DEPLOY_METHOD`, dispatches

- `Makefile` targets:
  ```
  build HOST=      → scripts/build.sh $(HOST)
  deploy HOST=     → scripts/deploy.sh $(HOST)
  test-server      → start long-running test container
  test             → run test suite against running test-server
  test-all         → test-server + test + teardown
  ```

- Validate: deploy to both hosts (production `radius_laa_blocker` and dev
  `radius_laa_blocker_dev` CapRover apps); confirm RADIUS MAC auth works on both SSIDs

---

## Stage 5 — Integration Tests

**Why fifth:** Deployment must be working before tests can run against it.

- `tests/requirements.txt`: `pyrad` (Python RADIUS library — sends `Access-Request` packets,
  returns parsed `Access-Accept` / `Access-Reject`; preferred over `radtest` CLI for
  programmatic assertions)
- `tests/.gitignore`: `.venv/`, `__pycache__/`
- `tests/test_laa_blocking.py` test matrix:
  - Each LAA second-nibble value (`2`, `6`, `a`, `A`, `e`, `E`) → `Access-Reject`
  - Same MACs in all three common formats (colon `aa:bb:...`, dash `AA-BB-...`,
    bare `aabbcc...`) → `Access-Reject`
  - Valid OUI MACs (multiple samples) → `Access-Accept`
  - Boundary cases (e.g., `02:...`, `f2:...`) confirming the locally-administered bit,
    not just specific nibble values
- `make test-server`: starts a long-running container from a known-good test build; leaves it
  running for repeated `make test` runs. Re-run `test-server` to restart with updated config.
- Validate: `make test-all` passes green

---

## Stage 6 — Syslog Support

**Why sixth:** Purely additive; no structural dependencies. Safe after everything else validates.

- If `RADIUS_LAA_BLOCKER_SYSLOG_HOST` is non-empty, generated `docker-compose.yml` includes:
  ```yaml
  logging:
    driver: syslog
    options:
      syslog-address: "udp://${RADIUS_LAA_BLOCKER_SYSLOG_HOST}:${RADIUS_LAA_BLOCKER_SYSLOG_PORT}"
  ```
- Equivalent config for CapRover deployments
- If variable is empty, no logging block is emitted
- Validate: test with and without `RADIUS_LAA_BLOCKER_SYSLOG_HOST` set; confirm no syslog
  block appears in generated output when unset

---

## Stage 7 — Documentation

**Why last:** README and CLAUDE.md should reflect the finished implementation, not the plan.

- **README rewrite** (vendor-agnostic):
  - Purpose section: L2 MAC randomization as a false security measure; DHCP exhaustion
    prevention as a secondary benefit
  - Architecture section for multi-host model
  - Variable reference table: all `RADIUS_LAA_BLOCKER_*` vars, types, defaults, required/optional
  - `hosts.ini` format explanation
  - "Tested With" section for UniFi specifics
  - **UniFi gotcha:** Hi-Capacity Tuning → Multicast Filtering must be **Off** (not Auto)
    to use RADIUS MAC Auth. Misleading error message ("mDNS is not supported with Dynamic
    VLANs") is a red herring — no Dynamic VLANs are involved. This cost significant
    debugging time.
- **CLAUDE.md**: updated throughout to reflect new structure, variable names, config paths,
  and deployment model
