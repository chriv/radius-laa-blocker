"""Load a host's .env before tests so RADIUS_* env vars are available.

The host is selected via the TEST_HOST environment variable (default: host-1-dev).
Override at the command line:
    TEST_HOST=host-1 make test
    RADIUS_HOST=rasp5-1 TEST_HOST=host-2 make test
"""
import os
from pathlib import Path

_host = os.environ.get("TEST_HOST", "host-1-dev")
_env_file = Path(__file__).parent.parent / "hosts" / _host / ".env"

if _env_file.exists():
    with open(_env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())
