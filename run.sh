#!/bin/bash

set -e

# =============================================================================
# RUN.SH - Local Development Runner
# =============================================================================
# Usage: ./run.sh [options]
# Options:
#   -s, --services    Comma-separated list of services to run
#   -e, --env         Environment (dev|prod) - default: dev
#   -d, --detach      Run in detached mode
#   -b, --build       Force rebuild images
#   -l, --logs        Follow logs after starting
#   -h, --help        Show this help message
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
SERVICES=""
DETACH=""
BUILD=""
FOLLOW_LOGS=false
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Available services
AVAILABLE_SERVICES=(
    "mongo"
    "redis"
    "mysql"
    "postgres"
    "laravel"
    "nestjs"
    "react"
    "next"
    "nginx"
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

# Function to show help
show_help() {
    cat << EOF
Usage: ./run.sh [options]

Options:
  -s, --services    Comma-separated list of services to run
                    Available: ${AVAILABLE_SERVICES[*]}
  -e, --env         Environment (dev|prod) - default: dev
  -d, --detach      Run in detached mode
  -b, --build       Force rebuild images
  -l, --logs        Follow logs after starting
  -h, --help        Show this help message

Examples:
  ./run.sh                                    # Run all services in dev mode
  ./run.sh -s laravel,mysql,redis             # Run specific services
  ./run.sh -e prod -d                         # Run in production mode, detached
  ./run.sh -s nestjs,postgres -b              # Run with forced rebuild
  ./run.sh -s react,next -l                   # Run frontend services and follow logs

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--services)
            SERVICES="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -d|--detach)
            DETACH="-d"
            shift
            ;;
        -b|--build)
            BUILD="--build"
            shift
            ;;
        -l|--logs)
            FOLLOW_LOGS=true
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

# Validate environment
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    print_error "Invalid environment: $ENVIRONMENT. Use 'dev' or 'prod'"
    exit 1
fi

# Set compose file based on environment
COMPOSE_FILE="docker-compose.${ENVIRONMENT}.yaml"

if [[ ! -f "$PROJECT_ROOT/$COMPOSE_FILE" ]]; then
    print_error "Compose file not found: $COMPOSE_FILE"
    exit 1
fi

print_info "Starting services with environment: ${ENVIRONMENT}"
print_info "Using compose file: ${COMPOSE_FILE}"

# Build the docker-compose command
COMPOSE_CMD="docker-compose -f $PROJECT_ROOT/$COMPOSE_FILE"

# Add services if specified
if [[ -n "$SERVICES" ]]; then
    IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICES"
    print_info "Services to start: ${SERVICE_ARRAY[*]}"
    
    # Validate services
    for service in "${SERVICE_ARRAY[@]}"; do
        if [[ ! " ${AVAILABLE_SERVICES[*]} " =~ " ${service} " ]]; then
            print_warning "Service '${service}' may not be defined in compose file"
        fi
    done
    
    COMPOSE_CMD="$COMPOSE_CMD up $DETACH $BUILD ${SERVICE_ARRAY[*]}"
else
    print_info "Starting all services"
    COMPOSE_CMD="$COMPOSE_CMD up $DETACH $BUILD"
fi

# Run docker-compose
print_info "Executing: $COMPOSE_CMD"
eval $COMPOSE_CMD

# Follow logs if requested and running in detached mode
if [[ "$FOLLOW_LOGS" == true && -n "$DETACH" ]]; then
    print_info "Following logs..."
    if [[ -n "$SERVICES" ]]; then
        docker-compose -f "$PROJECT_ROOT/$COMPOSE_FILE" logs -f ${SERVICE_ARRAY[*]}
    else
        docker-compose -f "$PROJECT_ROOT/$COMPOSE_FILE" logs -f
    fi
fi

print_success "Services started successfully!"
