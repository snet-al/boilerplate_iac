#!/bin/bash
set -e

# =============================================================================
# K.SH - Kubernetes Deployment
# =============================================================================
# Usage: ./k.sh -c <client> [-s site] [-n namespace]
# =============================================================================

CLIENT=""
SITE="primary"
K8S_NAMESPACE="default"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"
DEPLOY_DIR="$PROJECT_ROOT/.deploy"


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
    
    [[ ! -f "$source_path" ]] && return
    
    cp "$source_path" "$dest_path"
}

deploy() {
    local k8s_dir="$PROJECT_ROOT/k8s"
    
    [[ ! -d "$k8s_dir" ]] && echo "Error: k8s directory not found" && exit 1
    
    kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "Creating secrets..."
    for app in mongo redis mysql postgres laravel nestjs react next; do
        copy_env_file "$app"
        
        local env_file="$DEPLOY_DIR/$CLIENT/.env.$app"
        [[ ! -f "$env_file" ]] && continue
        
        local secret_name="${CLIENT}-${app}-secrets"
        
        kubectl create secret generic "$secret_name" \
            --from-env-file="$env_file" \
            --namespace="$K8S_NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo "Created secret: $secret_name"
    done
    
    echo "Applying manifests..."
    for dir in namespaces configmaps secrets services deployments statefulsets ingress; do
        [[ ! -d "$k8s_dir/$dir" ]] && continue
        
        kubectl apply -f "$k8s_dir/$dir" -n "$K8S_NAMESPACE" || true
    done
    
    local site_dir="$k8s_dir/targets/$SITE"
    if [[ -d "$site_dir" ]]; then
        echo "Applying $SITE configs..."
        kubectl apply -f "$site_dir" -n "$K8S_NAMESPACE"
    fi
    
    echo ""
    kubectl get pods -n "$K8S_NAMESPACE"
    kubectl get services -n "$K8S_NAMESPACE"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client) CLIENT="$2"; shift 2 ;;
        -s|--site) SITE="$2"; shift 2 ;;
        -n|--namespace) K8S_NAMESPACE="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Error: Unknown option: $1"; show_help; exit 1 ;;
    esac
done

[[ -z "$CLIENT" ]] && echo "Error: Client required (-c)" && exit 1

CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
[[ ! -d "$CLIENT_ENV_DIR" ]] && echo "Error: Client not found: $CLIENT" && exit 1

echo "Deploying $CLIENT to k8s namespace: $K8S_NAMESPACE"
mkdir -p "$DEPLOY_DIR/$CLIENT"

deploy

echo "Done!"
