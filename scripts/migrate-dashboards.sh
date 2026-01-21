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
echo "Generating IAM access token..."

ACCESS_TOKEN=$(curl -s -X POST \
  "https://iam.cloud.ibm.com/identity/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=urn:ibm:params:oauth:grant-type:apikey" \
  --data-urlencode "apikey=${IBM_CLOUD_API_KEY}" \
  | jq -r '.access_token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "ERROR: Failed to generate access token"
  exit 1
fi

AUTH_HEADER="Authorization: Bearer ${ACCESS_TOKEN}"

SOURCE_BASE_URL="https://${SOURCE_ID}.api.${SOURCE_REGION}.logs.cloud.ibm.com/v1"
TARGET_BASE_URL="https://${TARGET_ID}.api.${TARGET_REGION}.logs.cloud.ibm.com/v1"

# -----------------------------
# Folder name → target folder id map
# -----------------------------
declare -A FOLDER_MAP

# -----------------------------
# Fetch dashboards (LIST contains folder info)
# -----------------------------
echo "Fetching dashboards from source..."

DASHBOARD_LIST=$(curl -s \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  "${SOURCE_BASE_URL}/dashboards")

DASHBOARD_COUNT=$(echo "$DASHBOARD_LIST" | jq '.dashboards | length')

if [[ "$DASHBOARD_COUNT" -eq 0 ]]; then
  echo "No dashboards found in source."
  exit 0
fi

echo "Found $DASHBOARD_COUNT dashboards."
echo

# -----------------------------
# Migrate dashboards
# -----------------------------
echo "$DASHBOARD_LIST" | jq -c '.dashboards[]' | while read -r DASH; do
  DASHBOARD_ID=$(echo "$DASH" | jq -r '.id')
  DASHBOARD_NAME=$(echo "$DASH" | jq -r '.name // "unknown"')
  FOLDER_NAME=$(echo "$DASH" | jq -r '.folder.name // empty')

  echo "Processing dashboard: $DASHBOARD_NAME"
  echo "→ Source dashboard ID: $DASHBOARD_ID"

  TARGET_FOLDER_ID=""

  # -----------------------------
  # Create folder on target (if needed)
  # -----------------------------
  if [[ -n "$FOLDER_NAME" ]]; then
    if [[ -n "${FOLDER_MAP[$FOLDER_NAME]:-}" ]]; then
      TARGET_FOLDER_ID="${FOLDER_MAP[$FOLDER_NAME]}"
    else
      echo "→ Creating folder on target: $FOLDER_NAME"

      FOLDER_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "$(jq -n --arg name "$FOLDER_NAME" '{name: $name}')" \
        "${TARGET_BASE_URL}/folders")

      TARGET_FOLDER_ID=$(echo "$FOLDER_RESPONSE" | jq -r '.id')

      if [[ -z "$TARGET_FOLDER_ID" || "$TARGET_FOLDER_ID" == "null" ]]; then
        echo "✖ Failed to create folder: $FOLDER_NAME"
        echo "$FOLDER_RESPONSE"
        continue
      fi

      FOLDER_MAP["$FOLDER_NAME"]="$TARGET_FOLDER_ID"
      echo "✔ Folder created with ID: $TARGET_FOLDER_ID"
    fi
  fi

  # -----------------------------
  # GET dashboard by ID
  # -----------------------------
  DASHBOARD=$(curl -s \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    "${SOURCE_BASE_URL}/dashboards/${DASHBOARD_ID}")

  # -----------------------------
  # Remove id and update folder.id
  # -----------------------------
  if [[ -n "$TARGET_FOLDER_ID" ]]; then
  PAYLOAD=$(echo "$DASHBOARD" | jq \
    --arg folder_id "$TARGET_FOLDER_ID" \
    'del(.id, .folder) | .folder_id.value = $folder_id')
  else
  PAYLOAD=$(echo "$DASHBOARD" | jq 'del(.id, .folder)')
  fi


  # -----------------------------
  # POST dashboard to target
  # -----------------------------
  RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d "$PAYLOAD" \
    "${TARGET_BASE_URL}/dashboards")

  if echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    echo "✔ Successfully migrated: $DASHBOARD_NAME"
  else
    echo "✖ Failed to migrate: $DASHBOARD_NAME"
    echo "$RESPONSE"
  fi

  echo "----------------------------------------"
done

echo "✅ Dashboard migration completed."
