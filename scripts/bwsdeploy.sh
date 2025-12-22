#!/bin/bash

# ==============================================================================
# Bitwarden Secrets Manager Deploy Helper for Docker/Komodo
# ==============================================================================
# Usage: ./bwsdeploy.sh -m <pre|post> -p <project_name>
#
# Dependencies: bws, jq
# Env Vars Required: BWS_ACCESS_TOKEN
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
MODE=""
PROJECT_NAME=""
ENV_LINK_NAME="../.secrets.env"
RAM_FILE="/dev/shm/.secrets.env"

# Function: Print Usage
usage() {
    echo "Usage: $0 -m <pre|post> -p <project_name>"
    echo ""
    echo "  -m  Mode of operation: 'pre' (fetch secrets) or 'post' (cleanup)"
    echo "  -p  Bitwarden Project Name (case-sensitive)"
    exit 1
}

# Parse Arguments
while getopts "m:p:" opt; do
    case $opt in
        m) MODE="$OPTARG" ;;
        p) PROJECT_NAME="$OPTARG" ;;
        *) usage ;;
    esac
done

# Validate Required Arguments
if [[ -z "$MODE" || -z "$PROJECT_NAME" ]]; then
    echo "❌ Error: Both -m (mode) and -p (project name) are required."
    usage
fi

# Validate Mode
if [[ "$MODE" != "pre" && "$MODE" != "post" ]]; then
    echo "❌ Error: Mode must be 'pre' or 'post'."
    usage
fi

# ==============================================================================
# MODE: PRE-DEPLOY
# ==============================================================================
if [[ "$MODE" == "pre" ]]; then
    echo "🔍 [PRE] Looking up Project ID for '$PROJECT_NAME'..."

    # 1. Fetch Project List and parse ID
    # We use jq to find the object where name matches, then extract the id
    PROJECT_ID=$(bws project list --access-token "$BWS_ACCESS_TOKEN" | jq -r --arg name "$PROJECT_NAME" '.[] | select(.name == $name) | .id')

    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
        echo "❌ [PRE] Error: Project '$PROJECT_NAME' not found in Bitwarden."
        exit 1
    fi
    
    echo "✅ [PRE] Found Project ID: $PROJECT_ID"
    echo "🔐 [PRE] Fetching secrets to RAM ($RAM_FILE)..."

    # 2. Fetch secrets, format as KEY=VALUE, and write to /dev/shm
    bws secret list "$PROJECT_ID" | jq -r '.[] | "\(.key)=\(.value)"' > "$RAM_FILE"

    # 3. Create Symlink
    # We use -f to force overwrite if a symlink already exists
    ln -sf "$RAM_FILE" "$ENV_LINK_NAME"

    echo "🔗 [PRE] Symlink created: $ENV_LINK_NAME -> $RAM_FILE"
    echo "🚀 [PRE] Ready for deployment."

# ==============================================================================
# MODE: POST-DEPLOY
# ==============================================================================
elif [[ "$MODE" == "post" ]]; then
    echo "🧹 [POST] Cleaning up..."

    # 1. Remove the local symlink
    if [[ -L "$ENV_LINK_NAME" ]]; then
        rm "$ENV_LINK_NAME"
        echo "🗑️  [POST] Removed symlink: $ENV_LINK_NAME"
    else
        echo "⚠️  [POST] Symlink $ENV_LINK_NAME not found (already clean?)"
    fi

    # 2. Remove the actual file from RAM
    if [[ -f "$RAM_FILE" ]]; then
        rm "$RAM_FILE"
        echo "✨ [POST] Wiped secrets from RAM: $RAM_FILE"
    else
        echo "⚠️  [POST] RAM file $RAM_FILE not found."
    fi

    echo "✅ [POST] Cleanup complete."
fi