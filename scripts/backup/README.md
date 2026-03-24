# Database Backup System

All backup operations are managed through the central orchestrator `backup.sh`.

## Setup

**Interactive wizard** (writes `backup.env` or `backup.prod.env` with safe quoting; can run dry-run / full backup from the script; cron: manual instructions or enter minute/hour and optional `crontab` append):

```bash
bash scripts/backup/setup-backup-env.sh        # prompts for dev vs prod
bash scripts/backup/setup-backup-env.sh prod
bash scripts/backup/setup-backup-env.sh dev
```

Or create configuration manually:

```bash
cp env/backup.env.example backup.env
cp env/backup.prod.env.example backup.prod.env
# Edit: BACKUP_DATABASE (postgres|mysql|mongo), CONNECTION_TYPE, credentials, etc.
```

## Quick Start

```bash
# Dump configured database (dev)
./backup.sh dump

# Dump configured database (production)
./backup.sh dump -e prod

# Override database name
./backup.sh dump -n custom_db

# Restore from backup
./backup.sh restore -f postgres_app_db_20240115_120000.dump
./backup.sh restore -f mysql_app_db_20240115_120000.sql.gz --drop

# List all backups
./backup.sh list

# Cleanup old backups
./backup.sh cleanup -r 14
```

## Commands

| Command   | Description                       |
| --------- | --------------------------------- |
| `dump`    | Backup database(s)                |
| `restore` | Restore database from backup file |
| `list`    | List available backups            |
| `cleanup` | Remove old backups                |

## Options

| Option            | Description                                        |
| ----------------- | -------------------------------------------------- |
| `-e, --env`       | Environment (dev\|prod) - default: dev             |
| `-n, --name`      | Override database name from config                 |
| `-f, --file`      | Backup file for restore                            |
| `-r, --retention` | Days to keep backups (overrides config)            |
| `--drop`          | Drop existing database before restore              |
| `--dry-run`       | Preview without executing                          |

## Architecture

```
backup.sh (Orchestrator)
├── Loads configuration from backup.env or backup.prod.env
├── Determines which database to backup (BACKUP_DATABASE setting)
├── Uses generic variables (CONTAINER, DB_USER, DB_PASSWORD, DB_NAME)
└── Calls appropriate executor script with parameters

scripts/backup/
├── dump_postgres.sh     # Simple executor - just runs pg_dump
├── restore_postgres.sh  # Simple executor - just runs pg_restore
├── dump_mysql.sh        # Simple executor - just runs mysqldump
├── restore_mysql.sh     # Simple executor - just runs mysql restore
├── dump_mongo.sh        # Simple executor - just runs mongodump
└── restore_mongo.sh     # Simple executor - just runs mongorestore
```

The executor scripts are "dumb" - they receive all parameters from the orchestrator and just execute the backup/restore commands.

## Configuration

Edit `backup.env` or `backup.prod.env`:

```bash
# Which database to backup (postgres|mysql|mongo)
BACKUP_DATABASE="postgres"

# Database connection details
CONTAINER="dev_postgres"
DB_USER="app_user"
DB_PASSWORD="devpassword"
DB_NAME="app_db"

# Backup settings
BACKUP_RETENTION_DAYS=7
BACKUP_DIR="./backups/data"
```

## Backup Locations

```
backups/data/
├── postgres/   # postgres_<db>_<timestamp>.dump
├── mysql/      # mysql_<db>_<timestamp>.sql.gz
└── mongo/      # mongo_<db>_<timestamp>.archive.gz
```

## Examples

```bash
# Dump configured database in dev
./backup.sh dump

# Dump configured database with custom name
./backup.sh dump -n custom_db

# Dump configured database in production
./backup.sh dump -e prod

# Preview restore (dry run)
./backup.sh restore -f backup.dump --dry-run

# Restore with drop existing
./backup.sh restore -f backup.sql.gz --drop

# Cleanup backups older than 30 days
./backup.sh cleanup -r 30
```

## Cron Setup

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/backup.sh dump -e prod >> /var/log/backup.log 2>&1
```
