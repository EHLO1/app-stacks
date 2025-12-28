#!/bin/bash
set -e

ROUTES="${CADDY_ROUTES:-[]}"

echo "$ROUTES" | jq -r '
  .[] | 
  "\(.subdomain).jjcasa.net {
      reverse_proxy \(.scheme)://\(.target):\(.port) {
          \(if .skip_verify == true then "transport http { tls_insecure_skip_verify }" else "" end)
      }
      tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      }
  }
  "
' > /etc/caddy/routes.caddy

echo "Configuration generated. Starting Caddy..."

exec "$@"