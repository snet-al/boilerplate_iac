# 🏗️ Infrastructure as Code Boilerplate

A comprehensive, production-ready Infrastructure as Code (IaC) boilerplate supporting multiple services, databases, and deployment targets with Docker Compose and Kubernetes.

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Project Structure](#-project-structure)
- [Quick Start](#-quick-start)
- [Services](#-services)
- [Deployment](#-deployment)
- [Client Management](#-client-management)
- [Kubernetes](#-kubernetes)
- [Configuration](#-configuration)
- [Scripts Reference](#-scripts-reference)

## 🏛️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              LOAD BALANCER                                   │
│                                 (nginx)                                      │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│    Next.js    │       │     React     │       │    API GW     │
│   Frontend    │       │   Frontend    │       │               │
└───────────────┘       └───────────────┘       └───────┬───────┘
                                                        │
                        ┌───────────────────────────────┼───────────────────────┐
                        │                               │                       │
                        ▼                               ▼                       │
              ┌───────────────┐               ┌───────────────┐                │
              │    Laravel    │               │    NestJS     │                │
              │   Backend     │               │   Backend     │                │
              └───────┬───────┘               └───────┬───────┘                │
                      │                               │                        │
        ┌─────────────┼───────────────────────────────┼────────────┐           │
        │             │                               │            │           │
        ▼             ▼                               ▼            ▼           ▼
┌─────────────┐ ┌─────────────┐               ┌─────────────┐ ┌─────────────┐
│    MySQL    │ │    Redis    │               │  PostgreSQL │ │   MongoDB   │
│   Primary   │ │   Cache     │               │   Primary   │ │   Primary   │
└──────┬──────┘ └─────────────┘               └──────┬──────┘ └──────┬──────┘
       │                                             │               │
       ▼ (replication)                               ▼               ▼
┌─────────────┐                               ┌─────────────┐ ┌─────────────┐
│    MySQL    │                               │  PostgreSQL │ │   MongoDB   │
│  Secondary  │                               │  Secondary  │ │  Secondary  │
└─────────────┘                               └─────────────┘ └─────────────┘
```

### Primary/Secondary Architecture

- **Primary Site**: Full read/write capabilities with master databases
- **Secondary Site**: Read replicas with failover capability (master-slave replication)

## 📁 Project Structure

```
boilerplate_iac/
├── 📜 run.sh                    # Local development runner
├── 📜 deploy.sh                 # Production deployment script
├── 📜 clone.sh                  # Clone app repositories
│
├── 🐳 docker-compose.dev.yaml   # Development environment
├── 🐳 docker-compose.prod.yaml  # Production environment
├── 🐳 docker-compose.primary.yaml   # Primary site (master DBs)
├── 🐳 docker-compose.secondary.yaml # Secondary site (replica DBs)
│
├── 📁 apps/                     # App source code (cloned via clone.sh)
│   ├── README.md
│   ├── laravel/                 # Laravel backend app
│   ├── nestjs/                  # NestJS backend app
│   ├── react/                   # React frontend app
│   └── next/                    # Next.js frontend app
│
├── 📁 env/                      # Environment configurations
│   └── client/                  # Default client template/fallback
│       ├── .env.back.laravel
│       ├── .env.back.nestjs
│       ├── .env.front.react
│       ├── .env.front.next
│       ├── .env.db.mongo
│       ├── .env.db.mysql
│       ├── .env.db.postgres
│       └── .env.db.redis
│
├── 📁 config/                   # Service configurations
│   └── nginx/
│       ├── nginx.conf
│       ├── dev/
│       └── prod/
│
├── 📁 docker/                   # Dockerfiles
│   ├── laravel/
│   │   ├── Dockerfile.dev
│   │   └── Dockerfile.prod
│   ├── nestjs/
│   ├── react/
│   ├── next/
│   ├── mongo/
│   ├── mysql/
│   └── postgres/
│
└── 📁 k8s/                      # Kubernetes manifests
    ├── namespaces/
    ├── configmaps/
    ├── secrets/
    ├── deployments/
    ├── statefulsets/
    ├── services/
    ├── ingress/
    ├── hpa/
    ├── storage/
    └── targets/
        ├── primary/
        └── secondary/
```

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- kubectl (for Kubernetes deployments)
- Git

### Development Setup

```bash
# 1. Clone the repository
git clone <repository-url>
cd boilerplate_iac

# 2. Clone app repositories (edit clone.sh first to set your repo URLs)
./clone.sh

# 3. Start development services
./run.sh -e dev

# 4. Start specific services only
./run.sh -s laravel,mysql,redis
```

### Production Deployment

```bash
# Deploy for a specific client
./deploy.sh -c my-client -s primary

# Deploy to secondary site
./deploy.sh -c my-client -s secondary

# Deploy to Kubernetes
./k.sh -c my-client -n my-namespace
```

## 🔧 Services

### Databases

| Service    | Dev Port | Description                   |
| ---------- | -------- | ----------------------------- |
| MongoDB    | 27017    | Document database             |
| Redis      | 6379     | Cache & session store         |
| MySQL      | 3306     | Relational database (Laravel) |
| PostgreSQL | 5432     | Relational database (NestJS)  |

### Backends

| Service | Dev Port | Description                  |
| ------- | -------- | ---------------------------- |
| Laravel | 8000     | PHP backend framework        |
| NestJS  | 3000     | Node.js TypeScript framework |

### Frontends

| Service | Dev Port | Description             |
| ------- | -------- | ----------------------- |
| React   | 3001     | React SPA               |
| Next.js | 3002     | React SSR/SSG framework |

### Infrastructure

| Service | Dev Port | Description      |
| ------- | -------- | ---------------- |
| Nginx   | 80/443   | Reverse proxy/LB |

### Dev Tools (Development Only)

| Service         | Port | Description    |
| --------------- | ---- | -------------- |
| Mailhog         | 8025 | Email testing  |
| Adminer         | 8080 | Database admin |
| Mongo Express   | 8081 | MongoDB admin  |
| Redis Commander | 8082 | Redis admin    |

## 📦 Deployment

### Docker Compose Deployment

```bash
# Development
./run.sh -e dev

# Production - Primary Site
./deploy.sh -c <client> -s primary

# Production - Secondary Site (replicas)
./deploy.sh -c <client> -s secondary
```

### Environment Files

The `deploy.sh` script automatically:

1. Reads environment files directly from `env/<client>`
2. Falls back to `env/client` when the client folder is missing
3. Validates deployment inputs

### Compose Files

| File                            | Use Case                              |
| ------------------------------- | ------------------------------------- |
| `docker-compose.dev.yaml`       | Local development with hot-reload     |
| `docker-compose.prod.yaml`      | Production single-site deployment     |
| `docker-compose.primary.yaml`   | Primary site with master databases    |
| `docker-compose.secondary.yaml` | Secondary site with replica databases |

## 👥 App Management

### Cloning App Repositories

```bash
# Clone all apps (edit clone.sh first to set your repo URLs)
./clone.sh

# Clone specific app only
./clone.sh -a laravel

# Clone from a specific branch
./clone.sh -b develop

# Clone specific app from specific branch
./clone.sh -a nestjs -b feature/auth
```

### Apps Directory Structure

```
apps/
├── README.md          # Apps directory marker
├── laravel/           # Laravel backend app (cloned)
├── nestjs/            # NestJS backend app (cloned)
├── react/             # React frontend app (cloned)
└── next/              # Next.js frontend app (cloned)
```

### Environment Configuration

Use the default client env files and customize for your deployment:

```
env/
└── client/
    ├── .env.back.laravel      # Laravel configuration
    ├── .env.back.nestjs       # NestJS configuration
    ├── .env.front.react       # React configuration
    ├── .env.front.next        # Next.js configuration
    ├── .env.db.mongo          # MongoDB configuration
    ├── .env.db.mysql          # MySQL configuration
    ├── .env.db.postgres       # PostgreSQL configuration
    └── .env.db.redis          # Redis configuration
```

## ☸️ Kubernetes

### Deploying to Kubernetes

```bash
# Deploy with kubectl
./k.sh -c my-client -n production

# Apply manifests manually
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/configmaps/
kubectl apply -f k8s/secrets/
kubectl apply -f k8s/storage/
kubectl apply -f k8s/statefulsets/
kubectl apply -f k8s/deployments/
kubectl apply -f k8s/services/
kubectl apply -f k8s/ingress/
kubectl apply -f k8s/hpa/
```

### Kubernetes Resources

| Directory       | Contents                              |
| --------------- | ------------------------------------- |
| `namespaces/`   | Namespace, ResourceQuota, LimitRange  |
| `configmaps/`   | Application configurations            |
| `secrets/`      | Sensitive data (use external secrets) |
| `deployments/`  | Backend and frontend deployments      |
| `statefulsets/` | Database StatefulSets                 |
| `services/`     | ClusterIP services                    |
| `ingress/`      | Ingress rules with TLS                |
| `hpa/`          | Horizontal Pod Autoscalers            |
| `storage/`      | PVCs and StorageClasses               |
| `targets/`      | Primary/Secondary site configs        |

### Primary vs Secondary Site

```bash
# Primary site (master databases)
kubectl apply -f k8s/targets/primary/

# Secondary site (replica databases)
kubectl apply -f k8s/targets/secondary/
```

## ⚙️ Configuration

### Nginx Configuration

Development and production configurations are in `config/nginx/`:

- `nginx.conf` - Main configuration
- `dev/default.conf` - Development server blocks
- `prod/default.conf` - Production with SSL and rate limiting

### Database Replication

**MySQL Master-Slave:**

```
Primary (server-id=1) → GTID Replication → Secondary (server-id=2, read-only)
```

**PostgreSQL Streaming Replication:**

```
Primary (wal_level=replica) → WAL Streaming → Secondary (hot_standby)
```

**MongoDB Replica Set:**

```
Primary → Replica Set (rs0) → Secondary
```

**Redis Replication:**

```
Master → REPLICAOF → Slave (replica-read-only)
```

## 📜 Scripts Reference

### run.sh

```bash
Usage: ./run.sh [options]

Options:
  -s, --services    Comma-separated services (mongo,redis,mysql,postgres,laravel,nestjs,react,next)
  -e, --env         Environment (dev|prod) - default: dev
  -d, --detach      Run in background
  -b, --build       Force rebuild images
  -l, --logs        Follow logs after starting
  -h, --help        Show help

Examples:
  ./run.sh                              # Run all services
  ./run.sh -s laravel,mysql,redis       # Run specific services
  ./run.sh -e prod -d                   # Production, detached
```

### deploy.sh

```bash
Usage: ./deploy.sh [options]

Options:
  -c, --client      Client name (required)
  -s, --site        Site (primary|secondary)
  -a, --apps        Comma-separated apps to deploy
  -h, --help        Show help

Examples:
  ./deploy.sh -c acme-corp                    # Deploy all
  ./deploy.sh -c acme-corp -s secondary       # Deploy replica site
  ./deploy.sh -c acme-corp -a laravel,mysql   # Deploy specific apps
```

### clone.sh

```bash
Usage: ./clone.sh [options]

Options:
  -a, --app         Clone specific app (laravel|nestjs|react|next)
  -b, --branch      Branch to clone (default: main)
  -h, --help        Show help

Examples:
  ./clone.sh                        # Clone all apps
  ./clone.sh -a laravel             # Clone only Laravel
  ./clone.sh -b develop             # Clone from develop branch
  ./clone.sh -a nestjs -b feat      # Clone NestJS from feat branch
```

**Note:** Edit `APP_REPOS` in `clone.sh` to configure your repository URLs.

## 🔐 Security Notes

1. **Secrets Management**: In production, use external secrets management:

   - Kubernetes External Secrets
   - HashiCorp Vault
   - AWS Secrets Manager
   - Azure Key Vault

2. **SSL/TLS**: Configure SSL certificates in `config/nginx/ssl/`

3. **Passwords**: All passwords are auto-generated during `clone.sh`

4. **Network Security**: Internal services use private networks

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📄 License

MIT License - See LICENSE file for details.
