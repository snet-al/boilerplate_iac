#!/bin/bash
set -e

# =============================================================================
# DEPLOY.SH - Docker Compose Deployment
# =============================================================================
# Usage: ./deploy.sh -c <client> [-s site] [-a apps]
# For Kubernetes: use ./k.sh instead
# =============================================================================

CLIENT=""
SITE="primary"
APPS=""
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"
DEPLOY_DIR="$PROJECT_ROOT/.deploy"

show_help() {
    cat << EOF
          Usage: ./deploy.sh [options]

          Options:
            -c, --client      Client name (folder inside env/) - REQUIRED
            -s, --site        Deployment site (primary|secondary) - default: primary
            -a, --apps        Comma-separated list of apps to deploy
            -h, --help        Show this help message

          Examples:
            ./deploy.sh -c acme-corp                          # Deploy all apps
            ./deploy.sh -c acme-corp -s secondary             # Deploy to secondary site
            ./deploy.sh -c acme-corp -a laravel,mysql,redis   # Deploy specific apps

          For Kubernetes deployment, use: ./k.sh -c <client> -n <namespace>
          For monitoring, use: ./monitor.sh
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

deploy() {
    local compose_file="docker-compose.${SITE}.yaml"
    
    [[ ! -f "$PROJECT_ROOT/$compose_file" ]] && echo "Error: $compose_file not found" && exit 1
    
    export COMPOSE_PROJECT_NAME="${CLIENT}-${SITE}"
    export ENV_DIR="$DEPLOY_DIR/$CLIENT"
    
    local compose_cmd="docker-compose -f $PROJECT_ROOT/$compose_file"
    local apps_to_deploy=""
    
    if [[ -n "$APPS" ]]; then
        IFS=',' read -ra APP_ARRAY <<< "$APPS"
        apps_to_deploy="${APP_ARRAY[*]}"
        for app in $apps_to_deploy; do copy_env_file "$app"; done
    else
        for app in mongo redis mysql postgres laravel nestjs react next; do
            copy_env_file "$app"
        done
    fi
    
    eval "$compose_cmd up -d $apps_to_deploy"
    
    eval "$compose_cmd ps"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client) CLIENT="$2"; shift 2 ;;
        -s|--site) SITE="$2"; shift 2 ;;
        -a|--apps) APPS="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Error: Unknown option: $1"; show_help; exit 1 ;;
    esac
done

[[ -z "$CLIENT" ]] && echo "Error: Client required (-c)" && exit 1

CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
[[ ! -d "$CLIENT_ENV_DIR" ]] && echo "Error: Client not found: $CLIENT" && exit 1
[[ "$SITE" != "primary" && "$SITE" != "secondary" ]] && echo "Error: Invalid site" && exit 1

echo "Deploying $CLIENT -> $SITE"
mkdir -p "$DEPLOY_DIR/$CLIENT"

deploy

echo "Done! Run ./monitor.sh -s $SITE to check status"
