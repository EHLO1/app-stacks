# Caddy Internal (Dynamic TLS & Reverse Proxy)
This configuration can be used to deploy a Caddy application stack using Docker Compose.

## Purpose
I needed a setup that would allow me to issue trusted certificates for internal-only web services. Caddy natively handles TLS and reverse proxying. Using n8n for this is not necessary, but it allows me to list domains in an n8n Data Table, which n8n then takes and deploys a dynamic Caddyfile for. I plan to eventually drop the Data Table and tie this to a Technitium DNS Zone (via API) instead.

I have also read about Caddy's API and think it may be a more solid path than creation of a dynamic Caddyfile in the longterm. For now though, this is the way.

## Overview
- Caddy v2, repackaged with the cloudflare-dns module, and additional packages to facilitate dynamic configuration
- n8n-workflow.json file for the associated n8n workflow
- Additonal caddy bootstrap files to facilitate dynamic configuration.