FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:latest

# Install dependencies required for the entrypoint script
# curl: to call n8n
# bash: for the script logic
# netcat-openbsd: for 'nc' to check if Caddy is ready
RUN apk add --no-cache curl bash netcat-openbsd

# Copy the custom binary from the builder stage
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Copy local config files into the image
COPY bootstrap.caddy /etc/caddy/bootstrap.caddy
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]