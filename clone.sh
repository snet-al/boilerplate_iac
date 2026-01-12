#!/bin/bash

set -e

# =============================================================================
# CLONE.SH - Clone and Setup New Client Environment
# =============================================================================
# Usage: ./clone.sh [options]
# Options:
#   -c, --client      New client name - REQUIRED
#   -t, --template    Template client to clone from (default: example)
#   -r, --repo        Repository URL to clone services from
#   -b, --branch      Branch to clone (default: main)
#   --with-services   Clone service source code repositories
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
TEMPLATE="example"
REPO_URL=""
BRANCH="main"
WITH_SERVICES=false
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"
SERVICES_DIR="$PROJECT_ROOT/services"

# Service repositories (customize these)
declare -A SERVICE_REPOS=(
    ["laravel"]="https://github.com/laravel/laravel.git"
    ["nestjs"]="https://github.com/nestjs/typescript-starter.git"
    ["react"]="https://github.com/facebook/create-react-app.git"
    ["next"]="https://github.com/vercel/next.js.git"
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
Usage: ./clone.sh [options]

Options:
  -c, --client        New client name - REQUIRED
  -t, --template      Template client to clone from (default: example)
  -r, --repo          Repository URL to clone services from
  -b, --branch        Branch to clone (default: main)
  --with-services     Clone service source code repositories
  -h, --help          Show this help message

Available Templates:
$(ls -1 "$ENV_DIR" 2>/dev/null | sed 's/^/  - /')

Examples:
  ./clone.sh -c acme-corp                        # Clone using example template
  ./clone.sh -c acme-corp -t existing-client     # Clone from existing client
  ./clone.sh -c acme-corp --with-services        # Clone with service repos
  ./clone.sh -c acme-corp -r git@github.com:org/repo.git  # Clone from custom repo

This script will:
  1. Create new client directory in env/
  2. Copy and customize environment files
  3. Generate unique secrets and API keys
  4. Optionally clone service repositories

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client)
            CLIENT="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE="$2"
            shift 2
            ;;
        -r|--repo)
            REPO_URL="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        --with-services)
            WITH_SERVICES=true
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

# Sanitize client name
CLIENT=$(echo "$CLIENT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

# Check if client already exists
CLIENT_DIR="$ENV_DIR/$CLIENT"
if [[ -d "$CLIENT_DIR" ]]; then
    print_error "Client directory already exists: $CLIENT_DIR"
    print_info "Use a different name or remove the existing directory"
    exit 1
fi

# Validate template exists
TEMPLATE_DIR="$ENV_DIR/$TEMPLATE"
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    print_error "Template directory not found: $TEMPLATE_DIR"
    print_info "Available templates:"
    ls -1 "$ENV_DIR" 2>/dev/null | sed 's/^/  - /'
    exit 1
fi

print_info "=========================================="
print_info "Clone Configuration"
print_info "=========================================="
print_info "New Client:    $CLIENT"
print_info "Template:      $TEMPLATE"
print_info "With Services: $WITH_SERVICES"
print_info "=========================================="

# Function to generate random string
generate_random_string() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Function to generate secure password
generate_password() {
    local length=${1:-24}
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c "$length"
}

# Function to create client environment
create_client_environment() {
    print_step "Creating client directory: $CLIENT_DIR"
    mkdir -p "$CLIENT_DIR"
    
    # Copy all env files from template
    print_step "Copying environment files from template..."
    
    for env_file in "$TEMPLATE_DIR"/.env.*; do
        if [[ -f "$env_file" ]]; then
            local filename=$(basename "$env_file")
            local dest_file="$CLIENT_DIR/$filename"
            
            # Copy and customize the file
            cp "$env_file" "$dest_file"
            
            # Replace template placeholders
            customize_env_file "$dest_file"
            
            print_success "Created: $filename"
        fi
    done
}

# Function to customize env file with client-specific values
customize_env_file() {
    local file=$1
    local filename=$(basename "$file")
    
    # Generate unique values
    local app_key=$(generate_random_string 32)
    local jwt_secret=$(generate_random_string 64)
    local db_password=$(generate_password 24)
    local redis_password=$(generate_password 16)
    local api_key=$(generate_random_string 32)
    
    # Common replacements
    sed -i.bak "s/{{CLIENT_NAME}}/$CLIENT/g" "$file"
    sed -i.bak "s/{{APP_KEY}}/base64:$(echo -n "$app_key" | base64)/g" "$file"
    sed -i.bak "s/{{JWT_SECRET}}/$jwt_secret/g" "$file"
    sed -i.bak "s/{{DB_PASSWORD}}/$db_password/g" "$file"
    sed -i.bak "s/{{REDIS_PASSWORD}}/$redis_password/g" "$file"
    sed -i.bak "s/{{API_KEY}}/$api_key/g" "$file"
    sed -i.bak "s/{{TIMESTAMP}}/$(date -u +"%Y-%m-%dT%H:%M:%SZ")/g" "$file"
    
    # File-specific customizations
    case $filename in
        .env.db.mongo)
            local mongo_password=$(generate_password 24)
            sed -i.bak "s/{{MONGO_PASSWORD}}/$mongo_password/g" "$file"
            ;;
        .env.db.mysql)
            local mysql_root_password=$(generate_password 24)
            sed -i.bak "s/{{MYSQL_ROOT_PASSWORD}}/$mysql_root_password/g" "$file"
            ;;
        .env.db.postgres)
            local postgres_password=$(generate_password 24)
            sed -i.bak "s/{{POSTGRES_PASSWORD}}/$postgres_password/g" "$file"
            ;;
        .env.back.laravel)
            local laravel_key=$(generate_random_string 32)
            sed -i.bak "s/{{LARAVEL_APP_KEY}}/base64:$(echo -n "$laravel_key" | base64)/g" "$file"
            ;;
        .env.front.next)
            local nextauth_secret=$(generate_random_string 32)
            sed -i.bak "s/{{NEXTAUTH_SECRET}}/$nextauth_secret/g" "$file"
            ;;
    esac
    
    # Remove backup files
    rm -f "$file.bak"
}

