#!/bin/bash
set -e

# =============================================================================
# RUN.SH - Local Development Runner
# =============================================================================
# Usage: ./run.sh [options]
# Options:
#   -a, --apps        Comma-separated list of apps to run
#   -b, --build       Force rebuild images
#   -h, --help        Show this help message
# =============================================================================

APPS=""
BUILD=""
APP_ARRAY=()
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="docker-compose.dev.yaml"
[[ ! -f "$PROJECT_ROOT/$COMPOSE_FILE" ]] && echo "Error: Compose file not found: $COMPOSE_FILE" && exit 1
COMPOSE_CMD="docker-compose -f $PROJECT_ROOT/$COMPOSE_FILE"
AVAILABLE_APPS=("mongo" "redis" "mysql" "postgres" "laravel" "nestjs" "react" "next" "nginx")

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--apps) APPS="$2"; shift 2 ;;
        -b|--build) BUILD="--build --force-recreate"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Error: Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [[ -n "$APPS" ]]; then
    IFS=',' read -ra APP_ARRAY <<< "$APPS"
fi

COMPOSE_CMD="$COMPOSE_CMD up $BUILD ${APP_ARRAY[*]}"

eval $COMPOSE_CMD

echo "Done!"
