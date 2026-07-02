#!/usr/bin/env bash

###############################################################################
# Script Name : create-manifest.sh
#
# Description :
#   Generates a download manifest after the iFlow backup completes.
#
# Input Files :
#   matched-iflows.json
#   failed-iflows.json (optional)
#
# Output :
#   btp-iflows/download-manifest.json
#
###############################################################################

set -euo pipefail

echo "============================================================"
echo "Creating Download Manifest"
echo "============================================================"

DOWNLOAD_DIR="${DOWNLOAD_DIR:-btp-iflows}"
TARGET_BRANCH="${TARGET_BRANCH:-unknown}"
DEPLOYMENT_MARKER="${DEPLOYMENT_MARKER:-ReadyForDeployment}"

MATCHED_FILE="matched-iflows.json"
FAILED_FILE="failed-iflows.json"

MANIFEST_FILE="$DOWNLOAD_DIR/download-manifest.json"

mkdir -p "$DOWNLOAD_DIR"

###############################################################################
# Validate required files
###############################################################################

if [[ ! -f "$MATCHED_FILE" ]]; then
    echo "ERROR: $MATCHED_FILE not found."
    exit 1
fi

###############################################################################
# Counts
###############################################################################

DOWNLOADED_COUNT=$(jq length "$MATCHED_FILE")

if [[ -f "$FAILED_FILE" ]]; then
   FAILED_COUNT=$(jq length "$FAILED_FILE")
else
   FAILED_COUNT=0
fi

###############################################################################
# Generate manifest
###############################################################################

jq \
    --arg generatedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg workflowRun "${GITHUB_RUN_NUMBER:-N/A}" \
    --arg workflowId "${GITHUB_RUN_ID:-N/A}" \
    --arg repository "${GITHUB_REPOSITORY:-N/A}" \
    --arg commit "${GITHUB_SHA:-N/A}" \
    --arg branch "$TARGET_BRANCH" \
    --arg marker "$DEPLOYMENT_MARKER" \
    --arg versionRule "X.Y.Z.ReadyForDeployment" \
    --argjson downloaded "$DOWNLOADED_COUNT" \
    --argjson failed "$FAILED_COUNT" \
'
{
    manifestVersion: "1.0",

    generatedAtUtc: $generatedAt,

    github: {
        repository: $repository,
        workflowRunNumber: $workflowRun,
        workflowRunId: $workflowId,
        commit: $commit,
        targetBranch: $branch
    },

    backupPolicy: {
        deploymentMarker: $marker,
        acceptedVersionPattern: $versionRule,
        filterMode: "CASE-SENSITIVE"
    },

    summary: {
        downloaded: $downloaded,
        failed: $failed
    },

    downloadedArtifacts: .
}
' "$MATCHED_FILE" > "$MANIFEST_FILE"

###############################################################################
# Display summary
###############################################################################

echo ""
echo "Manifest created successfully"
echo "Location : $MANIFEST_FILE"
echo ""

jq . "$MANIFEST_FILE"

echo ""
echo "============================================================"
echo "Backup Summary"
echo "============================================================"
echo "Downloaded : $DOWNLOADED_COUNT"
echo "Failed     : $FAILED_COUNT"
echo "Manifest   : $MANIFEST_FILE"
echo "============================================================"
