#!/bin/bash
set -e

# =============================================================================
# DEPLOY-SECONDARY.SH - Secondary Site Deployment
# =============================================================================
# Usage: ./deploy-secondary.sh -c <client> [-a apps]
# Default behavior deploys only app services, not nginx or replica DBs.
# Use -a db to deploy only the replica database services.
# =============================================================================

CLIENT=""
APPS=""
SITE="secondary"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"
DEPLOY_DIR="$PROJECT_ROOT/.deploy"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.secondary.yaml"
DEFAULT_SERVICES=(laravel nestjs react next)

# app:source:destination
ENV_FILES=(
    "mongo:.env.db.mongo:.env.mongo"
    "redis:.env.db.redis:.env.redis"
    "mysql:.env.db.mysql:.env.mysql"
    "postgres:.env.db.postgres:.env.postgres"
    "laravel:.env.back.laravel:.env.laravel"
    "nestjs:.env.back.nestjs:.env.nestjs"
    "react:.env.front.react:.env.react"
    "next:.env.front.next:.env.next"
)

copy_env() {
    local target=$1
    for entry in "${ENV_FILES[@]}"; do
        IFS=':' read -r app src dst <<< "$entry"
        if [[ "$app" == "$target" && -f "$CLIENT_ENV_DIR/$src" ]]; then
            cp "$CLIENT_ENV_DIR/$src" "$DEPLOY_DIR/$CLIENT/$dst"
            echo "Copied $src"
            return
        fi
    done
}

normalize_app_name() {
    case $1 in
        mongo-primary|mongo-secondary) echo "mongo" ;;
        redis-primary|redis-secondary) echo "redis" ;;
        mysql-primary|mysql-secondary) echo "mysql" ;;
        postgres-primary|postgres-secondary) echo "postgres" ;;
        *) echo "$1" ;;
    esac
}

expand_requested_app() {
    case $1 in
        db|database|databases|slave-db|replica-db)
            printf '%s\n' mongo redis mysql postgres
            ;;
        apps)
            printf '%s\n' laravel nestjs react next
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

resolve_service_name() {
    local normalized_app
    normalized_app="$(normalize_app_name "$1")"

    case $normalized_app in
        mongo|redis|mysql|postgres) echo "${normalized_app}-${SITE}" ;;
        *) echo "$1" ;;
    esac
}

is_database_service() {
    case $1 in
        mongo-secondary|redis-secondary|mysql-secondary|postgres-secondary) return 0 ;;
        *) return 1 ;;
    esac
}

validate_service_name() {
    local service_name=$1

    if [[ "$service_name" == "nginx" ]]; then
        echo "Error: nginx is not deployed from deploy-secondary.sh"
        exit 1
    fi
}

deploy() {
    [[ ! -f "$COMPOSE_FILE" ]] && echo "Error: Compose file not found: $COMPOSE_FILE" && exit 1

    export COMPOSE_PROJECT_NAME="${CLIENT}-${SITE}"
    export ENV_DIR="$DEPLOY_DIR/$CLIENT"

    local compose_args=(-f "$COMPOSE_FILE")
    local requested_app=""
    local expanded_app=""
    local app_key=""
    local services_to_deploy=()
    local has_database_service=false

    if [[ -n "$APPS" ]]; then
        IFS=',' read -ra APP_ARRAY <<< "$APPS"

        for requested_app in "${APP_ARRAY[@]}"; do
            requested_app="${requested_app// /}"
            [[ -z "$requested_app" ]] && continue

            while IFS= read -r expanded_app; do
                [[ -z "$expanded_app" ]] && continue

                app_key="$(normalize_app_name "$expanded_app")"
                local resolved_service
                resolved_service="$(resolve_service_name "$expanded_app")"

                validate_service_name "$resolved_service"
                copy_env "$app_key"
                services_to_deploy+=("$resolved_service")

                if is_database_service "$resolved_service"; then
                    has_database_service=true
                fi
            done < <(expand_requested_app "$requested_app")
        done
    else
        local app=""
        for app in "${DEFAULT_SERVICES[@]}"; do
            copy_env "$app"
            services_to_deploy+=("$app")
        done
    fi

    [[ ${#services_to_deploy[@]} -eq 0 ]] && echo "Error: No valid apps provided" && exit 1

    echo "Starting services: ${services_to_deploy[*]}"

    # Secondary defaults to app-only deploys. Avoid auto-starting replica DB deps unless explicitly requested.
    if [[ "$has_database_service" == true ]]; then
        docker-compose "${compose_args[@]}" up -d "${services_to_deploy[@]}"
    else
        docker-compose "${compose_args[@]}" up -d --no-deps "${services_to_deploy[@]}"
    fi

    docker-compose "${compose_args[@]}" ps
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client) CLIENT="$2"; shift 2 ;;
        -a|--apps) APPS="$2"; shift 2 ;;
        -h|--help) echo "Usage: ./deploy-secondary.sh -c <client> [-a apps]"; exit 0 ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$CLIENT" ]] && echo "Error: Client required (-c)" && exit 1

CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
[[ ! -d "$CLIENT_ENV_DIR" ]] && echo "Error: Client not found: $CLIENT" && exit 1

echo "Deploying $CLIENT -> $SITE"
mkdir -p "$DEPLOY_DIR/$CLIENT"

deploy

echo "Done! Run ./monitor.sh -s $SITE to check status"
