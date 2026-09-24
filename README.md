# 🏗️ Infrastructure as Code Boilerplate

A comprehensive, production-ready Infrastructure as Code (IaC) boilerplate supporting multiple services, databases, and deployment targets with Docker Compose and Kubernetes.

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Project Structure](#-project-structure)
- [Quick Start](#-quick-start)
- [Services](#-services)
- [SMTP Relay](#️-smtp-relay)
- [Deployment](#-deployment)
- [Client Management](#-client-management)
- [Kubernetes](#-kubernetes)
- [Configuration](#-configuration)
- [Migration Checklist](#-migration-checklist)
- [Scaffold Conventions](#scaffold-conventions)
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
├── 📜 deploy-primary.sh         # Primary site deployment script
├── 📜 deploy-secondary.sh       # Secondary site deployment script
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
│   └── client/                  # Client template (copy per client)
│       ├── .env.back.laravel
│       ├── .env.back.nestjs
│       ├── .env.front.react
│       ├── .env.front.next
│       ├── .env.db.mongo
│       ├── .env.db.mysql
│       ├── .env.db.postgres
│       ├── .env.db.redis
│       └── .env.infra.smtp
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
│   ├── postgres/
│   └── smtp/                    # Send-only Postfix + OpenDKIM relay
│       ├── Dockerfile
│       └── entrypoint.sh
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
# Deploy to the primary site
./deploy-primary.sh -c my-client

# Deploy to the secondary site apps only
./deploy-secondary.sh -c my-client

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

| Service | Dev Port | Description                          |
| ------- | -------- | ------------------------------------ |
| Nginx   | 80/443   | Reverse proxy/LB                     |
| SMTP    | 2525→25  | Send-only mail relay (Postfix+DKIM)  |

### Dev Tools (Development Only)

| Service         | Port | Description    |
| --------------- | ---- | -------------- |
| Mailhog         | 8025 | Email testing  |
| Adminer         | 8080 | Database admin |
| Mongo Express   | 8081 | MongoDB admin  |
| Redis Commander | 8082 | Redis admin    |

## ✉️ SMTP Relay

`docker/smtp/` is a self-contained, send-only mail relay: Postfix + OpenDKIM on Alpine,
fully configured from env vars. Apps talk to it as `smtp:25` on `backend_network` — no
auth, access is restricted by `SMTP_ALLOWED_NETWORKS`. Every message is DKIM-signed and
must come from an address `@SMTP_DOMAIN` (or `SMTP_ALLOWED_SENDER_DOMAINS`); anything
else is rejected at `MAIL FROM`. It is portable: copy `docker/smtp/`, the compose block
and `env/client/.env.infra.smtp` into any `pr_*` repo and set `SMTP_DOMAIN`.

**Configure** `env/<client>/.env.infra.smtp` (template in `env/client/`):

| Variable                      | Default                          | Purpose                                   |
| ----------------------------- | -------------------------------- | ----------------------------------------- |
| `SMTP_DOMAIN`                 | required                         | Sender domain — mail goes out as `@domain` |
| `SMTP_HOSTNAME`               | `mail.$SMTP_DOMAIN`              | HELO name; must have A + PTR for direct delivery |
| `SMTP_ALLOWED_SENDER_DOMAINS` | `$SMTP_DOMAIN`                   | Space-separated envelope-sender allowlist |
| `SMTP_ALLOWED_NETWORKS`       | Docker private ranges            | Who may submit (Postfix `mynetworks`)     |
| `SMTP_DKIM_SELECTOR`          | `mail`                           | DKIM selector; key auto-generated on first boot |
| `SMTP_RELAY_HOST/PORT/USER/PASSWORD` | empty (direct delivery)   | Optional upstream (SES, Mailgun, Postmark…) |
| `SMTP_RELAY_TLS`              | `true`                           | Require TLS to the relay                  |

Use `SMTP_RELAY_HOST` whenever the host cannot open outbound port 25 (most VPS providers
block it) or has no static IP with a PTR record. DKIM is still applied before the relay.

**Getting mail delivered.** With `SMTP_RELAY_HOST` empty the relay hands mail straight to
the recipient's MX from the host's own IP. Whether Gmail/Outlook accept it depends on the
records below, which all have to agree on `SMTP_HOSTNAME` (`mail.<domain>`) and the host's
public IP:

| record | where | value |
| --- | --- | --- |
| `A mail.<domain>` | DNS provider, **unproxied** | the host's public IP |
| PTR for that IP | VPS provider panel (Contabo: Network Services → Reverse DNS; Hetzner: server → Networking) | `mail.<domain>` |
| SPF `TXT <domain>` | DNS provider | `v=spf1 a:mail.<domain> ~all`, merged into whatever SPF already exists |
| DKIM `TXT <selector>._domainkey.<domain>` | DNS provider | `v=DKIM1;k=rsa;p=…` as printed by `entrypoint.sh dns` |
| DMARC `TXT _dmarc.<domain>` | DNS provider | `v=DMARC1; p=none;` while validating, then `p=quarantine; rua=mailto:postmaster@<domain>; adkim=s; aspf=s` |

The A record must not sit behind a CDN proxy (Cloudflare orange cloud): SMTP never passes
through the proxy and the SPF `a:` mechanism resolves that name. A domain can only have one
SPF record, so `a:mail.<domain>` is added to the existing one rather than replacing it; if
inbound mail is handled by a forwarding service (Cloudflare Email Routing, ImprovMX, …) its
`include:` stays or forwarded mail fails SPF. The DKIM key is generated on first start into
the `smtp_dkim` volume; a fresh volume means a fresh key and a new TXT value, so the volume
is part of the backup set. Other `_domainkey` selectors already on the zone (a forwarding
service, Resend, SES, …) are other senders and coexist with this one.

Bounces and delivery-status notifications are addressed to the envelope sender
(`noreply@<domain>` or whatever the app uses as `From`), DMARC aggregate reports to
`SMTP_DMARC_RUA`. Both need a mailbox or forwarding rule behind them; otherwise the domain's
own MX answers `550` and the bounce is lost.

The relay itself prints and checks the same things:

```bash
docker exec <client>-primary_smtp entrypoint.sh dns      # SPF, DKIM, DMARC, A/PTR to publish
docker exec <client>-primary_smtp entrypoint.sh test you@example.org
docker exec <client>-primary_smtp mailq                  # queue / bounces
dig +short A mail.<domain>; dig +short -x <ip>            # A and PTR as the world sees them
dig +short TXT <domain> | grep spf; dig +short TXT <selector>._domainkey.<domain>
```

A correct send shows `SPF: PASS`, `DKIM: PASS with domain <domain>` and `DMARC: PASS` in
Gmail's "Show original"; mail-tester.com scores the rest (PTR, blacklists, headers).
Sending before A/PTR/SPF are in place is the fastest way to get a fresh IP blacklisted,
which is why they are published before the first deploy and DKIM right after it.

What recipients see is the app's `From` (`EMAIL_FROM_ADDRESS` / `MAIL_FROM_ADDRESS`);
`"Name <noreply@<domain>>"` gives it a display name and still passes the sender allowlist.
`SMTP_SECURE=false` / `MAIL_ENCRYPTION=null` and no published port on the relay are by
design: app → relay is plain SMTP inside the compose network, relay → world negotiates
STARTTLS (`smtp_tls_security_level=may`, `encrypt` when an upstream relay is set).
`SMTP_ALLOWED_NETWORKS` defaults to the RFC 1918 ranges so it covers whatever subnet Docker
assigns; it can be narrowed to the one in `docker network inspect <backend network>`.

Primary and secondary sites must sign with the same key: copy the `smtp_dkim` volume to
the secondary (or `docker cp` the `keys/<domain>/` directory) before its first start.

**Porting the relay into an existing `pr_*` repo** (which may not share this scaffold's file
names — check its compose files, `run.sh` and `deploy*.sh` first):

1. `cp -r boilerplate_iac/docker/smtp <repo>/docker/smtp` — nothing inside it is project-specific.
2. Env file per stage/client in the repo's own naming (`env/smtp.env.prod`,
   `env/clients/<client>/smtp.env.prod`, …) from `env/client/.env.infra.smtp` with `SMTP_DOMAIN` set.
3. Compose block per file: `build.context: ./docker/smtp`, `env_file`, the two volumes
   (`smtp_spool`, `smtp_dkim`), the repo's backend network, the `postfix status` healthcheck.
   Register both volumes at the top. Dev may expose `127.0.0.1:2525:25`; prod exposes nothing.
4. Apps: add `SMTP_HOST=<smtp service> SMTP_PORT=25` (Laravel: `MAIL_HOST/MAIL_PORT`,
   `MAIL_ENCRYPTION=null`) to the mail-sending services and `depends_on` the relay. If the app
   hard-codes its transport, make it read those vars.
5. Scripts: add the service to `run.sh`'s core list and the env copy to the deploy script
   (`ENV_FILES` here; whatever `cp` block the repo uses otherwise).
6. Start it, run `entrypoint.sh dns`, publish the records, `entrypoint.sh test <you>`.

**Apps** point at the relay with the vars already in the client templates: Laravel
`MAIL_HOST=smtp MAIL_PORT=25 MAIL_ENCRYPTION=null`, NestJS `SMTP_HOST=smtp SMTP_PORT=25`.
In dev, `mailhog` remains the default for app templates; the relay is also started and
reachable from the host on `localhost:2525` for integration checks.

## 📦 Deployment

### Docker Compose Deployment

```bash
# Development
./run.sh -e dev

# Production - Primary Site
./deploy-primary.sh -c <client>

# Production - Secondary Site apps only
./deploy-secondary.sh -c <client>

# Secondary replica databases only
./deploy-secondary.sh -c <client> -a db
```

### Environment Files

The deploy scripts automatically:

1. Copies client-specific environment files
2. Adds deployment metadata
3. Validates configurations

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

Copy the client template folder and customize for your deployment:

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

### Migration Checklist

Use this checklist when adopting the scaffold in a project that already has a live primary PostgreSQL database.

1. Back up the current primary database before enabling replication.
2. Keep the existing primary volume and data directory. Do not wipe or recreate the primary database just to enable replication.
3. Set the PostgreSQL replication environment variables for the project:
   `POSTGRES_PRIMARY_HOST`, `POSTGRES_PRIMARY_PORT`, `POSTGRES_SECONDARY_HOST`,
   `POSTGRES_REPLICATION_USER`, `POSTGRES_REPLICATION_PASSWORD`, and `POSTGRES_REPLICATION_SLOT`.
4. Restart only the primary database with the new replication settings first, then verify it starts cleanly with the existing data.
5. `deploy-primary.sh` automatically re-applies the PostgreSQL replication role on the running primary container after startup. If you start the primary database some other way, manually verify that the replication role exists and can log in. Init scripts in `/docker-entrypoint-initdb.d` only run on first initialization of an empty data directory.
6. Confirm the primary `pg_hba.conf` allows the secondary host IP or CIDR to connect for replication.
7. Start the secondary database with a fresh empty volume so it can run `pg_basebackup` from the primary. Do not reuse an unrelated secondary volume from another project.
8. Verify replication after startup:
   on the secondary, `SELECT pg_is_in_recovery();` should return `true`;
   on the primary, `SELECT * FROM pg_stat_replication;` should show the standby connection.
9. Only after replication is healthy should you point secondary-site app reads to the standby database.

This scaffold is designed to preserve existing primary data. The risky part is usually not corruption of the primary, but starting a secondary from stale or unrelated data, or forgetting to create and verify the replication user on an already-initialized primary.

### Scaffold Conventions

When adapting this boilerplate for your project, follow these patterns to keep scripts clean and easy to modify.

**Configuration as data, not logic.** Services and env file mappings are declared as arrays at the top of each script. To add or remove a service, edit the array -- don't touch the functions below it.

```bash
# app:source:destination
ENV_FILES=(
    "mongo:.env.db.mongo:.env.mongo"
    "postgres:.env.db.postgres:.env.postgres"
    "myapp:.env.back.myapp:.env.myapp"    # <- add your service here
)
```

**No `show_help` functions.** Usage is documented in the header comment of each script. The `--help` flag prints a one-line usage string. This avoids duplicating documentation between the comment and a function body that inevitably falls out of sync.

```bash
# =============================================================================
# DEPLOY-PRIMARY.SH - Primary Site Deployment
# =============================================================================
# Usage: ./deploy-primary.sh -c <client> [-a apps]
# =============================================================================
```

**Database-specific logic stays in `docker/`.** Deploy scripts are thin orchestrators. Any logic tied to a specific database engine (SQL, connection checks, replication setup) lives in `docker/<engine>/` as a standalone script. Deploy scripts call it with a one-liner.

```
docker/postgres/primary/
├── entrypoint.sh                  # runtime config (pg_hba.conf rendering)
├── ensure-replication-user.sh     # post-startup replication role
└── pg_hba.conf                    # auth template
```

## 📜 Scripts Reference

### run.sh

```bash
Usage: ./run.sh [options]

Options:
  -s, --services    Comma-separated services (mongo,redis,mysql,postgres,laravel,nestjs,react,next,smtp)
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

### deploy-primary.sh

```bash
Usage: ./deploy-primary.sh [options]

Options:
  -c, --client      Client name (required)
  -a, --apps        Specific apps to deploy
  -h, --help        Show help

Examples:
  ./deploy-primary.sh -c acme-corp            # Deploy primary stack
  ./deploy-primary.sh -c acme-corp -a db      # Deploy primary databases only
  ./deploy-primary.sh -c acme-corp -a apps    # Deploy application services only
```

### deploy-secondary.sh

```bash
Usage: ./deploy-secondary.sh [options]

Options:
  -c, --client      Client name (required)
  -a, --apps        Specific apps to deploy
                    Default: laravel,nestjs,react,next,smtp
                    Use db to deploy replica databases only
                    nginx is intentionally excluded
  -h, --help        Show help

Examples:
  ./deploy-secondary.sh -c acme-corp          # Deploy secondary apps only
  ./deploy-secondary.sh -c acme-corp -a db    # Deploy replica databases only
  ./deploy-secondary.sh -c acme-corp -a react,next
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
