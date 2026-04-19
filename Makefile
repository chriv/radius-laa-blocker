.PHONY: build deploy test-setup test-server test test-all

# Build deployment artifacts for a host.
# Usage: make build HOST=host-1-dev
build:
	@test -n "$(HOST)" || (echo "Usage: make build HOST=<host>"; exit 1)
	bash scripts/build.sh $(HOST)

# Build and deploy a host.
# Usage: make deploy HOST=host-1-dev
deploy: build
	bash scripts/deploy.sh $(HOST)

# Create the Python venv and install test dependencies.
test-setup:
	python3 -m venv tests/.venv
	tests/.venv/bin/pip install --quiet --upgrade pip
	tests/.venv/bin/pip install --quiet -r tests/requirements.txt
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
#   make test                                    # host-1-dev on localhost
#   TEST_HOST=host-1 make test                   # production host-1 on localhost
#   RADIUS_HOST=rasp5-1 TEST_HOST=host-2 make test  # production host-2 remote
test:
	@test -f tests/.venv/bin/pytest || (echo "Run 'make test-setup' first"; exit 1)
	cd tests && TEST_HOST=$(or $(TEST_HOST),host-1-dev) .venv/bin/pytest -v

# Full test cycle: start server, run tests, tear down.
test-all: test-server
	$(MAKE) test
	docker compose -f build/host-1-dev/docker-compose.yml down
