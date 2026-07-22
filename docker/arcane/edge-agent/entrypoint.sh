#!/bin/sh
set -e

# Expected ENV VARS to be passed in:
# ARCANE_MANAGER_URL
# AGENT_HOSTNAME
# ARCANE_MANAGER_API_KEY

secret_file="/secrets/agent_token"
endpoint_url="$ARCANE_MANAGER_URL/api/environments"

if [ -z "$AGENT_HOSTNAME" ]; then
    echo "Error: AGENT_HOSTNAME environment variable is not set."
    exit 1
fi

# Check for existing valid token
if [ -f "$secret_file" ] && grep -q "^arc_" "$secret_file"; then
    echo "Valid agent_token already exists."
    exit 0
fi

echo "Secret missing or invalid. Requesting new token for $AGENT_HOSTNAME..."

response=$(curl "$endpoint_url" \
  --request POST \
  --header "Content-Type: application/json" \
  --header "X-Api-Key: $ARCANE_MANAGER_API_KEY" \
  --data "{
  \"apiUrl\": \"edge://$AGENT_HOSTNAME\",
  \"enabled\": true,
  \"isEdge\": true,
  \"name\": \"$AGENT_HOSTNAME\",
  \"useApiKey\": true
  }"
)

token=$(echo "$response" | jq -r '.data.apiKey // empty')

# Validate received token
if [ -z "$token" ] || ! echo "$token" | grep -q "^arc_"; then
    echo "Error: Failed to retrieve a valid token. Response was: $response"
    exit 1
fi

echo -n "$token" > "$secret_file"
echo "Token successfully written to $secret_file."
exit 0