.PHONY: build deploy test-server test test-all

# Build deployment artifacts for a host.
# Usage: make build HOST=host-1
build:
	@test -n "$(HOST)" || (echo "Usage: make build HOST=<host>"; exit 1)
	bash scripts/build.sh $(HOST)

# Build and deploy a host.
# Usage: make deploy HOST=host-1
deploy: build
	bash scripts/deploy.sh $(HOST)

# Start a long-running FreeRADIUS container for integration testing.
# Uses host-2 (development) build. Re-run to restart with updated config.
test-server:
	bash scripts/build.sh host-1-dev
	docker compose -f build/host-1-dev/docker-compose.yml up --build -d
	@echo "Test server running. Run 'make test' to execute test suite."

# Run the integration test suite against the running test-server.
test:
	cd tests && .venv/bin/pytest -v

# Full test cycle: start server, run tests, tear down.
test-all:
	$(MAKE) test-server
	$(MAKE) test
	docker compose -f build/host-1-dev/docker-compose.yml down
