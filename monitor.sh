#!/bin/bash
# =============================================================================
# MONITOR.SH - Health Check & Monitoring
# =============================================================================
# Shows Docker Compose or Kubernetes status. Use -w to wait until healthy.
#
# Usage: ./monitor.sh [options]
#
# Options:
#   -k, --k8s         Monitor Kubernetes instead of Docker Compose
#   -n, --namespace   Kubernetes namespace (default: default)
#   -s, --site        Docker Compose site: primary|secondary (default: primary)
#   -w, --wait        Wait for healthy status (retries until timeout)
# =============================================================================

set -e

K8S=false
K8S_NAMESPACE="default"
SITE="primary"
WAIT_MODE=false
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--k8s) K8S=true; shift ;;
        -n|--namespace) K8S_NAMESPACE="$2"; shift 2 ;;
        -s|--site) SITE="$2"; shift 2 ;;
        -w|--wait) WAIT_MODE=true; shift ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "$WAIT_MODE" == true ]]; then
    max_attempts=30
    attempt=1
    echo "Waiting for healthy status..."
    while [[ $attempt -le $max_attempts ]]; do
        echo "Attempt $attempt/$max_attempts"
        if [[ "$K8S" == true ]]; then
            ready=$(kubectl get pods -n "$K8S_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            total=$(kubectl get pods -n "$K8S_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            echo "Pods: $ready/$total running"
            if [[ "$ready" -eq "$total" && "$total" -gt 0 ]]; then
                echo "All pods healthy!"
                exit 0
            fi
        else
            compose_file="$PROJECT_ROOT/docker-compose.${SITE}.yaml"
            [[ ! -f "$compose_file" ]] && echo "Error: Compose file not found: $compose_file" && exit 1
            healthy=$(docker-compose -f "$compose_file" ps --services --filter "status=running" 2>/dev/null | wc -l | tr -d ' ')
            echo "Containers running: $healthy"
            if [[ "$healthy" -gt 0 ]]; then
                echo "Apps healthy!"
                exit 0
            fi
        fi
        sleep 10
        ((attempt++))
    done
    echo "Timeout reached"
    exit 1
fi

if [[ "$K8S" == true ]]; then
    echo "Kubernetes status (namespace: $K8S_NAMESPACE):"
    echo ""
    echo "Pods:"
    kubectl get pods -n "$K8S_NAMESPACE"
    echo ""
    echo "Services:"
    kubectl get services -n "$K8S_NAMESPACE"
else
    compose_file="$PROJECT_ROOT/docker-compose.${SITE}.yaml"
    [[ ! -f "$compose_file" ]] && echo "Error: Compose file not found: $compose_file" && exit 1
    echo "Docker Compose status ($SITE):"
    docker-compose -f "$compose_file" ps
fi
