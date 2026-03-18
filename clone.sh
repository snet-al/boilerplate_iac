#!/bin/bash
set -e

# =============================================================================
# CLONE.SH - Clone App Repositories
# =============================================================================
# Usage: ./clone.sh [-a app]
# Folder name and branch are derived from each REPOS entry.
# =============================================================================

APP=""
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$PROJECT_ROOT/apps"

# url:branch (folder name derived from repo URL)
REPOS=(
    "https://github.com/your-org/laravel-app.git:main"
    "https://github.com/your-org/nestjs-app.git:main"
    "https://github.com/your-org/react-app.git:main"
    "https://github.com/your-org/next-app.git:main"
)

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app) APP="$2"; shift 2 ;;
        -h|--help) echo "Usage: ./clone.sh [-a app]"; exit 0 ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$APPS_DIR"

for entry in "${REPOS[@]}"; do
    IFS=':' read -r url branch <<< "$entry"
    name=$(basename "$url" .git)
    dir="$APPS_DIR/$name"

    [[ -n "$APP" && "$name" != "$APP" ]] && continue

    if [[ -d "$dir" ]]; then
        echo "Updating $name..."
        git -C "$dir" fetch
        git -C "$dir" pull
    else
        echo "Cloning $name ($branch)..."
        git clone --branch "$branch" "$url" "$dir" 2>/dev/null || {
            echo "Error: Failed to clone $name"
            continue
        }
    fi
done

echo "Done!"
