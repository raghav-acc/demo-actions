#!/usr/bin/env bash

###############################################################################
# Script Name : discover-iflows.sh
# Description : Discover SAP CPI iFlows having version
#               X.Y.Z.ReadyForDeployment
###############################################################################

set -euo pipefail

echo "========================================================="
echo "Discovering ReadyForDeployment iFlows"
echo "========================================================="

API_BASE="${SAP_CPI_API_BASE_URL%/}"

mkdir -p "$DOWNLOAD_DIR"

ACTIVE_ARTIFACTS="active-artifacts-response.json"
PACKAGES_RESPONSE="packages-response.json"
SELECTED="selected-iflows.json"
SKIPPED="skipped-iflows.json"

############################################################
# Verify API
############################################################

echo "Checking SAP CPI Metadata..."

HTTP_CODE=$(curl -sS \
    --request GET \
    "$API_BASE/api/v1/\$metadata" \
    --header "Authorization: Bearer $SAP_ACCESS_TOKEN" \
    --header "Accept: application/xml" \
    --output metadata.xml \
    --write-out "%{http_code}")

echo "Metadata Status : $HTTP_CODE"

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "ERROR: Unable to access CPI Metadata endpoint."
    head metadata.xml || true
    exit 1
fi

############################################################
# Fetch Packages
############################################################

echo ""
echo "Fetching Integration Packages..."

HTTP_CODE=$(curl -sS \
    --request GET \
    "$API_BASE/api/v1/IntegrationPackages?\$format=json" \
    --header "Authorization: Bearer $SAP_ACCESS_TOKEN" \
    --header "Accept: application/json" \
    --output "$PACKAGES_RESPONSE" \
    --write-out "%{http_code}")

echo "Package API Status : $HTTP_CODE"

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "ERROR: Failed to fetch Integration Packages."
    cat "$PACKAGES_RESPONSE"
    exit 1
fi

############################################################
# Initialize
############################################################

echo '{"d":{"results":[]}}' > "$ACTIVE_ARTIFACTS"

############################################################
# Fetch Artifacts Package-wise
############################################################

echo ""
echo "Reading packages..."

jq -r '.d.results[].Id' "$PACKAGES_RESPONSE" | while read -r PACKAGE_ID
do

    [[ -z "$PACKAGE_ID" || "$PACKAGE_ID" == "null" ]] && continue

    echo ""
    echo "Package : $PACKAGE_ID"

    SAFE_PACKAGE=$(echo "$PACKAGE_ID" | tr -cd '[:alnum:]_.-')
    RESPONSE_FILE="package-${SAFE_PACKAGE}.json"

    ODATA_PACKAGE=$(printf "%s" "$PACKAGE_ID" | sed "s/'/''/g")

    HTTP_CODE=$(curl -sS \
        --request GET \
        "$API_BASE/api/v1/IntegrationPackages('$ODATA_PACKAGE')/IntegrationDesigntimeArtifacts?\$format=json" \
        --header "Authorization: Bearer $SAP_ACCESS_TOKEN" \
        --header "Accept: application/json" \
        --output "$RESPONSE_FILE" \
        --write-out "%{http_code}")

    if [[ "$HTTP_CODE" != "200" ]]; then
        echo "WARNING : Failed to read package artifacts."
        cat "$RESPONSE_FILE" || true
        continue
    fi

    jq -s '
      {
        d:{
          results:
          (
            (.[0].d.results // [])
            +
            (.[1].d.results // [])
          )
        }
      }
    ' "$ACTIVE_ARTIFACTS" "$RESPONSE_FILE" > combined.json

    mv combined.json "$ACTIVE_ARTIFACTS"

done

############################################################
# Filter ReadyForDeployment versions
############################################################

echo ""
echo "Filtering ReadyForDeployment versions..."

python3 <<'PYTHON'

import json
import re

pattern = re.compile(r'^\d+\.\d+\.\d+\.ReadyForDeployment$')

with open("active-artifacts-response.json","r",encoding="utf-8") as f:
    payload=json.load(f)

artifacts=payload.get("d",{}).get("results",[])

matched=[]
skipped=[]

for item in artifacts:

    artifact_id=item.get("Id")
    version=item.get("Version")
    package=item.get("PackageId")
    name=item.get("Name",artifact_id)

    if not artifact_id:
        continue

    if version and pattern.match(version):

        matched.append({
            "id":artifact_id,
            "name":name,
            "packageId":package,
            "savedVersion":version
        })

    else:

        skipped.append({
            "id":artifact_id,
            "name":name,
            "packageId":package,
            "versionFromSAP":version,
            "reason":"Version does not match X.Y.Z.ReadyForDeployment"
        })

with open("selected-iflows.json","w") as f:
    json.dump(matched,f,indent=2)

with open("skipped-iflows.json","w") as f:
    json.dump(skipped,f,indent=2)

print()
print("--------------------------------------------------")
print(f"Total Artifacts : {len(artifacts)}")
print(f"Matched         : {len(matched)}")
print(f"Skipped         : {len(skipped)}")
print("--------------------------------------------------")

for item in matched:
    print(
        f"MATCHED : "
        f"{item['id']} | "
        f"{item['savedVersion']}"
    )

PYTHON

############################################################
# Validate Result
############################################################

COUNT=$(jq length "$SELECTED")

echo ""
echo "ReadyForDeployment iFlows : $COUNT"

if [[ "$COUNT" -eq 0 ]]; then
    echo "No ReadyForDeployment iFlows found."
    exit 0
fi

echo ""
echo "Discovery completed successfully."
echo "Selected iFlows written to:"
echo "  $SELECTED"
echo ""