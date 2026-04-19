# Project: UniFi LAA (Randomized MAC) Blocker with Physically Distributed Fail-Open RADIUS

## Objective
Design a highly available, physically distributed MAC Authentication Bypass (MAB) RADIUS solution for a UniFi wireless network (WPA2/3 Personal + MAC Auth). 

The system will reject clients using Locally Administered Addresses (Randomized MACs) at the 802.11 association phase to prevent DHCP pool exhaustion. To guarantee network availability, the stack is split across two separate physical hosts, both utilizing standard RADIUS ports.

## Architecture & Deployment Strategy
The deployment requires two separate `freeradius/freeradius-server` Docker configurations for two distinct host machines:

1. **Host A: Primary RADIUS Blocker**
   - **Role:** The primary gatekeeper.
   - **Port:** UDP `1812`.
   - **Logic:** Inspects the `User-Name` attribute. Rejects LAA MACs using regex. Accepts universally administered MACs.

2. **Host B: Secondary Fail-Open RADIUS**
   - **Role:** Disaster recovery fallback. UniFi only queries this if Host A is offline.
   - **Port:** UDP `1812`.
   - **Logic:** A dummy server that blindly sets `Auth-Type := Accept` for *all* requests.

## Technical Requirements

### 1. UniFi Environmental Assumptions
- **MAC Format:** UniFi sends the MAC address in the `User-Name` and `Calling-Station-Id` attributes as a continuous 12-character hex string (e.g., `AABBCCDDEEFF`).
- **RADIUS Clients:** `clients.conf` on both servers must accept requests from any internal IP (`0.0.0.0/0` or `10.0.0.0/8`) with a shared secret.

### 2. Primary Blocker Logic (Host A)
- Use FreeRADIUS `unlang` in the `sites-available/default` authorize section.
- **LAA Detection Regex:** `^.[26aeAE].*` (Matches if the second character dictates a locally administered address).
- **Action:** If matched, return `reject` with Reply-Message: "Randomized MAC Rejected". Otherwise, set `Auth-Type := Accept`.

### 3. Secondary Fail-Open Logic (Host B)
- Use FreeRADIUS `unlang` in the `sites-available/default` authorize section.
- **Action:** Blindly set `Auth-Type := Accept` for all requests.

## Required Outputs
Please generate the complete file structures and raw code for *both* deployments:

### For Host A (Primary)
1. Running CapRover on a Docker swarm. Will need to use a simple CapRover deployment method for a container (with persistent storage).
2. The custom `unlang` block for the `default` site containing the regex rejection logic.
3. The `clients.conf` block.

### For Host B (Secondary)
4. `docker-compose.yml` mapping UDP `1812:1812`.
5. The custom `unlang` block for the `default` site containing the blind accept logic.
6. The `clients.conf` block.

### UniFi Configuration
7. A brief guide on configuring the UniFi Controller's RADIUS profile, detailing how to enter Host A's IP as the Primary Server and Host B's IP as the Secondary Server, both on port 1812.