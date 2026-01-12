#!/bin/bash
set -e

# =============================================================================
# CLONE.SH - Clone App Repositories
# =============================================================================
# Usage: ./clone.sh [options]
# Options:
#   -a, --app         Clone specific app (laravel|nestjs|react|next)
#   -b, --branch      Branch to clone (default: main)
#   -h, --help        Show this help message
# =============================================================================

# Default values
APP=""
BRANCH="main"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$PROJECT_ROOT/apps"

# CUSTOMIZE THESE FOR YOUR PROJECT
declare -A APP_REPOS=(
    ["laravel"]="https://github.com/your-org/laravel-app.git"
    ["nestjs"]="https://github.com/your-org/nestjs-app.git"
    ["react"]="https://github.com/your-org/react-app.git"
    ["next"]="https://github.com/your-org/next-app.git"
)

show_help() {
    cat << EOF
Usage: ./clone.sh [options]

Options:
  -a, --app       Clone specific app (laravel|nestjs|react|next)
  -b, --branch    Branch to clone (default: main)
  -h, --help      Show this help message

Examples:
  ./clone.sh                    # Clone all apps
  ./clone.sh -a laravel         # Clone only Laravel app
  ./clone.sh -b develop         # Clone all apps from develop branch
EOF
}

clone_app() {
    local app=$1
    local repo_url="${APP_REPOS[$app]}"
    local app_dir="$APPS_DIR/$app"

    [[ -z "$repo_url" ]] && echo "Error: Unknown app: $app" && return 1

    if [[ -d "$app_dir" ]]; then
        echo "Updating $app..."
        git -C "$app_dir" fetch
        git -C "$app_dir" pull
    else
        echo "Cloning $app..."
        git clone --branch "$BRANCH" "$repo_url" "$app_dir" 2>/dev/null || {
            echo "Error: Failed to clone $app"
            return 1
        }
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app) APP="$2"; shift 2 ;;
        -b|--branch) BRANCH="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Error: Unknown option: $1"; show_help; exit 1 ;;
    esac
done

mkdir -p "$APPS_DIR"

if [[ -n "$APP" ]]; then
    clone_app "$APP"
else
    for app in "${!APP_REPOS[@]}"; do
        clone_app "$app"
    done
fi

echo "Done!"
