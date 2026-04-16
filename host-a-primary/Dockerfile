FROM freeradius/freeradius-server:latest

# NOTE: The official freeradius/freeradius-server Docker image (Debian-based) stores
# config at /etc/freeradius/3.0/. If a deploy fails with "file not found" errors,
# exec into the container and run `find /etc -name radiusd.conf` to find the actual path.

COPY config/clients.conf /etc/freeradius/3.0/clients.conf
COPY config/sites-available/default /etc/freeradius/3.0/sites-available/default

EXPOSE 1812/udp
