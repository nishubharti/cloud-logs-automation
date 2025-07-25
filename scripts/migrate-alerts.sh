#!/bin/bash

# === Prompt for user input ===
read -p "Enter your IBM Log Analysis Instance ID: " INSTANCE_ID
read -p "Enter the region (e.g., eu-gb): " REGION
read -p "Enter your Target IBM Log Analysis Instance ID: " TARGET_INSTANCE_ID
read -p "Enter the Target Instance region (e.g., eu-gb): " TARGET_REGION
read -s -p "Enter your IBM Cloud API Key: " APIKEY
echo

# === IBM Cloud login ===
echo "Logging in to IBM Cloud..."

ibmcloud login --apikey "$APIKEY" -r "$REGION" -a=cloud.ibm.com
if [ $? -ne 0 ]; then
  echo "IBM Cloud login failed. Please check your API key or region."
  exit 1
fi
echo "Logging successful"

# === Get IAM Bearer Token ===
IAM_TOKEN=$(ibmcloud iam oauth-tokens | grep "IAM token:" | sed -E 's/.*Bearer (.*)/\1/')
if [ -z "$IAM_TOKEN" ]; then
  echo "Failed to retrieve IAM token."
  exit 1
fi

LIST_ALERT_ENDPOINT="https://${INSTANCE_ID}.api.${REGION}.logs.cloud.ibm.com/v1/alerts"

# 1. Get all alerts
LIST_ALERT_RESPONSE=$(curl -s -X GET "$LIST_ALERT_ENDPOINT" \
  -H "Authorization: Bearer $IAM_TOKEN" \
  -H "Accept: application/json")

echo "Full response:"
echo "$LIST_ALERT_RESPONSE" | jq .


# 2. Check for any integration_id fields
INTEGRATION_IDS=$(echo "$LIST_ALERT_RESPONSE" | jq '.alerts[].notification_groups[].notifications[]?.integration_id?')

if [[ -n "$INTEGRATION_IDS" && "$INTEGRATION_IDS" != "null" ]]; then
  echo "⚠️ Detected 'integration_id' in alert notifications:"
  echo "$INTEGRATION_IDS" | sort | uniq | sed 's/^/- /'

  read -p "Would you like to proceed without event notification configuration these alerts? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "❌ Aborting. Please create the required integrations before proceeding."
    exit 1
  fi
fi

# Target endpoint to create alert
TARGET_ALERT_ENDPOINT="https://${TARGET_INSTANCE_ID}.api.${TARGET_REGION}.logs.cloud.ibm.com/v1/alerts"

# 2. Process each alert individually
echo "$LIST_ALERT_RESPONSE" | jq -c '.alerts[]' | while read -r alert; do

    # Check if integration_id exists in this alert
    HAS_INTEGRATION_ID=$(echo "$alert" | jq '[.notification_groups[].notifications[]? | has("integration_id")] | any')
    if [[ "$HAS_INTEGRATION_ID" == "true" ]]; then
        echo "Alert contains 'integration_id'. proceeding without event notification integration"
        CLEANED_ALERT=$(echo "$alert" | jq 'del(.id, .unique_identifier) | .notification_groups |= map(del(.notifications))')
    else
        CLEANED_ALERT=$(echo "$alert" | jq 'del(.id, .unique_identifier)')
    fi

    echo "Creating alert:"
    echo "$CLEANED_ALERT" | jq '.'

     # === Get IAM Bearer Token as if there will be large number of alerts during the execution there is chance that the token gets exprired===
    IAM_TOKEN=$(ibmcloud iam oauth-tokens | grep "IAM token:" | sed -E 's/.*Bearer (.*)/\1/')
    if [ -z "$IAM_TOKEN" ]; then
      echo "Failed to retrieve IAM token."
      exit 1
    fi

    curl -s -X POST "$TARGET_ALERT_ENDPOINT" \
        -H "Authorization: Bearer $IAM_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CLEANED_ALERT"

    echo -e "\n---\n"

done
