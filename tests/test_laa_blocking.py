"""
Integration tests for LAA (Locally Administered Address) blocking.

Sends real RADIUS Access-Request packets to a running FreeRADIUS container
and asserts Access-Accept or Access-Reject responses.

Run against the dev test server:
    make test-server   # start container
    make test          # run this suite

Environment variables (defaults match host-1-dev):
    RADIUS_HOST    server address (default: 127.0.0.1)
    RADIUS_PORT    UDP port       (default: 18120 from host-1-dev .env)
    RADIUS_SECRET  shared secret  (loaded from host-1-dev .env by conftest.py)
"""

import os
from pathlib import Path

import pytest
from pyrad.client import Client, Timeout
from pyrad import packet
from pyrad.dictionary import Dictionary

RADIUS_HOST = os.environ.get("RADIUS_HOST", "127.0.0.1")
RADIUS_PORT = int(os.environ.get("RADIUS_LAA_BLOCKER_PORT", "18120"))
RADIUS_SECRET = os.environ.get("RADIUS_LAA_BLOCKER_SECRET", "").encode()
DICT_FILE = str(Path(__file__).parent / "dictionary")


def send_mac(mac: str) -> int:
    """Send an Access-Request with the MAC as User-Name. Returns the reply code."""
    client = Client(
        server=RADIUS_HOST,
        authport=RADIUS_PORT,
        secret=RADIUS_SECRET,
        dict=Dictionary(DICT_FILE),
    )
    client.timeout = 5
    req = client.CreateAuthPacket(code=packet.AccessRequest)
    req["User-Name"] = mac
    req["User-Password"] = req.PwCrypt(mac)
    req["NAS-IP-Address"] = "127.0.0.1"
    req["NAS-Port"] = 0
    req.add_message_authenticator()
    reply = client.SendPacket(req)
    return reply.code


# ---------------------------------------------------------------------------
# LAA second-nibble values — bit 1 of first octet set, each must be rejected
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("second_nibble", ["2", "6", "a", "A", "e", "E"])
def test_laa_nibble_rejected(second_nibble):
    """Each second-nibble value that indicates the LAA bit must be rejected."""
    mac = f"a{second_nibble}:bb:cc:dd:ee:ff"
    assert send_mac(mac) == packet.AccessReject, f"Expected reject for LAA MAC {mac}"


# ---------------------------------------------------------------------------
# Same LAA MAC across all three common AP controller MAC formats
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("mac", [
    "a2:bb:cc:dd:ee:ff",  # colon-separated, lowercase (UniFi default)
    "A2:BB:CC:DD:EE:FF",  # colon-separated, uppercase
    "a2-bb-cc-dd-ee-ff",  # dash-separated, lowercase
    "a2bbccddeeff",        # no separator, lowercase
    "A2BBCCDDEEFF",        # no separator, uppercase
])
def test_laa_formats_rejected(mac):
    """LAA MACs must be rejected regardless of separator style."""
    assert send_mac(mac) == packet.AccessReject, f"Expected reject for {mac}"


# ---------------------------------------------------------------------------
# Universally administered (OUI-assigned) MACs — must be accepted
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("mac", [
    "00:50:56:aa:bb:cc",  # VMware OUI        — second char '0'
    "ac:de:48:11:22:33",  # Apple OUI         — second char 'c'
    "f0:18:98:01:02:03",  # Cisco OUI         — second char '0'
    "b8:27:eb:01:02:03",  # Raspberry Pi Foundation — second char '8'
    "dc:a6:32:01:02:03",  # Raspberry Pi Trading   — second char 'c'
    "44:38:39:ff:ef:57",  # Cumulus/NVIDIA OUI — second char '4'
])
def test_universal_mac_accepted(mac):
    """Universally administered MACs must be accepted."""
    assert send_mac(mac) == packet.AccessAccept, f"Expected accept for {mac}"


# ---------------------------------------------------------------------------
# Boundary: first nibble varies, second nibble fixed at '2' (LAA) — all reject
# Confirms the regex tests bit position, not a specific first-nibble value
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("first_nibble", ["0", "1", "5", "8", "9", "f", "F"])
def test_laa_boundary_first_nibble_irrelevant(first_nibble):
    """First nibble must not affect LAA detection — second nibble '2' always rejects."""
    mac = f"{first_nibble}2:bb:cc:dd:ee:ff"
    assert send_mac(mac) == packet.AccessReject, f"Expected reject for {mac}"


# ---------------------------------------------------------------------------
# Boundary: second nibble in {0, 1, 4, 5, 8, 9, c, d} — no LAA bit, accept
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("second_nibble", ["0", "1", "4", "5", "8", "9", "c", "d"])
def test_non_laa_nibble_accepted(second_nibble):
    """Second-nibble values without the LAA bit set must be accepted."""
    mac = f"f{second_nibble}:bb:cc:dd:ee:ff"
    assert send_mac(mac) == packet.AccessAccept, f"Expected accept for MAC with nibble '{second_nibble}'"
