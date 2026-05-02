.PHONY: build deploy test-setup test-server test test-all test-production test-production-ssh

# venv layout: bin/ on Unix/macOS, Scripts/ on Windows
ifeq ($(OS),Windows_NT)
VENV_BIN := tests/.venv/Scripts
else
VENV_BIN := tests/.venv/bin
endif

# Build deployment artifacts for a host.
# Usage: make build HOST=<host>
build:
	@test -n "$(HOST)" || (echo "Usage: make build HOST=<host>"; exit 1)
	bash scripts/build.sh $(HOST)

# Build and deploy a host.
# Usage: make deploy HOST=<host>
deploy: build
	bash scripts/deploy.sh $(HOST)

# Create the Python venv and install test dependencies.
test-setup:
	python3 -m venv tests/.venv
	$(VENV_BIN)/pip install --quiet --upgrade pip
	$(VENV_BIN)/pip install --quiet -r tests/requirements.txt
	@echo "Test environment ready. Run 'make test-server' then 'make test'."

# Start a long-running FreeRADIUS container for integration testing.
# Re-run to restart with updated config.
test-server:
	bash scripts/build.sh host-1-dev
	docker compose -f build/host-1-dev/docker-compose.yml up --build -d
	@echo "Test server running on port 18120. Run 'make test' to execute suite."

# Run the integration test suite against a running server.
# TEST_HOST selects which hosts/<host>/.env to load (default: host-1-dev).
# RADIUS_HOST overrides the server address (default: 127.0.0.1).
# Examples:
#   make test                                            # host-1-dev on localhost
#   TEST_HOST=host-1 make test                           # production host-1 on localhost
#   RADIUS_HOST=10.0.0.1 TEST_HOST=host-2 make test     # production host-2 remote
test:
	@test -f $(VENV_BIN)/pytest || (echo "Run 'make test-setup' first"; exit 1)
	TEST_HOST=$(or $(TEST_HOST),host-1-dev) $(VENV_BIN)/pytest tests/ -v

# Full test cycle: start server, run tests, tear down.
test-all: test-server
	$(MAKE) test
	docker compose -f build/host-1-dev/docker-compose.yml down

# Run the test suite against both production hosts on port 1812.
# Always tests both hosts and reports a combined exit code.
# Requires RADIUS_HOST_1 and RADIUS_HOST_2 (hostname or IP of each host).
#
# NOTE: pyrad uses select.poll() which is Unix-only. On Windows, use
# test-production-ssh to run the suite on a remote Unix host instead.
#
# Example:
#   make test-production RADIUS_HOST_1=10.0.0.1 RADIUS_HOST_2=10.0.0.2
test-production:
	@test -n "$(RADIUS_HOST_1)" || (echo "Usage: make test-production RADIUS_HOST_1=<addr> RADIUS_HOST_2=<addr>"; exit 1)
	@test -n "$(RADIUS_HOST_2)" || (echo "Usage: make test-production RADIUS_HOST_1=<addr> RADIUS_HOST_2=<addr>"; exit 1)
	@test -f $(VENV_BIN)/pytest || (echo "Run 'make test-setup' first"; exit 1)
	@rc=0; \
	echo "=== host-1 ($(RADIUS_HOST_1):1812) ==="; \
	RADIUS_HOST=$(RADIUS_HOST_1) TEST_HOST=host-1 $(VENV_BIN)/pytest tests/ -v || rc=1; \
	echo "=== host-2 ($(RADIUS_HOST_2):1812) ==="; \
	RADIUS_HOST=$(RADIUS_HOST_2) TEST_HOST=host-2 $(VENV_BIN)/pytest tests/ -v || rc=1; \
	exit $$rc

# Same as test-production but executes on a remote Unix host via SSH.
# Use this from Windows where pyrad's select.poll() is unavailable.
# The remote host must have the repo checked out and venv set up (make test-setup).
# Requires:
#   TEST_RUNNER_SSH_HOST  — SSH target (e.g. user@my-unix-box)
#   TEST_RUNNER_REPO_PATH — path to the repo on that host
#   RADIUS_HOST_1 / RADIUS_HOST_2 — production host addresses
#
# Example:
#   make test-production-ssh \
#     TEST_RUNNER_SSH_HOST=user@my-unix-box \
#     TEST_RUNNER_REPO_PATH=~/projects/radius-laa-blocker \
#     RADIUS_HOST_1=10.0.0.1 \
#     RADIUS_HOST_2=10.0.0.2
test-production-ssh:
	@test -n "$(TEST_RUNNER_SSH_HOST)"  || (echo "Usage: make test-production-ssh TEST_RUNNER_SSH_HOST=user@host TEST_RUNNER_REPO_PATH=<path> RADIUS_HOST_1=<addr> RADIUS_HOST_2=<addr>"; exit 1)
	@test -n "$(TEST_RUNNER_REPO_PATH)" || (echo "Usage: make test-production-ssh TEST_RUNNER_SSH_HOST=user@host TEST_RUNNER_REPO_PATH=<path> RADIUS_HOST_1=<addr> RADIUS_HOST_2=<addr>"; exit 1)
	@test -n "$(RADIUS_HOST_1)"         || (echo "Usage: make test-production-ssh TEST_RUNNER_SSH_HOST=user@host TEST_RUNNER_REPO_PATH=<path> RADIUS_HOST_1=<addr> RADIUS_HOST_2=<addr>"; exit 1)
	@test -n "$(RADIUS_HOST_2)"         || (echo "Usage: make test-production-ssh TEST_RUNNER_SSH_HOST=user@host TEST_RUNNER_REPO_PATH=<path> RADIUS_HOST_1=<addr> RADIUS_HOST_2=<addr>"; exit 1)
	ssh $(TEST_RUNNER_SSH_HOST) \
	    "cd $(TEST_RUNNER_REPO_PATH) && git pull --quiet && \
	     rc=0; \
	     echo '=== host-1 ($(RADIUS_HOST_1):1812) ==='; \
	     RADIUS_HOST=$(RADIUS_HOST_1) TEST_HOST=host-1 tests/.venv/bin/pytest tests/ -v || rc=1; \
	     echo '=== host-2 ($(RADIUS_HOST_2):1812) ==='; \
	     RADIUS_HOST=$(RADIUS_HOST_2) TEST_HOST=host-2 tests/.venv/bin/pytest tests/ -v || rc=1; \
	     exit \$$rc"
