# 1. Builder Stage
FROM caddy:builder AS builder
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

# 2. Runtime Stage
FROM caddy:latest

# Install jq (Alpine version)
RUN apk add --no-cache jq bash

# Copy custom binary
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Copy our bootstrap script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set the script as the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]