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

show_help() {
    cat << EOF
Usage: ./deploy-primary.sh [options]

Options:
  -c, --client      Client name (folder inside env/) - REQUIRED
  -a, --apps        Comma-separated apps to deploy
                    Use db/databases for all primary databases
                    Use apps for all application services
  -h, --help        Show this help message

Examples:
  ./deploy-primary.sh -c acme-corp
  ./deploy-primary.sh -c acme-corp -a mysql
  ./deploy-primary.sh -c acme-corp -a db
  ./deploy-primary.sh -c acme-corp -a apps,nginx
EOF
}

copy_env_file() {
    local app=$1
    local env_file="" dest_file=""

    case $app in
        mongo) env_file=".env.db.mongo"; dest_file=".env.mongo" ;;
        redis) env_file=".env.db.redis"; dest_file=".env.redis" ;;
        mysql) env_file=".env.db.mysql"; dest_file=".env.mysql" ;;
        postgres) env_file=".env.db.postgres"; dest_file=".env.postgres" ;;
        laravel) env_file=".env.back.laravel"; dest_file=".env.laravel" ;;
        nestjs) env_file=".env.back.nestjs"; dest_file=".env.nestjs" ;;
        react) env_file=".env.front.react"; dest_file=".env.react" ;;
        next) env_file=".env.front.next"; dest_file=".env.next" ;;
    esac

    [[ -z "$env_file" ]] && return

    local source_path="$CLIENT_ENV_DIR/$env_file"
    local dest_path="$DEPLOY_DIR/$CLIENT/$dest_file"

    if [[ -f "$source_path" ]]; then
        cp "$source_path" "$dest_path"
        echo "Copied env for $app"
    fi
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

    if [[ -n "$APPS" ]]; then
        IFS=',' read -ra APP_ARRAY <<< "$APPS"

        for requested_app in "${APP_ARRAY[@]}"; do
            requested_app="${requested_app// /}"
            [[ -z "$requested_app" ]] && continue

            while IFS= read -r expanded_app; do
                [[ -z "$expanded_app" ]] && continue

                app_key="$(normalize_app_name "$expanded_app")"
                copy_env_file "$app_key"
                services_to_deploy+=("$(resolve_service_name "$expanded_app")")
            done < <(expand_requested_app "$requested_app")
        done

        [[ ${#services_to_deploy[@]} -eq 0 ]] && echo "Error: No valid apps provided" && exit 1

        echo "Starting services: ${services_to_deploy[*]}"
        docker-compose "${compose_args[@]}" up -d "${services_to_deploy[@]}"
    else
        for app in mongo redis mysql postgres laravel nestjs react next; do
            copy_env_file "$app"
        done

        docker-compose "${compose_args[@]}" up -d
    fi

    docker-compose "${compose_args[@]}" ps
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client) CLIENT="$2"; shift 2 ;;
        -a|--apps) APPS="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Error: Unknown option: $1"; show_help; exit 1 ;;
    esac
done

[[ -z "$CLIENT" ]] && echo "Error: Client required (-c)" && exit 1

CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
[[ ! -d "$CLIENT_ENV_DIR" ]] && echo "Error: Client not found: $CLIENT" && exit 1

echo "Deploying $CLIENT -> $SITE"
mkdir -p "$DEPLOY_DIR/$CLIENT"

deploy

echo "Done! Run ./monitor.sh -s $SITE to check status"
