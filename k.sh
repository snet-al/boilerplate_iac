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
            return
        fi
    done
}

deploy() {
    local k8s_dir="$PROJECT_ROOT/k8s"
    
    [[ ! -d "$k8s_dir" ]] && echo "Error: k8s directory not found" && exit 1
    
    kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "Creating secrets..."
    for entry in "${ENV_FILES[@]}"; do
        IFS=':' read -r app _ _ <<< "$entry"
        copy_env "$app"
        
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
        -h|--help) echo "Usage: ./k.sh -c <client> [-s site] [-n namespace]"; exit 0 ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$CLIENT" ]] && echo "Error: Client required (-c)" && exit 1

CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
[[ ! -d "$CLIENT_ENV_DIR" ]] && echo "Error: Client not found: $CLIENT" && exit 1

echo "Deploying $CLIENT to k8s namespace: $K8S_NAMESPACE"
mkdir -p "$DEPLOY_DIR/$CLIENT"

deploy

echo "Done!"
