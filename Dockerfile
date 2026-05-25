FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    wireguard-tools \
    curl \
    jq \
    iproute2 \
    iputils \
    iptables \
    ip6tables \
    ca-certificates \
    bash \
    python3

# Create state directory
RUN mkdir -p /data/pia-wg && chmod 700 /data/pia-wg

WORKDIR /app

COPY pia-wg-firewalla.sh .
COPY web_ui.py .
RUN chmod +x pia-wg-firewalla.sh

# Mount your .env here, or pass all variables via `docker run -e` / docker-compose env_file
VOLUME ["/data/pia-wg"]

# Web UI (optional): set WEB_PORT=8080 (default) or 0 to disable
EXPOSE 8080

# NET_ADMIN + SYS_MODULE are required for WireGuard; see docker-compose.yml
ENTRYPOINT ["/app/pia-wg-firewalla.sh"]
CMD ["start"]