# Function to clone service repositories
clone_service_repos() {
    print_step "Setting up service directories..."
    
    local client_services_dir="$SERVICES_DIR/$CLIENT"
    mkdir -p "$client_services_dir"
    
    for service in "${!SERVICE_REPOS[@]}"; do
        local repo_url="${SERVICE_REPOS[$service]}"
        local service_dir="$client_services_dir/$service"
        
        if [[ -n "$REPO_URL" ]]; then
            # Use custom repo URL if provided
            repo_url="$REPO_URL"
        fi
        
        print_info "Cloning $service from $repo_url"
        
        if [[ -d "$service_dir" ]]; then
            print_warning "Service directory already exists: $service_dir"
            continue
        fi
        
        git clone --depth 1 --branch "$BRANCH" "$repo_url" "$service_dir" 2>/dev/null || {
            print_warning "Failed to clone $service, creating empty directory"
            mkdir -p "$service_dir"
            
            # Create basic structure
            case $service in
                laravel)
                    create_laravel_stub "$service_dir"
                    ;;
                nestjs)
                    create_nestjs_stub "$service_dir"
                    ;;
                react)
                    create_react_stub "$service_dir"
                    ;;
                next)
                    create_next_stub "$service_dir"
                    ;;
            esac
        }
        
        print_success "Set up $service"
    done
}

# Stub creation functions
create_laravel_stub() {
    local dir=$1
    mkdir -p "$dir"/{app,config,database,public,resources,routes,storage}
    cat > "$dir/composer.json" << 'EOF'
{
    "name": "client/laravel-app",
    "type": "project",
    "require": {
        "php": "^8.1",
        "laravel/framework": "^10.0"
    }
}
EOF
    cat > "$dir/artisan" << 'EOF'
#!/usr/bin/env php
<?php
// Laravel Artisan stub
EOF
    chmod +x "$dir/artisan"
}

create_nestjs_stub() {
    local dir=$1
    mkdir -p "$dir"/src
    cat > "$dir/package.json" << 'EOF'
{
    "name": "client-nestjs-app",
    "version": "1.0.0",
    "scripts": {
        "build": "nest build",
        "start": "nest start",
        "start:dev": "nest start --watch",
        "start:prod": "node dist/main"
    },
    "dependencies": {
        "@nestjs/common": "^10.0.0",
        "@nestjs/core": "^10.0.0",
        "@nestjs/platform-express": "^10.0.0"
    }
}
EOF
    cat > "$dir/tsconfig.json" << 'EOF'
{
    "compilerOptions": {
        "module": "commonjs",
        "target": "ES2021",
        "outDir": "./dist",
        "rootDir": "./src"
    }
}
EOF
}

create_react_stub() {
    local dir=$1
    mkdir -p "$dir"/{src,public}
    cat > "$dir/package.json" << 'EOF'
{
    "name": "client-react-app",
    "version": "1.0.0",
    "scripts": {
        "start": "react-scripts start",
        "build": "react-scripts build"
    },
    "dependencies": {
        "react": "^18.2.0",
        "react-dom": "^18.2.0",
        "react-scripts": "5.0.1"
    }
}
EOF
}

create_next_stub() {
    local dir=$1
    mkdir -p "$dir"/{pages,public,styles}
    cat > "$dir/package.json" << 'EOF'
{
    "name": "client-next-app",
    "version": "1.0.0",
    "scripts": {
        "dev": "next dev",
        "build": "next build",
        "start": "next start"
    },
    "dependencies": {
        "next": "^14.0.0",
        "react": "^18.2.0",
        "react-dom": "^18.2.0"
    }
}
EOF
    cat > "$dir/next.config.js" << 'EOF'
/** @type {import('next').NextConfig} */
module.exports = {
    reactStrictMode: true,
}
EOF
}

