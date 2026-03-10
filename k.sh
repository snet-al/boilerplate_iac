#!/bin/bash
# =============================================================================
# K.SH - Kubernetes Deployment
# =============================================================================
# Deploys a client (env/<client>) to Kubernetes: creates secrets directly from
# client env files and applies k8s manifests. For Docker Compose use deploy.sh.
#
# Usage: ./k.sh -c <client> [options]
#
# Options:
#   -c, --client      Client name (folder inside env/) - required
#   -s, --site        Site: primary|secondary (default: primary)
#   -n, --namespace   Kubernetes namespace (default: default)
# =============================================================================

set -e

CLIENT=""
SITE="primary"
K8S_NAMESPACE="default"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client) CLIENT="$2"; shift 2 ;;
        -s|--site) SITE="$2"; shift 2 ;;
        -n|--namespace) K8S_NAMESPACE="$2"; shift 2 ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$CLIENT" ]] && echo "Error: Client required (-c)" && exit 1

CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
if [[ ! -d "$CLIENT_ENV_DIR" ]]; then
    CLIENT_ENV_DIR="$ENV_DIR/client"
    [[ ! -d "$CLIENT_ENV_DIR" ]] && echo "Error: Client not found: $CLIENT and fallback env/client is missing" && exit 1
    echo "Client '$CLIENT' not found, using fallback: env/client"
fi

k8s_dir="$PROJECT_ROOT/k8s"
[[ ! -d "$k8s_dir" ]] && echo "Error: k8s directory not found" && exit 1

echo "Deploying $CLIENT to k8s namespace: $K8S_NAMESPACE"

kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating secrets..."
for app in mongo redis mysql postgres laravel nestjs react next; do
    env_file=""
    case $app in
        mongo) env_file=".env.db.mongo" ;;
        redis) env_file=".env.db.redis" ;;
        mysql) env_file=".env.db.mysql" ;;
        postgres) env_file=".env.db.postgres" ;;
        laravel) env_file=".env.back.laravel" ;;
        nestjs) env_file=".env.back.nestjs" ;;
        react) env_file=".env.front.react" ;;
        next) env_file=".env.front.next" ;;
    esac
    [[ -z "$env_file" ]] && continue
    env_path="$CLIENT_ENV_DIR/$env_file"
    [[ ! -f "$env_path" ]] && continue
    secret_name="${CLIENT}-${app}-secrets"
    kubectl create secret generic "$secret_name" \
        --from-env-file="$env_path" \
        --namespace="$K8S_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created secret: $secret_name"
done

echo "Applying manifests..."
for dir in namespaces configmaps secrets services deployments statefulsets ingress; do
    [[ ! -d "$k8s_dir/$dir" ]] && continue
    kubectl apply -f "$k8s_dir/$dir" -n "$K8S_NAMESPACE" || true
done

site_dir="$k8s_dir/targets/$SITE"
if [[ -d "$site_dir" ]]; then
    echo "Applying $SITE configs..."
    kubectl apply -f "$site_dir" -n "$K8S_NAMESPACE"
fi

echo ""
kubectl get pods -n "$K8S_NAMESPACE"
kubectl get services -n "$K8S_NAMESPACE"

echo "Done!"
