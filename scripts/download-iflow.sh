#!/usr/bin/env bash

###############################################################################
# Script Name : download-iflow.sh
#
# Description :
#   Downloads all selected SAP CPI iFlows using their saved SAP version.
#
# Inputs:
#   SAP_ACCESS_TOKEN
#   SAP_CPI_API_BASE_URL
#   DOWNLOAD_DIR
#   EXTRACT_ZIP
#   selected-iflows.json
#
# Outputs:
#   matched-iflows.json
#   failed-iflows.json
#
###############################################################################

set -euo pipefail

###############################################################################
# Validate Environment
###############################################################################

required_vars=(
    SAP_ACCESS_TOKEN
    SAP_CPI_API_BASE_URL
    DOWNLOAD_DIR
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Environment variable '$var' is missing."
        exit 1
    fi
done

if [[ ! -f selected-iflows.json ]]; then
    echo "ERROR: selected-iflows.json not found."
    exit 1
fi

###############################################################################
# Initialize
###############################################################################

API_BASE="${SAP_CPI_API_BASE_URL%/}"

mkdir -p "$DOWNLOAD_DIR"

echo "[]" > matched-iflows.json
echo "[]" > failed-iflows.json

SUCCESS_COUNT=0
FAILED_COUNT=0

###############################################################################
# Download Function
###############################################################################

download_iflow() {

    local json="$1"

    local IFLOW_ID
    local IFLOW_NAME
    local PACKAGE_ID
    local VERSION

    IFLOW_ID=$(echo "$json" | jq -r '.id')
    IFLOW_NAME=$(echo "$json" | jq -r '.name')
    PACKAGE_ID=$(echo "$json" | jq -r '.packageId // "NA"')
    VERSION=$(echo "$json" | jq -r '.savedVersion')

    SAFE_ID=$(echo "$IFLOW_ID" | tr -cd '[:alnum:]_.-')
    SAFE_VERSION=$(echo "$VERSION" | tr -cd '[:alnum:]_.-')

    TARGET_DIR="$DOWNLOAD_DIR/$SAFE_ID/$SAFE_VERSION"

    ZIP_FILE="$TARGET_DIR/${SAFE_ID}_${SAFE_VERSION}.zip"
    ERROR_FILE="$TARGET_DIR/error.json"

    mkdir -p "$TARGET_DIR"

    ODATA_ID=$(printf "%s" "$IFLOW_ID" | sed "s/'/''/g")
    ODATA_VERSION=$(printf "%s" "$VERSION" | sed "s/'/''/g")

    DOWNLOAD_URL="$API_BASE/api/v1/IntegrationDesigntimeArtifacts(Id='$ODATA_ID',Version='$ODATA_VERSION')/\$value"

    echo ""
    echo "============================================================"
    echo "Downloading iFlow"
    echo "------------------------------------------------------------"
    echo "ID       : $IFLOW_ID"
    echo "Name     : $IFLOW_NAME"
    echo "Package  : $PACKAGE_ID"
    echo "Version  : $VERSION"
    echo "============================================================"

    HTTP_CODE=$(curl -sS \
        --connect-timeout 20 \
        --max-time 120 \
        --request GET \
        "$DOWNLOAD_URL" \
        --header "Authorization: Bearer $SAP_ACCESS_TOKEN" \
        --header "Accept: application/zip" \
        --output "$ZIP_FILE" \
        --write-out "%{http_code}")

    echo "HTTP Status : $HTTP_CODE"

    ###########################################################################
    # SUCCESS
    ###########################################################################

    if [[ "$HTTP_CODE" == "200" && -s "$ZIP_FILE" ]]; then

        echo "Download successful."

        if [[ "${EXTRACT_ZIP:-false}" == "true" ]]; then

            EXTRACT_DIR="$TARGET_DIR/extracted"

            rm -rf "$EXTRACT_DIR"

            mkdir -p "$EXTRACT_DIR"

            if unzip -tq "$ZIP_FILE" >/dev/null 2>&1; then

                unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"

                echo "ZIP extracted."

            else

                echo "WARNING: Invalid ZIP file."

            fi

        fi

        TMP=$(mktemp)

        jq \
          --arg id "$IFLOW_ID" \
          --arg name "$IFLOW_NAME" \
          --arg package "$PACKAGE_ID" \
          --arg version "$VERSION" \
          --arg zip "$ZIP_FILE" \
          --arg folder "$TARGET_DIR" \
          '. += [{
              id:$id,
              name:$name,
              packageId:$package,
              downloadedVersion:$version,
              zipFile:$zip,
              folder:$folder,
              status:"Downloaded"
          }]' \
          matched-iflows.json > "$TMP"

        mv "$TMP" matched-iflows.json

        SUCCESS_COUNT=$((SUCCESS_COUNT+1))

    ###########################################################################
    # FAILURE
    ###########################################################################

    else

        echo "Download failed."

        curl -sS \
            --request GET \
            "$DOWNLOAD_URL" \
            --header "Authorization: Bearer $SAP_ACCESS_TOKEN" \
            --header "Accept: application/json" \
            --output "$ERROR_FILE" || true

        rm -f "$ZIP_FILE"

        TMP=$(mktemp)

        jq \
          --arg id "$IFLOW_ID" \
          --arg version "$VERSION" \
          --arg code "$HTTP_CODE" \
          --arg error "$ERROR_FILE" \
          '. += [{
              id:$id,
              attemptedVersion:$version,
              httpCode:$code,
              errorFile:$error,
              status:"Failed"
          }]' \
          failed-iflows.json > "$TMP"

        mv "$TMP" failed-iflows.json

        FAILED_COUNT=$((FAILED_COUNT+1))

    fi

}

###############################################################################
# Main
###############################################################################

TOTAL=$(jq length selected-iflows.json)

echo ""
echo "============================================================"
echo "Total iFlows selected : $TOTAL"
echo "============================================================"

jq -c '.[]' selected-iflows.json | while read -r IFLOW
do
    download_iflow "$IFLOW"
done

###############################################################################
# Summary
###############################################################################

echo ""
echo "============================================================"
echo "Download Summary"
echo "============================================================"

SUCCESS=$(jq length matched-iflows.json)
FAILED=$(jq length failed-iflows.json)

echo "Downloaded : $SUCCESS"
echo "Failed     : $FAILED"

if [[ "$SUCCESS" -eq 0 ]]; then
    echo "ERROR: No iFlows were downloaded."
    exit 1
fi

if [[ "$FAILED" -gt 0 ]]; then
    echo ""
    echo "Some downloads failed:"
    jq .
    failed-iflows.json
fi

echo ""
echo "Download completed successfully."