#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# File        : common.sh
# Description : Common utility functions for SAP Integration Suite GitHub Actions
# Author      : GitHub Actions
# -----------------------------------------------------------------------------

set -euo pipefail

################################################################################
# Logging
################################################################################

log_info() {
    echo "[INFO ] $*"
}

log_warn() {
    echo "[WARN ] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[ OK  ] $*"
}

start_group() {
    echo "::group::$*"
}

end_group() {
    echo "::endgroup::"
}

################################################################################
# Exit with error
################################################################################

die() {
    log_error "$1"
    exit 1
}

################################################################################
# Verify command exists
################################################################################

require_command() {

    local cmd="$1"

    command -v "$cmd" >/dev/null 2>&1 || \
        die "Required command '$cmd' is not installed."

}

################################################################################
# Validate environment variable
################################################################################

require_env() {

    local variable="$1"

    if [[ -z "${!variable:-}" ]]; then
        die "Environment variable '$variable' is not set."
    fi

}

################################################################################
# Normalize URL
################################################################################

normalize_url() {

    local url="$1"

    echo "${url%/}"

}

################################################################################
# Escape OData string
################################################################################

odata_escape() {

    printf "%s" "$1" | sed "s/'/''/g"

}

################################################################################
# Create directory if missing
################################################################################

ensure_directory() {

    mkdir -p "$1"

}

################################################################################
# Safe filename
################################################################################

safe_filename() {

    echo "$1" | tr -cd '[:alnum:]_.-'

}

################################################################################
# HTTP GET wrapper
################################################################################

http_get() {

    local url="$1"
    local output="$2"
    local accept="${3:-application/json}"

    curl -sS \
        --connect-timeout 20 \
        --max-time 120 \
        --request GET \
        --header "Authorization: Bearer ${SAP_ACCESS_TOKEN}" \
        --header "Accept: ${accept}" \
        --output "$output" \
        --write-out "%{http_code}" \
        "$url"

}

################################################################################
# HTTP POST wrapper
################################################################################

http_post() {

    local url="$1"
    local output="$2"
    shift 2

    curl -sS \
        --request POST \
        --output "$output" \
        --write-out "%{http_code}" \
        "$url" \
        "$@"

}

################################################################################
# Verify HTTP status
################################################################################

check_http_status() {

    local status="$1"
    local response="$2"

    if [[ "$status" != "200" ]]; then

        log_error "HTTP Status : $status"

        if [[ -f "$response" ]]; then
            cat "$response"
        fi

        exit 1

    fi

}

################################################################################
# Read JSON property
################################################################################

json_value() {

    local file="$1"
    local expression="$2"

    jq -r "$expression" "$file"

}

################################################################################
# Git configuration
################################################################################

configure_git() {

    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"

}

################################################################################
# Checkout target branch
################################################################################

checkout_branch() {

    local branch="$1"

    git fetch origin

    if git ls-remote --exit-code --heads origin "$branch" >/dev/null
    then
        log_info "Checking out existing branch: $branch"

        git checkout "$branch"

        git pull origin "$branch"

    else

        log_info "Creating new branch: $branch"

        git checkout -b "$branch"

    fi

}

################################################################################
# Commit changes
################################################################################

commit_changes() {

    local folder="$1"
    local message="$2"
    local branch="$3"

    git add "$folder"

    if git diff --cached --quiet
    then
        log_info "No changes to commit."
        return
    fi

    git commit -m "$message"

    git push origin "$branch"

    log_success "Changes pushed successfully."

}

################################################################################
# Download file
################################################################################

download_file() {

    local url="$1"
    local output="$2"
    local accept="${3:-application/zip}"

    curl -sS \
        --connect-timeout 20 \
        --max-time 300 \
        --request GET \
        --header "Authorization: Bearer ${SAP_ACCESS_TOKEN}" \
        --header "Accept: ${accept}" \
        --output "$output" \
        --write-out "%{http_code}" \
        "$url"

}

################################################################################
# Validate ZIP
################################################################################

extract_zip() {

    local zip="$1"
    local destination="$2"

    if unzip -tq "$zip" >/dev/null 2>&1
    then

        rm -rf "$destination"

        mkdir -p "$destination"

        unzip -q "$zip" -d "$destination"

        log_success "ZIP extracted."

    else

        log_warn "Invalid ZIP archive."

    fi

}

################################################################################
# Print section header
################################################################################

print_header() {

    echo
    echo "=============================================================="
    echo "$1"
    echo "=============================================================="

}

################################################################################
# Initialization
################################################################################

initialize() {

    require_command curl
    require_command jq
    require_command git
    require_command unzip

}
}