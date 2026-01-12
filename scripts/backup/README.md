# Database Backup System

All backup operations are managed through the central orchestrator `backup.sh`.

## Quick Start

```bash
# Dump all databases
./backup.sh dump

# Dump specific database type
./backup.sh dump -d postgres
./backup.sh dump -d mysql
./backup.sh dump -d mongo

# Dump in production
./backup.sh dump -e prod

# Restore from backup
./backup.sh restore -d postgres -f postgres_app_db_20240115_120000.dump
./backup.sh restore -d mysql -f mysql_app_db_20240115_120000.sql.gz --drop

# List backups
./backup.sh list
./backup.sh list -d postgres

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

| Option            | Description                                                |
| ----------------- | ---------------------------------------------------------- |
| `-e, --env`       | Environment (dev\|prod) - default: dev                     |
| `-d, --database`  | Database type (postgres\|mysql\|mongo\|all) - default: all |
| `-n, --name`      | Specific database name (overrides env default)             |
| `-f, --file`      | Backup file for restore                                    |
| `-r, --retention` | Days to keep backups - default: 7                          |
| `--drop`          | Drop existing database before restore                      |
| `--dry-run`       | Preview without executing                                  |

## Architecture

```
backup.sh (Orchestrator)
├── Holds all project configuration
├── Loads environment variables
├── Knows container names
├── Manages credentials
└── Calls executor scripts with parameters

scripts/backup/
├── dump_postgress.sh    # Simple executor - just runs pg_dump
├── restore_postgress.sh # Simple executor - just runs pg_restore
├── dump_mysql.sh        # Simple executor - just runs mysqldump
├── restore_mysql.sh     # Simple executor - just runs mysql restore
├── dump_mongo.sh        # Simple executor - just runs mongodump
└── restore_mongo.sh     # Simple executor - just runs mongorestore
```

The executor scripts are "dumb" - they receive all parameters from the orchestrator and just execute the backup/restore commands.

## Backup Locations

```
backups/data/
├── postgres/   # postgres_<db>_<timestamp>.dump
├── mysql/      # mysql_<db>_<timestamp>.sql.gz
└── mongo/      # mongo_<db>_<timestamp>.archive.gz
```

## Examples

```bash
# Dump PostgreSQL in dev
./backup.sh dump -d postgres

# Dump MySQL with custom database name
./backup.sh dump -d mysql -n custom_db

# Dump all databases in production
./backup.sh dump -e prod

# Preview restore (dry run)
./backup.sh restore -d postgres -f backup.dump --dry-run

# Restore with drop existing
./backup.sh restore -d mysql -f backup.sql.gz --drop

# Cleanup backups older than 30 days
./backup.sh cleanup -r 30
```

## Cron Setup

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/backup.sh dump -e prod >> /var/log/backup.log 2>&1
```
