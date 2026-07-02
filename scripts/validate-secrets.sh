#!/usr/bin/env bash

###############################################################################
# Script Name : validate-secrets.sh
# Description : Validates all required GitHub Secrets before executing the
#               SAP CPI backup workflow.
#
# Required Environment Variables:
#   SAP_BTP_TOKEN_URL
#   SAP_BTP_OAUTH_CLIENT_ID
#   SAP_BTP_OAUTH_CLIENT_SECRET
#   SAP_CPI_API_BASE_URL
###############################################################################

set -euo pipefail

echo "======================================================="
echo " Validating SAP Integration Suite Configuration"
echo "======================================================="

###############################################################################
# Required Secrets
###############################################################################

REQUIRED_SECRETS=(
  SAP_BTP_TOKEN_URL
  SAP_BTP_OAUTH_CLIENT_ID
  SAP_BTP_OAUTH_CLIENT_SECRET
  SAP_CPI_API_BASE_URL
)

###############################################################################
# Validate Secret Exists
###############################################################################

validate_secret() {

    local secret_name="$1"
    local secret_value="${!secret_name:-}"

    if [[ -z "$secret_value" ]]; then
        echo "ERROR: '$secret_name' is not configured."
        exit 1
    fi

    echo "✓ $secret_name"
}

###############################################################################
# Validate HTTPS URL
###############################################################################

validate_url() {

    local variable_name="$1"
    local url="${!variable_name}"

    if [[ ! "$url" =~ ^https:// ]]; then
        echo "ERROR: '$variable_name' must start with https://"
        exit 1
    fi

    if [[ "$url" =~ [[:space:]] ]]; then
        echo "ERROR: '$variable_name' contains whitespace."
        exit 1
    fi

    echo "✓ $variable_name URL is valid"
}

###############################################################################
# Validate All Required Secrets
###############################################################################

echo
echo "Checking required secrets..."

for secret in "${REQUIRED_SECRETS[@]}"; do
    validate_secret "$secret"
done

###############################################################################
# Validate URLs
###############################################################################

echo
echo "Checking URLs..."

validate_url SAP_BTP_TOKEN_URL
validate_url SAP_CPI_API_BASE_URL

###############################################################################
# Normalize URLs
###############################################################################

TOKEN_URL="${SAP_BTP_TOKEN_URL%/}"
API_BASE_URL="${SAP_CPI_API_BASE_URL%/}"

# Append /oauth/token if omitted
if [[ "$TOKEN_URL" != */oauth/token ]]; then
    TOKEN_URL="$TOKEN_URL/oauth/token"
fi

###############################################################################
# Export Normalized Values
###############################################################################

{
    echo "SAP_BTP_TOKEN_URL=$TOKEN_URL"
    echo "SAP_CPI_API_BASE_URL=$API_BASE_URL"
} >> "$GITHUB_ENV"

###############################################################################
# Display Configuration Summary
###############################################################################

echo
echo "======================================================="
echo " Validation Successful"
echo "======================================================="
echo "Token Endpoint : $TOKEN_URL"
echo "API Base URL   : $API_BASE_URL"
echo "OAuth Client   : Configured"
echo "Client Secret  : Configured"
echo "======================================================="

exit 0