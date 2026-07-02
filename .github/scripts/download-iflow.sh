#!/bin/bash
set -euo pipefail

SAP_CPI_API_BASE_URL="${SAP_CPI_API_BASE_URL%/}"

echo "[]" > matched-iflows.json
echo "[]" > failed-iflows.json

jq -c '.[]' selected-iflows.json | while read -r item
do
    IFLOW_ID=$(echo "$item" | jq -r '.id')
    IFLOW_NAME=$(echo "$item" | jq -r '.name')
    PACKAGE_ID=$(echo "$item" | jq -r '.packageId')
    IFLOW_VERSION=$(echo "$item" | jq -r '.savedVersion')

    SAFE_ID=$(echo "$IFLOW_ID" | tr -cd '[:alnum:]_.-')
    SAFE_VERSION=$(echo "$IFLOW_VERSION" | tr -cd '[:alnum:]_.-')

    BASE_DIR="$DOWNLOAD_DIR/$SAFE_ID"
    CURRENT_DIR="$BASE_DIR/current"
    ARCHIVE_DIR="$BASE_DIR/archive"

    mkdir -p "$CURRENT_DIR"
    mkdir -p "$ARCHIVE_DIR"

    #
    # Archive old download
    #
    if [ "$(ls -A "$CURRENT_DIR" 2>/dev/null)" ]; then

        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

        echo "Archiving existing files for $IFLOW_ID"

        mkdir -p "$ARCHIVE_DIR/$TIMESTAMP"

        mv "$CURRENT_DIR"/* "$ARCHIVE_DIR/$TIMESTAMP/" || true
    fi

    ZIP_FILE="$CURRENT_DIR/${SAFE_ID}_${SAFE_VERSION}.zip"
    ERROR_FILE="$CURRENT_DIR/error.txt"

    DOWNLOAD_URL="$SAP_CPI_API_BASE_URL/api/v1/IntegrationDesigntimeArtifacts(Id='$IFLOW_ID',Version='$IFLOW_VERSION')/\$value"

    echo "Downloading $IFLOW_ID ($IFLOW_VERSION)"

    HTTP_CODE=$(curl -sS \
        --request GET "$DOWNLOAD_URL" \
        --header "Authorization: Bearer $SAP_ACCESS_TOKEN" \
        --header "Accept: application/zip" \
        --output "$ZIP_FILE" \
        --write-out "%{http_code}")

    if [ "$HTTP_CODE" = "200" ] && [ -s "$ZIP_FILE" ]; then

        echo "Download successful"

        if [ "$EXTRACT_ZIP" = "true" ]; then

            mkdir -p "$CURRENT_DIR/extracted"

            unzip -oq "$ZIP_FILE" -d "$CURRENT_DIR/extracted"
        fi

        jq \
        --arg id "$IFLOW_ID" \
        --arg name "$IFLOW_NAME" \
        --arg package "$PACKAGE_ID" \
        --arg version "$IFLOW_VERSION" \
        --arg folder "$CURRENT_DIR" \
        '. += [{
            id:$id,
            name:$name,
            packageId:$package,
            downloadedVersion:$version,
            folder:$folder,
            status:"Downloaded"
        }]' matched-iflows.json > tmp.json

        mv tmp.json matched-iflows.json

    else

        echo "Download failed"

        rm -f "$ZIP_FILE"

        jq \
        --arg id "$IFLOW_ID" \
        --arg version "$IFLOW_VERSION" \
        --arg code "$HTTP_CODE" \
        '. += [{
            id:$id,
            attemptedVersion:$version,
            httpCode:$code,
            status:"Failed"
        }]' failed-iflows.json > tmp.json

        mv tmp.json failed-iflows.json

    fi

done
