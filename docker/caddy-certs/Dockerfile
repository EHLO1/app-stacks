FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/mholt/caddy-events-exec

FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

RUN echo -e '#!/bin/sh\n\
mkdir -p /certs\n\
cp /data/caddy/"$1" /certs/"$BASE_URL".crt\n\
cp /data/caddy/"$2" /certs/"$BASE_URL".key\n\
chown -R 1000:1000 /certs' > /usr/local/bin/deploy-certs.sh \
    && chmod +x /usr/local/bin/deploy-certs.sh