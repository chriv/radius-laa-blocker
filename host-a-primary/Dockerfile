FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends freeradius \
    && rm -rf /var/lib/apt/lists/*

COPY config/clients.conf /etc/freeradius/3.0/clients.conf
COPY config/sites-available/default /etc/freeradius/3.0/sites-available/default

EXPOSE 1812/udp

CMD ["freeradius", "-f"]
