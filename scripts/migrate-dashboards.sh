#!/usr/bin/env bash

set -euo pipefail

# -----------------------------
# Usage
# -----------------------------
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <source_id> <source_region> <target_id> <target_region>"
  exit 1
fi

SOURCE_ID="$1"
SOURCE_REGION="$2"
TARGET_ID="$3"
TARGET_REGION="$4"

# -----------------------------
# API Key check
# -----------------------------
if [[ -z "${IBM_CLOUD_API_KEY:-}" ]]; then
  echo "ERROR: IBM_CLOUD_API_KEY environment variable is not set"
  exit 1
fi

# -----------------------------
# Generate Bearer Token
# -----------------------------
echo "Generating Bearer token..."

TOKEN_RESPONSE=$(curl -s -X POST \
  "https://iam.cloud.ibm.com/identity/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=urn:ibm:params:oauth:grant-type:apikey" \
  --data-urlencode "apikey=${IBM_CLOUD_API_KEY}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "ERROR: Failed to generate access token"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

AUTH_HEADER="Authorization: Bearer ${ACCESS_TOKEN}"

# -----------------------------
# Fetch dashboards from source
# -----------------------------
SOURCE_URL="https://${SOURCE_ID}.api.${SOURCE_REGION}.logs.cloud.ibm.com/v1/dashboards"

echo "Fetching dashboards from source: $SOURCE_URL"

DASHBOARD_RESPONSE=$(curl -s \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  "$SOURCE_URL")

DASHBOARD_COUNT=$(echo "$DASHBOARD_RESPONSE" | jq '.dashboards | length')

if [[ "$DASHBOARD_COUNT" -eq 0 ]]; then
  echo "No dashboards found in source."
  exit 0
fi

echo "Found $DASHBOARD_COUNT dashboards."

# -----------------------------
# Post dashboards to target
# -----------------------------
TARGET_URL="https://${TARGET_ID}.api.${TARGET_REGION}.logs.cloud.ibm.com/v1/dashboards"

echo "Migrating dashboards to target: $TARGET_URL"
echo

echo "$DASHBOARD_RESPONSE" | jq -c '.dashboards[]' | while read -r dashboard; do
  NAME=$(echo "$dashboard" | jq -r '.name')

  echo "Migrating dashboard: $NAME"

  # Remove fields that should not be sent on create
  PAYLOAD=$(echo "$dashboard" | jq 'del(
      .id,
      .create_time,
      .update_time,
      .is_default,
      .is_pinned
    )')

  echo ${PAYLOAD}

  RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d "$PAYLOAD" \
    "$TARGET_URL")

  if echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    echo "✔ Successfully created: $NAME"
  else
    echo "✖ Failed to create: $NAME"
    echo "$RESPONSE"
  fi

  echo
done

echo "Dashboard migration completed."
