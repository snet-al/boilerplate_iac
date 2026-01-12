#!/bin/bash

set -e

# =============================================================================
# DEPLOY.SH - Production Deployment Script with Client Support
# =============================================================================
# Usage: ./deploy.sh [options]
# Options:
#   -c, --client      Client name (folder inside env/) - REQUIRED
#   -t, --target      Deployment target (primary|secondary) - default: primary
#   -e, --env         Environment (dev|prod) - default: prod
#   -s, --services    Comma-separated list of services to deploy
#   -k, --k8s         Deploy to Kubernetes instead of Docker Compose
#   -n, --namespace   Kubernetes namespace - default: default
#   --dry-run         Show what would be done without executing
#   -h, --help        Show this help message
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
CLIENT=""
TARGET="primary"
ENVIRONMENT="prod"
SERVICES=""
DEPLOY_K8S=false
K8S_NAMESPACE="default"
DRY_RUN=false
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"
DEPLOY_DIR="$PROJECT_ROOT/.deploy"

# Available services grouped by type
declare -A SERVICE_GROUPS=(
    ["databases"]="mongo redis mysql postgres"
    ["backends"]="laravel nestjs"
    ["frontends"]="react next"
    ["infrastructure"]="nginx"
)

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Function to show help
show_help() {
    cat << EOF
Usage: ./deploy.sh [options]

Options:
  -c, --client      Client name (folder inside env/) - REQUIRED
  -t, --target      Deployment target (primary|secondary) - default: primary
  -e, --env         Environment (dev|prod) - default: prod
  -s, --services    Comma-separated list of services to deploy
  -k, --k8s         Deploy to Kubernetes instead of Docker Compose
  -n, --namespace   Kubernetes namespace - default: default
  --dry-run         Show what would be done without executing
  -h, --help        Show this help message

Available Clients:
$(ls -1 "$ENV_DIR" 2>/dev/null | grep -v "^example$" | sed 's/^/  - /')

Service Groups:
  databases:      ${SERVICE_GROUPS[databases]}
  backends:       ${SERVICE_GROUPS[backends]}
  frontends:      ${SERVICE_GROUPS[frontends]}
  infrastructure: ${SERVICE_GROUPS[infrastructure]}

Examples:
  ./deploy.sh -c acme-corp                          # Deploy all services for acme-corp
  ./deploy.sh -c acme-corp -t secondary             # Deploy to secondary site (replica)
  ./deploy.sh -c acme-corp -s laravel,mysql,redis   # Deploy specific services
  ./deploy.sh -c acme-corp -k -n production         # Deploy to Kubernetes
  ./deploy.sh -c acme-corp --dry-run                # Preview deployment

Directory Structure Expected:
  env/
  └── <client>/
      ├── .env.back.laravel
      ├── .env.back.nestjs
      ├── .env.front.react
      ├── .env.front.next
      ├── .env.db.mongo
      ├── .env.db.mysql
      ├── .env.db.postgres
      └── .env.db.redis

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client)
            CLIENT="$2"
            shift 2
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--services)
            SERVICES="$2"
            shift 2
            ;;
        -k|--k8s)
            DEPLOY_K8S=true
            shift
            ;;
        -n|--namespace)
            K8S_NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CLIENT" ]]; then
    print_error "Client name is required. Use -c or --client option."
    show_help
    exit 1
fi

# Validate client exists
CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
if [[ ! -d "$CLIENT_ENV_DIR" ]]; then
    print_error "Client directory not found: $CLIENT_ENV_DIR"
    print_info "Available clients:"
    ls -1 "$ENV_DIR" 2>/dev/null | grep -v "^example$" | sed 's/^/  - /'
    exit 1
fi

# Validate target
if [[ "$TARGET" != "primary" && "$TARGET" != "secondary" ]]; then
    print_error "Invalid target: $TARGET. Use 'primary' or 'secondary'"
    exit 1
fi

# Validate environment
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    print_error "Invalid environment: $ENVIRONMENT. Use 'dev' or 'prod'"
    exit 1
fi

print_info "=========================================="
print_info "Deployment Configuration"
print_info "=========================================="
print_info "Client:      $CLIENT"
print_info "Target:      $TARGET"
print_info "Environment: $ENVIRONMENT"
print_info "K8s Deploy:  $DEPLOY_K8S"
print_info "Dry Run:     $DRY_RUN"
print_info "=========================================="

