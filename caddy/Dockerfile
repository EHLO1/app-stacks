# Dockerfile for Caddy with Cloudflare DNS support
# Start with the builder image
FROM caddy:builder AS builder

# Add the Cloudflare DNS module
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

# Build the final image
FROM caddy:latest

# Copy the custom binary over the standard one
COPY --from=builder /usr/bin/caddy /usr/bin/caddy