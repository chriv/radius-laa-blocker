FROM freeradius/freeradius-server:latest

COPY config/clients.conf /etc/freeradius/clients.conf
COPY config/sites-available/default /etc/freeradius/sites-available/default

EXPOSE 1812/udp
