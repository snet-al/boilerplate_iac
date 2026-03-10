#!/bin/bash
# =============================================================================
# CLONE.SH - Clone App Repositories
# =============================================================================
# Clones (or updates) all repos listed in REPOS into PROJECT_ROOT/apps.
# Edit the REPOS array below to set repo URLs and optional branch per line.
#
# Usage: ./clone.sh [options]
#
# Options:
#   -b, --branch      Default branch when not specified per repo (default: main)
# =============================================================================

set -e

BRANCH="main"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$PROJECT_ROOT/apps"

# CUSTOMIZE: "repo_url" "branch" (one per line). Branch optional; uses -b default if omitted.
REPOS=(
    "https://github.com/your-org/laravel-app.git main"
    "https://github.com/your-org/nestjs-app.git main"
    "https://github.com/your-org/react-app.git main"
    "https://github.com/your-org/next-app.git main"
)

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--branch) BRANCH="$2"; shift 2 ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$APPS_DIR"

for entry in "${REPOS[@]}"; do
    read -r repo_url branch <<< "$entry"
    branch=${branch:-$BRANCH}
    name=$(basename "${repo_url%.git}")
    repo_dir="$APPS_DIR/$name"

    if [[ -d "$repo_dir" ]]; then
        echo "Updating $name..."
        git -C "$repo_dir" fetch
        git -C "$repo_dir" pull
    else
        echo "Cloning $name..."
        git clone --branch "$branch" "$repo_url" "$repo_dir" 2>/dev/null || {
            echo "Error: Failed to clone $name"
            exit 1
        }
    fi
done

echo "Done!"
