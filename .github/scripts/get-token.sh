#!/usr/bin/env bash

###############################################################################
# Script Name : get-token.sh
# Description : Generates SAP BTP OAuth Access Token
# Author      : GitHub Actions
###############################################################################

set -euo pipefail

echo "========================================================="
echo "Generating SAP BTP OAuth Access Token"
echo "========================================================="

#######################################
# Validate required environment variables
#######################################

required_vars=(
  SAP_BTP_TOKEN_URL
  SAP_BTP_OAUTH_CLIENT_ID
  SAP_BTP_OAUTH_CLIENT_SECRET
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "::error::$var is not set."
        exit 1
    fi
done

#######################################
# Normalize Token URL
#######################################

TOKEN_URL="${SAP_BTP_TOKEN_URL%/}"

# Append /oauth/token only if missing
if [[ "$TOKEN_URL" != */oauth/token ]]; then
    TOKEN_URL="${TOKEN_URL}/oauth/token"
fi

echo "Token Endpoint:"
echo "$TOKEN_URL"

#######################################
# Request OAuth Token
#######################################

MAX_RETRIES=3
RETRY=1

while [[ $RETRY -le $MAX_RETRIES ]]
do

    echo ""
    echo "Attempt $RETRY of $MAX_RETRIES..."

    RESPONSE=$(curl --silent --show-error \
        --request POST \
        --user "${SAP_BTP_OAUTH_CLIENT_ID}:${SAP_BTP_OAUTH_CLIENT_SECRET}" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data "grant_type=client_credentials" \
        --write-out "\nHTTP_STATUS:%{http_code}" \
        "$TOKEN_URL")

    HTTP_STATUS=$(echo "$RESPONSE" | awk -F: '/HTTP_STATUS/ {print $2}')
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

    echo "HTTP Status : $HTTP_STATUS"

    if [[ "$HTTP_STATUS" == "200" ]]; then
        break
    fi

    echo "Token request failed."

    if [[ $RETRY -lt $MAX_RETRIES ]]; then
        echo "Retrying..."
        sleep 2
    fi

    RETRY=$((RETRY + 1))

done

#######################################
# Validate Response
#######################################

if [[ "$HTTP_STATUS" != "200" ]]; then
    echo "::error::Unable to generate SAP OAuth token."

    echo ""
    echo "Response:"
    echo "$BODY"

    exit 1
fi

#######################################
# Extract Token
#######################################

ACCESS_TOKEN=$(echo "$BODY" | jq -r '.access_token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then

    echo "::error::access_token not found."

    echo "$BODY"

    exit 1
fi

#######################################
# Mask Token
#######################################

echo "::add-mask::$ACCESS_TOKEN"

#######################################
# Export Token
#######################################

{
    echo "SAP_ACCESS_TOKEN=$ACCESS_TOKEN"
} >> "$GITHUB_ENV"

#######################################
# Optional Information
#######################################

TOKEN_TYPE=$(echo "$BODY" | jq -r '.token_type // "Bearer"')
EXPIRES_IN=$(echo "$BODY" | jq -r '.expires_in // "Unknown"')

echo ""
echo "Token Type : $TOKEN_TYPE"
echo "Expires In : $EXPIRES_IN seconds"

echo ""
echo "SAP OAuth token generated successfully."
echo "========================================================="