# Build the custom binary with Cloudflare plugin
FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

# Build the final runtime image
FROM caddy:latest

# Copy the custom binary from the builder stage
COPY --from=builder /usr/bin/caddy /usr/bin/caddy