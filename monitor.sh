#!/bin/bash
set -e

# =============================================================================
# MONITOR.SH - Health Check & Monitoring
# =============================================================================
# Usage: ./monitor.sh [-k] [-n namespace] [-s site]
# =============================================================================

K8S=false
K8S_NAMESPACE="default"
SITE="primary"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_MODE=false

check_docker() {
    local compose_file="$PROJECT_ROOT/docker-compose.${SITE}.yaml"
    
    [[ ! -f "$compose_file" ]] && echo "Error: Compose file not found: $compose_file" && exit 1
    
    echo "Docker Compose status ($SITE):"
    docker-compose -f "$compose_file" ps
}

check_k8s() {
    echo "Kubernetes status (namespace: $K8S_NAMESPACE):"
    echo ""
    echo "Pods:"
    kubectl get pods -n "$K8S_NAMESPACE"
    echo ""
    echo "Services:"
    kubectl get services -n "$K8S_NAMESPACE"
}

wait_healthy() {
    local max_attempts=30 attempt=1
    
    echo "Waiting for healthy status..."
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "Attempt $attempt/$max_attempts"
        
        if [[ "$K8S" == true ]]; then
            local ready=$(kubectl get pods -n "$K8S_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            local total=$(kubectl get pods -n "$K8S_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            
            echo "Pods: $ready/$total running"
            
            if [[ "$ready" -eq "$total" && "$total" -gt 0 ]]; then
                echo "All pods healthy!"
                return 0
            fi
        else
            local compose_file="$PROJECT_ROOT/docker-compose.${SITE}.yaml"
            local healthy=$(docker-compose -f "$compose_file" ps --services --filter "status=running" 2>/dev/null | wc -l | tr -d ' ')
            
            echo "Containers running: $healthy"
            
            if [[ "$healthy" -gt 0 ]]; then
                echo "Apps healthy!"
                return 0
            fi
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo "Timeout reached"
    return 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--k8s) K8S=true; shift ;;
        -n|--namespace) K8S_NAMESPACE="$2"; shift 2 ;;
        -s|--site) SITE="$2"; shift 2 ;;
        -w|--wait) WAIT_MODE=true; shift ;;
        -h|--help) echo "Usage: ./monitor.sh [-k] [-n namespace] [-s site] [-w]"; exit 0 ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "$WAIT_MODE" == true ]]; then
    wait_healthy
else
    if [[ "$K8S" == true ]]; then
        check_k8s
    else
        check_docker
    fi
fi