# Function to create client-specific docker-compose override
create_compose_override() {
    print_step "Creating docker-compose override for client..."
    
    local override_file="$CLIENT_DIR/docker-compose.override.yaml"
    
    cat > "$override_file" << EOF
# Docker Compose Override for $CLIENT
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# 
# This file extends the base docker-compose files with client-specific settings.
# Usage: docker-compose -f docker-compose.prod.yaml -f env/$CLIENT/docker-compose.override.yaml up -d

version: '3.8'

services:
  # Add client-specific service configurations here
  
  laravel:
    env_file:
      - ./env/$CLIENT/.env.back.laravel
    labels:
      - "client=$CLIENT"
  
  nestjs:
    env_file:
      - ./env/$CLIENT/.env.back.nestjs
    labels:
      - "client=$CLIENT"
  
  react:
    env_file:
      - ./env/$CLIENT/.env.front.react
    labels:
      - "client=$CLIENT"
  
  next:
    env_file:
      - ./env/$CLIENT/.env.front.next
    labels:
      - "client=$CLIENT"
  
  mongo:
    env_file:
      - ./env/$CLIENT/.env.db.mongo
    labels:
      - "client=$CLIENT"
  
  mysql:
    env_file:
      - ./env/$CLIENT/.env.db.mysql
    labels:
      - "client=$CLIENT"
  
  postgres:
    env_file:
      - ./env/$CLIENT/.env.db.postgres
    labels:
      - "client=$CLIENT"
  
  redis:
    env_file:
      - ./env/$CLIENT/.env.db.redis
    labels:
      - "client=$CLIENT"

# Client-specific volumes
volumes:
  ${CLIENT}_mongo_data:
  ${CLIENT}_mysql_data:
  ${CLIENT}_postgres_data:
  ${CLIENT}_redis_data:
  ${CLIENT}_laravel_storage:

# Client-specific networks
networks:
  ${CLIENT}_network:
    driver: bridge
EOF

    print_success "Created docker-compose override"
}

# Function to generate client summary
generate_summary() {
    print_step "Generating client summary..."
    
    local summary_file="$CLIENT_DIR/README.md"
    
    cat > "$summary_file" << EOF
# Client: $CLIENT

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Template: $TEMPLATE

## Environment Files

| File | Description |
|------|-------------|
| .env.back.laravel | Laravel backend configuration |
| .env.back.nestjs | NestJS backend configuration |
| .env.front.react | React frontend configuration |
| .env.front.next | Next.js frontend configuration |
| .env.db.mongo | MongoDB configuration |
| .env.db.mysql | MySQL configuration |
| .env.db.postgres | PostgreSQL configuration |
| .env.db.redis | Redis configuration |

## Deployment Commands

\`\`\`bash
# Deploy to primary site
./deploy.sh -c $CLIENT -t primary

# Deploy to secondary site (replica)
./deploy.sh -c $CLIENT -t secondary

# Deploy to Kubernetes
./deploy.sh -c $CLIENT -k -n $CLIENT-namespace

# Deploy specific services
./deploy.sh -c $CLIENT -s laravel,mysql,redis
\`\`\`

## Docker Compose Override

Use the generated \`docker-compose.override.yaml\` for client-specific configurations:

\`\`\`bash
docker-compose -f docker-compose.prod.yaml -f env/$CLIENT/docker-compose.override.yaml up -d
\`\`\`

## Important Notes

1. Review all generated passwords and secrets in the .env files
2. Update API keys and external service credentials
3. Configure domain names and SSL certificates
4. Test deployment in a staging environment first

EOF

    print_success "Generated README.md"
}

# Main execution
main() {
    print_info "Starting client setup for: $CLIENT"
    
    # Create client environment
    create_client_environment
    
    # Create compose override
    create_compose_override
    
    # Clone service repos if requested
    if [[ "$WITH_SERVICES" == true ]]; then
        clone_service_repos
    fi
    
    # Generate summary
    generate_summary
    
    print_success "=========================================="
    print_success "Client setup completed successfully!"
    print_success "Client: $CLIENT"
    print_success "Directory: $CLIENT_DIR"
    print_success "=========================================="
    print_info ""
    print_info "Next steps:"
    print_info "  1. Review and customize environment files in $CLIENT_DIR"
    print_info "  2. Update external API keys and credentials"
    print_info "  3. Test with: ./deploy.sh -c $CLIENT --dry-run"
    print_info "  4. Deploy with: ./deploy.sh -c $CLIENT"
    print_info ""
}

# Run main function
main
