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
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AVAILABLE_APPS=("mongo" "redis" "mysql" "postgres" "laravel" "nestjs" "react" "next" "nginx")

show_help() {
    cat << EOF
Usage: ./run.sh [options]

Options:
  -a, --apps        Comma-separated list of apps to run
                    Available: ${AVAILABLE_APPS[*]}
  -b, --build       Force rebuild images
  -h, --help        Show this help message

Examples:
  ./run.sh                                    # Run all apps
  ./run.sh -a laravel,mysql,redis             # Run specific apps
  ./run.sh -a nestjs,postgres -b              # Run with forced rebuild
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--apps) APPS="$2"; shift 2 ;;
        -b|--build) BUILD="--build"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Error: Unknown option: $1"; show_help; exit 1 ;;
    esac
done

COMPOSE_FILE="docker-compose.dev.yaml"
[[ ! -f "$PROJECT_ROOT/$COMPOSE_FILE" ]] && echo "Error: Compose file not found: $COMPOSE_FILE" && exit 1

echo "Starting apps (file: $COMPOSE_FILE)"

COMPOSE_CMD="docker-compose -f $PROJECT_ROOT/$COMPOSE_FILE"

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
