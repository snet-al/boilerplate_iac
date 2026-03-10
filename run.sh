#!/bin/bash
# =============================================================================
# RUN.SH - Local Development Runner
# =============================================================================
# Starts services with docker-compose.dev.yaml. Use -a to run specific apps only.
#
# Usage: ./run.sh [options]
#
# Options:
#   -a, --apps        Comma-separated list of apps to run (default: all)
#   -b, --build       Force rebuild and recreate containers
# =============================================================================

set -e

APPS=""
BUILD=""
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="docker-compose.dev.yaml"
[[ ! -f "$PROJECT_ROOT/$COMPOSE_FILE" ]] && echo "Error: Compose file not found: $COMPOSE_FILE" && exit 1
COMPOSE_CMD="docker-compose -f $PROJECT_ROOT/$COMPOSE_FILE"
AVAILABLE_APPS=("mongo" "redis" "mysql" "postgres" "laravel" "nestjs" "react" "next" "nginx")

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--apps) APPS="$2"; shift 2 ;;
        -b|--build) BUILD="--build --force-recreate"; shift ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -n "$APPS" ]]; then
    IFS=',' read -ra APP_ARRAY <<< "$APPS"
    echo "Apps: ${APP_ARRAY[*]}"
    
    for app in "${APP_ARRAY[@]}"; do
        [[ ! " ${AVAILABLE_APPS[*]} " =~ " ${app} " ]] && echo "Warning: App '$app' may not be defined"
    done
    
    COMPOSE_CMD="$COMPOSE_CMD up $BUILD ${APP_ARRAY[*]}"
else
    echo "Starting all apps"
    COMPOSE_CMD="$COMPOSE_CMD up $BUILD"
fi

echo "Executing: $COMPOSE_CMD"
eval $COMPOSE_CMD

echo "Done!"