# Create deployment directory
if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$DEPLOY_DIR/$CLIENT"
fi

# Function to copy and process env files
copy_env_files() {
    local service=$1
    local env_file=""
    local dest_file=""
    
    case $service in
        mongo)
            env_file=".env.db.mongo"
            dest_file=".env.mongo"
            ;;
        redis)
            env_file=".env.db.redis"
            dest_file=".env.redis"
            ;;
        mysql)
            env_file=".env.db.mysql"
            dest_file=".env.mysql"
            ;;
        postgres)
            env_file=".env.db.postgres"
            dest_file=".env.postgres"
            ;;
        laravel)
            env_file=".env.back.laravel"
            dest_file=".env.laravel"
            ;;
        nestjs)
            env_file=".env.back.nestjs"
            dest_file=".env.nestjs"
            ;;
        react)
            env_file=".env.front.react"
            dest_file=".env.react"
            ;;
        next)
            env_file=".env.front.next"
            dest_file=".env.next"
            ;;
    esac
    
    if [[ -n "$env_file" ]]; then
        local source_path="$CLIENT_ENV_DIR/$env_file"
        local dest_path="$DEPLOY_DIR/$CLIENT/$dest_file"
        
        if [[ -f "$source_path" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                print_info "[DRY-RUN] Would copy $source_path -> $dest_path"
            else
                cp "$source_path" "$dest_path"
                
                # Add deployment metadata
                echo "" >> "$dest_path"
                echo "# Deployment Metadata" >> "$dest_path"
                echo "DEPLOY_CLIENT=$CLIENT" >> "$dest_path"
                echo "DEPLOY_TARGET=$TARGET" >> "$dest_path"
                echo "DEPLOY_ENV=$ENVIRONMENT" >> "$dest_path"
                echo "DEPLOY_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$dest_path"
                
                print_success "Copied env file for $service"
            fi
        else
            print_warning "Env file not found for $service: $source_path"
        fi
    fi
}

# Function to deploy with Docker Compose
deploy_docker_compose() {
    local compose_file="docker-compose.${TARGET}.yaml"
    
    if [[ ! -f "$PROJECT_ROOT/$compose_file" ]]; then
        print_error "Compose file not found: $compose_file"
        exit 1
    fi
    
    print_step "Deploying with Docker Compose: $compose_file"
    
    # Set environment variables for compose
    export COMPOSE_PROJECT_NAME="${CLIENT}-${TARGET}"
    export ENV_DIR="$DEPLOY_DIR/$CLIENT"
    
    local compose_cmd="docker-compose -f $PROJECT_ROOT/$compose_file"
    
    # Determine services to deploy
    local services_to_deploy=""
    if [[ -n "$SERVICES" ]]; then
        IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICES"
        services_to_deploy="${SERVICE_ARRAY[*]}"
    fi
    
    # Copy env files for each service
    if [[ -n "$services_to_deploy" ]]; then
        for service in $services_to_deploy; do
            copy_env_files "$service"
        done
    else
        # Copy all env files
        for service in mongo redis mysql postgres laravel nestjs react next; do
            copy_env_files "$service"
        done
    fi
    
    # Pull latest images
    print_step "Pulling latest images..."
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would run: $compose_cmd pull $services_to_deploy"
    else
        eval "$compose_cmd pull $services_to_deploy" || true
    fi
    
    # Build images
    print_step "Building images..."
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would run: $compose_cmd build $services_to_deploy"
    else
        eval "$compose_cmd build $services_to_deploy"
    fi
    
    # Deploy services
    print_step "Starting services..."
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would run: $compose_cmd up -d $services_to_deploy"
    else
        eval "$compose_cmd up -d $services_to_deploy"
    fi
    
    # Show status
    print_step "Deployment status:"
    if [[ "$DRY_RUN" == false ]]; then
        eval "$compose_cmd ps"
    fi
}

# Function to deploy with Kubernetes
deploy_kubernetes() {
    print_step "Deploying to Kubernetes namespace: $K8S_NAMESPACE"
    
    local k8s_dir="$PROJECT_ROOT/k8s"
    
    if [[ ! -d "$k8s_dir" ]]; then
        print_error "Kubernetes manifests directory not found: $k8s_dir"
        exit 1
    fi
    
    # Create namespace if it doesn't exist
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create namespace: $K8S_NAMESPACE"
    else
        kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    # Copy env files and create secrets
    print_step "Creating Kubernetes secrets from env files..."
    for service in mongo redis mysql postgres laravel nestjs react next; do
        copy_env_files "$service"
        
        local env_file="$DEPLOY_DIR/$CLIENT/.env.$service"
        if [[ -f "$env_file" ]]; then
            local secret_name="${CLIENT}-${service}-secrets"
            
            if [[ "$DRY_RUN" == true ]]; then
                print_info "[DRY-RUN] Would create secret: $secret_name"
            else
                kubectl create secret generic "$secret_name" \
                    --from-env-file="$env_file" \
                    --namespace="$K8S_NAMESPACE" \
                    --dry-run=client -o yaml | kubectl apply -f -
                print_success "Created secret: $secret_name"
            fi
        fi
    done
    
    # Apply ConfigMaps
    print_step "Applying ConfigMaps..."
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would apply: $k8s_dir/configmaps/"
    else
        kubectl apply -f "$k8s_dir/configmaps/" -n "$K8S_NAMESPACE" || true
    fi
    
    # Determine which manifests to apply based on target
    local deployment_type="primary"
    if [[ "$TARGET" == "secondary" ]]; then
        deployment_type="secondary"
    fi
    
    # Apply appropriate deployments based on services
    print_step "Applying deployments for $deployment_type site..."
    
    local manifests=(
        "namespaces"
        "configmaps"
        "secrets"
        "services"
        "deployments"
        "statefulsets"
        "ingress"
    )
    
    for manifest_type in "${manifests[@]}"; do
        local manifest_dir="$k8s_dir/$manifest_type"
        if [[ -d "$manifest_dir" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                print_info "[DRY-RUN] Would apply: $manifest_dir"
            else
                kubectl apply -f "$manifest_dir" -n "$K8S_NAMESPACE" || print_warning "Some resources in $manifest_type may have failed"
            fi
        fi
    done
    
    # Apply target-specific configurations
    local target_dir="$k8s_dir/targets/$TARGET"
    if [[ -d "$target_dir" ]]; then
        print_step "Applying $TARGET-specific configurations..."
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would apply: $target_dir"
        else
            kubectl apply -f "$target_dir" -n "$K8S_NAMESPACE"
        fi
    fi
    
    # Show deployment status
    print_step "Kubernetes deployment status:"
    if [[ "$DRY_RUN" == false ]]; then
        kubectl get pods -n "$K8S_NAMESPACE"
        kubectl get services -n "$K8S_NAMESPACE"
    fi
}

# Function to run health checks
run_health_checks() {
    print_step "Running health checks..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would run health checks"
        return
    fi
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_info "Health check attempt $attempt/$max_attempts"
        
        if [[ "$DEPLOY_K8S" == true ]]; then
            # Kubernetes health check
            local ready_pods=$(kubectl get pods -n "$K8S_NAMESPACE" --no-headers | grep -c "Running" || echo "0")
            local total_pods=$(kubectl get pods -n "$K8S_NAMESPACE" --no-headers | wc -l | tr -d ' ')
            
            print_info "Pods ready: $ready_pods/$total_pods"
            
            if [[ "$ready_pods" -eq "$total_pods" && "$total_pods" -gt 0 ]]; then
                print_success "All pods are running!"
                return 0
            fi
        else
            # Docker Compose health check
            local healthy=$(docker-compose -f "$PROJECT_ROOT/docker-compose.${TARGET}.yaml" ps --services --filter "status=running" | wc -l | tr -d ' ')
            print_info "Healthy containers: $healthy"
            
            if [[ "$healthy" -gt 0 ]]; then
                print_success "Services are running!"
                return 0
            fi
        fi
        
        sleep 10
        ((attempt++))
    done
    
    print_warning "Health check timeout reached"
    return 1
}

# Main deployment logic
main() {
    print_info "Starting deployment for client: $CLIENT"
    
    if [[ "$DEPLOY_K8S" == true ]]; then
        deploy_kubernetes
    else
        deploy_docker_compose
    fi
    
    # Run health checks (skip in dry-run mode)
    if [[ "$DRY_RUN" == false ]]; then
        run_health_checks
    fi
    
    print_success "=========================================="
    print_success "Deployment completed successfully!"
    print_success "Client: $CLIENT"
    print_success "Target: $TARGET"
    print_success "Environment: $ENVIRONMENT"
    print_success "=========================================="
}

# Run main function
main
