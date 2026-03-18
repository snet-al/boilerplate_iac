#!/bin/bash
set -e

# =============================================================================
# DEPLOY-PRIMARY.SH - Primary Site Deployment
# =============================================================================
# Usage: ./deploy-primary.sh -c <client> [-a apps]
# =============================================================================

CLIENT=""
APPS=""
SITE="primary"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"
DEPLOY_DIR="$PROJECT_ROOT/.deploy"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.primary.yaml"

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
        db|database|databases)
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

deploy() {
    [[ ! -f "$COMPOSE_FILE" ]] && echo "Error: Compose file not found: $COMPOSE_FILE" && exit 1

    export COMPOSE_PROJECT_NAME="${CLIENT}-${SITE}"
    export ENV_DIR="$DEPLOY_DIR/$CLIENT"

    local compose_args=(-f "$COMPOSE_FILE")
    local requested_app=""
    local expanded_app=""
    local app_key=""
    local services_to_deploy=()
    local deploying_postgres=false

    if [[ -n "$APPS" ]]; then
        IFS=',' read -ra APP_ARRAY <<< "$APPS"

        for requested_app in "${APP_ARRAY[@]}"; do
            requested_app="${requested_app// /}"
            [[ -z "$requested_app" ]] && continue

            while IFS= read -r expanded_app; do
                [[ -z "$expanded_app" ]] && continue

                app_key="$(normalize_app_name "$expanded_app")"
                copy_env "$app_key"
                services_to_deploy+=("$(resolve_service_name "$expanded_app")")
            done < <(expand_requested_app "$requested_app")
        done

        [[ ${#services_to_deploy[@]} -eq 0 ]] && echo "Error: No valid apps provided" && exit 1

        for svc in "${services_to_deploy[@]}"; do
            [[ "$svc" == "postgres-primary" ]] && deploying_postgres=true
        done

        echo "Starting services: ${services_to_deploy[*]}"
        docker-compose "${compose_args[@]}" up -d "${services_to_deploy[@]}"
    else
        for entry in "${ENV_FILES[@]}"; do
            IFS=':' read -r app _ _ <<< "$entry"
            copy_env "$app"
        done

        deploying_postgres=true
        docker-compose "${compose_args[@]}" up -d
    fi

    if [[ "$deploying_postgres" == true ]]; then
        "$PROJECT_ROOT/docker/postgres/primary/ensure-replication-user.sh" \
            "$DEPLOY_DIR/$CLIENT/.env.postgres" "${compose_args[@]}"
    fi

    docker-compose "${compose_args[@]}" ps
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client) CLIENT="$2"; shift 2 ;;
        -a|--apps) APPS="$2"; shift 2 ;;
        -h|--help) echo "Usage: ./deploy-primary.sh -c <client> [-a apps]"; exit 0 ;;
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
