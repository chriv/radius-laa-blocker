"""Load host-1-dev .env before tests so RADIUS_* env vars are available."""
import os
from pathlib import Path

_env_file = Path(__file__).parent.parent / "hosts" / "host-1-dev" / ".env"

if _env_file.exists():
    with open(_env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())
