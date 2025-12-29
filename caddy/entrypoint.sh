#!/bin/bash

# Start Caddy with bootstrap config
caddy run --config /etc/caddy/bootstrap.caddy --adapter caddyfile &
PID=$!

# Wait for Caddy
echo "Waiting for Caddy..."
until nc -z localhost 2019; do
  sleep 1
done

# Signal n8n (Source: caddy-boot)
echo "Caddy is up. Requesting config..."
curl -X POST https://n8n.jjcasa.net/webhook/caddy-config-sync \
     -H "Content-Type: application/json" \
     -H "CF-Access-Client-Id: ${CF_N8N_WEBHOOK_CLIENT_ID}" \
     -H "CF-Access-Client-Secret: ${CF_N8N_WEBHOOK_CLIENT_SECRET}"
     -d '{"source": "caddy-boot", "msg": "Hey girl! Can I get yo number?"}'

# Wait for process
wait $PID