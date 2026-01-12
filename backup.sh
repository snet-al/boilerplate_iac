#!/bin/bash
# =============================================================================
# BACKUP ORCHESTRATION SCRIPT
# =============================================================================
# Central orchestrator for all database backup/restore operations
# Holds all project configuration, environment variables, and container info
#
# Usage: ./backup.sh <command> [options]
#
# Commands:
#   dump      Backup database(s)
#   restore   Restore database from backup
#   list      List available backups
#   cleanup   Remove old backups
#
# Options:
#   -e, --env           Environment (dev|prod) - default: dev
#   -d, --database      Database type (postgres|mysql|mongo|all) - default: all
#   -n, --name          Specific database name (optional)
#   -f, --file          Backup file for restore (required for restore)
#   -r, --retention     Days to keep backups - default: 7
#   --drop              Drop existing before restore
#   --dry-run           Preview without executing
#   -h, --help          Show help message
# =============================================================================

set -euo pipefail

# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="boilerplate"
BACKUP_DIR="${SCRIPT_DIR}/backups/data"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts/backup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# =============================================================================
# DEFAULT VALUES
# =============================================================================
ENVIRONMENT="dev"
DATABASE="all"
DB_NAME=""
BACKUP_FILE=""
RETENTION_DAYS=7
DROP_EXISTING=false
DRY_RUN=false
COMMAND=""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

show_help() {
    cat << EOF
=============================================================================
BACKUP ORCHESTRATION SCRIPT
=============================================================================
Central orchestrator for all database backup/restore operations

Usage: ./backup.sh <command> [options]

Commands:
    dump        Backup database(s)
    restore     Restore database from backup
    list        List available backups
    cleanup     Remove old backups

Options:
    -e, --env           Environment (dev|prod) - default: dev
    -d, --database      Database type (postgres|mysql|mongo|all) - default: all
    -n, --name          Specific database name (optional, overrides env default)
    -f, --file          Backup file for restore (required for restore)
    -r, --retention     Days to keep backups - default: 7
    --drop              Drop existing database before restore
    --dry-run           Preview without executing
    -h, --help          Show this help message

Examples:
    ./backup.sh dump                              # Dump all databases in dev
    ./backup.sh dump -e prod                      # Dump all databases in production
    ./backup.sh dump -d postgres                  # Dump only PostgreSQL
    ./backup.sh dump -d mysql -n custom_db        # Dump specific MySQL database
    ./backup.sh restore -d postgres -f backup.dump
    ./backup.sh restore -d mysql -f backup.sql.gz --drop
    ./backup.sh list -d postgres                  # List PostgreSQL backups
    ./backup.sh cleanup -r 14                     # Remove backups older than 14 days

EOF
    exit 0
}

# =============================================================================
# ENVIRONMENT LOADING
# =============================================================================
load_environment() {
    local env="$1"
    
    # Set compose project name based on environment
    COMPOSE_PROJECT_NAME="${env}"
    
    # PostgreSQL defaults
    POSTGRES_CONTAINER="${COMPOSE_PROJECT_NAME}_postgres"
    POSTGRES_USER="app_user"
    POSTGRES_PASSWORD="devpassword"
    POSTGRES_DB="app_db"
    
    # MySQL defaults
    MYSQL_CONTAINER="${COMPOSE_PROJECT_NAME}_mysql"
    MYSQL_USER="app_user"
    MYSQL_PASSWORD="devpassword"
    MYSQL_ROOT_PASSWORD="devpassword"
    MYSQL_DATABASE="app_db"
    
    # MongoDB defaults
    MONGO_CONTAINER="${COMPOSE_PROJECT_NAME}_mongo"
    MONGO_ROOT_USERNAME="admin"
    MONGO_ROOT_PASSWORD="devpassword"
    MONGO_DATABASE="app_db"
    
    # Load PostgreSQL env if exists
    local pg_env="${SCRIPT_DIR}/env/${env}/.env.postgres"
    if [[ -f "$pg_env" ]]; then
        log "Loading PostgreSQL config from: ${pg_env}"
        set -a
        source "$pg_env"
        set +a
    fi
    
    # Load MySQL env if exists
    local mysql_env="${SCRIPT_DIR}/env/${env}/.env.mysql"
    if [[ -f "$mysql_env" ]]; then
        log "Loading MySQL config from: ${mysql_env}"
        set -a
        source "$mysql_env"
        set +a
    fi
    
    # Load MongoDB env if exists
    local mongo_env="${SCRIPT_DIR}/env/${env}/.env.mongo"
    if [[ -f "$mongo_env" ]]; then
        log "Loading MongoDB config from: ${mongo_env}"
        set -a
        source "$mongo_env"
        set +a
    fi
}

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================
if [[ $# -eq 0 ]]; then
    show_help
fi

# First argument is the command
COMMAND="$1"
shift

# Parse remaining options
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -n|--name)
            DB_NAME="$2"
            shift 2
            ;;
        -f|--file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        -r|--retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --drop)
            DROP_EXISTING=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log "ERROR: Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate command
if [[ ! "$COMMAND" =~ ^(dump|restore|list|cleanup)$ ]]; then
    log "ERROR: Invalid command: $COMMAND"
    show_help
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    log "ERROR: Invalid environment: $ENVIRONMENT. Must be 'dev' or 'prod'."
    exit 1
fi

# Validate database
if [[ ! "$DATABASE" =~ ^(postgres|mysql|mongo|all)$ ]]; then
    log "ERROR: Invalid database: $DATABASE. Must be 'postgres', 'mysql', 'mongo', or 'all'."
    exit 1
fi

# Load environment configuration
load_environment "$ENVIRONMENT"

# Create backup directories
mkdir -p "${BACKUP_DIR}/postgres"
mkdir -p "${BACKUP_DIR}/mysql"
mkdir -p "${BACKUP_DIR}/mongo"

# =============================================================================
# DUMP FUNCTIONS
# =============================================================================
dump_postgres() {
    local db_name="${DB_NAME:-$POSTGRES_DB}"
    local output_file="${BACKUP_DIR}/postgres/postgres_${db_name}_${TIMESTAMP}.dump"
    
    log "=========================================="
    log "PostgreSQL Dump"
    log "=========================================="
    log "Container: ${POSTGRES_CONTAINER}"
    log "Database: ${db_name}"
    log "Output: ${output_file}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would dump PostgreSQL database"
        return 0
    fi
    
    "${SCRIPTS_DIR}/dump_postgress.sh" \
        --container "${POSTGRES_CONTAINER}" \
        --user "${POSTGRES_USER}" \
        --password "${POSTGRES_PASSWORD}" \
        --database "${db_name}" \
        --output "${output_file}"
}

dump_mysql() {
    local db_name="${DB_NAME:-$MYSQL_DATABASE}"
    local output_file="${BACKUP_DIR}/mysql/mysql_${db_name}_${TIMESTAMP}.sql.gz"
    
    log "=========================================="
    log "MySQL Dump"
    log "=========================================="
    log "Container: ${MYSQL_CONTAINER}"
    log "Database: ${db_name}"
    log "Output: ${output_file}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would dump MySQL database"
        return 0
    fi
    
    "${SCRIPTS_DIR}/dump_mysql.sh" \
        --container "${MYSQL_CONTAINER}" \
        --user "${MYSQL_USER}" \
        --password "${MYSQL_PASSWORD}" \
        --database "${db_name}" \
        --output "${output_file}"
}

dump_mongo() {
    local db_name="${DB_NAME:-$MONGO_DATABASE}"
    local output_file="${BACKUP_DIR}/mongo/mongo_${db_name}_${TIMESTAMP}.archive.gz"
    
    log "=========================================="
    log "MongoDB Dump"
    log "=========================================="
    log "Container: ${MONGO_CONTAINER}"
    log "Database: ${db_name}"
    log "Output: ${output_file}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would dump MongoDB database"
        return 0
    fi
    
    "${SCRIPTS_DIR}/dump_mongo.sh" \
        --container "${MONGO_CONTAINER}" \
        --user "${MONGO_ROOT_USERNAME}" \
        --password "${MONGO_ROOT_PASSWORD}" \
        --database "${db_name}" \
        --output "${output_file}"
}

# =============================================================================
# RESTORE FUNCTIONS
# =============================================================================
restore_postgres() {
    if [[ -z "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file required for restore. Use -f option."
        exit 1
    fi
    
    # Resolve backup file path
    if [[ ! -f "$BACKUP_FILE" ]] && [[ -f "${BACKUP_DIR}/postgres/${BACKUP_FILE}" ]]; then
        BACKUP_FILE="${BACKUP_DIR}/postgres/${BACKUP_FILE}"
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
    
    local db_name="${DB_NAME:-$POSTGRES_DB}"
    
    log "=========================================="
    log "PostgreSQL Restore"
    log "=========================================="
    log "Container: ${POSTGRES_CONTAINER}"
    log "Database: ${db_name}"
    log "File: ${BACKUP_FILE}"
    log "Drop existing: ${DROP_EXISTING}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would restore PostgreSQL database"
        return 0
    fi
    
    local drop_flag=""
    [[ "$DROP_EXISTING" == true ]] && drop_flag="--drop"
    
    "${SCRIPTS_DIR}/restore_postgress.sh" \
        --container "${POSTGRES_CONTAINER}" \
        --user "${POSTGRES_USER}" \
        --password "${POSTGRES_PASSWORD}" \
        --database "${db_name}" \
        --file "${BACKUP_FILE}" \
        ${drop_flag}
}

restore_mysql() {
    if [[ -z "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file required for restore. Use -f option."
        exit 1
    fi
    
    # Resolve backup file path
    if [[ ! -f "$BACKUP_FILE" ]] && [[ -f "${BACKUP_DIR}/mysql/${BACKUP_FILE}" ]]; then
        BACKUP_FILE="${BACKUP_DIR}/mysql/${BACKUP_FILE}"
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
    
    local db_name="${DB_NAME:-$MYSQL_DATABASE}"
    
    log "=========================================="
    log "MySQL Restore"
    log "=========================================="
    log "Container: ${MYSQL_CONTAINER}"
    log "Database: ${db_name}"
    log "File: ${BACKUP_FILE}"
    log "Drop existing: ${DROP_EXISTING}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would restore MySQL database"
        return 0
    fi
    
    local drop_flag=""
    [[ "$DROP_EXISTING" == true ]] && drop_flag="--drop"
    
    "${SCRIPTS_DIR}/restore_mysql.sh" \
        --container "${MYSQL_CONTAINER}" \
        --user "${MYSQL_USER}" \
        --password "${MYSQL_PASSWORD}" \
        --database "${db_name}" \
        --file "${BACKUP_FILE}" \
        ${drop_flag}
}

restore_mongo() {
    if [[ -z "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file required for restore. Use -f option."
        exit 1
    fi
    
    # Resolve backup file path
    if [[ ! -f "$BACKUP_FILE" ]] && [[ -f "${BACKUP_DIR}/mongo/${BACKUP_FILE}" ]]; then
        BACKUP_FILE="${BACKUP_DIR}/mongo/${BACKUP_FILE}"
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
    
    local db_name="${DB_NAME:-$MONGO_DATABASE}"
    
    log "=========================================="
    log "MongoDB Restore"
    log "=========================================="
    log "Container: ${MONGO_CONTAINER}"
    log "Database: ${db_name}"
    log "File: ${BACKUP_FILE}"
    log "Drop existing: ${DROP_EXISTING}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would restore MongoDB database"
        return 0
    fi
    
    local drop_flag=""
    [[ "$DROP_EXISTING" == true ]] && drop_flag="--drop"
    
    "${SCRIPTS_DIR}/restore_mongo.sh" \
        --container "${MONGO_CONTAINER}" \
        --user "${MONGO_ROOT_USERNAME}" \
        --password "${MONGO_ROOT_PASSWORD}" \
        --database "${db_name}" \
        --file "${BACKUP_FILE}" \
        ${drop_flag}
}

# =============================================================================
# LIST BACKUPS
# =============================================================================
list_backups() {
    log "=========================================="
    log "Available Backups"
    log "=========================================="
    
    case $DATABASE in
        postgres)
            log "PostgreSQL backups:"
            ls -lht "${BACKUP_DIR}/postgres/"*.dump 2>/dev/null || echo "  No backups found"
            ;;
        mysql)
            log "MySQL backups:"
            ls -lht "${BACKUP_DIR}/mysql/"*.sql.gz 2>/dev/null || echo "  No backups found"
            ;;
        mongo)
            log "MongoDB backups:"
            ls -lht "${BACKUP_DIR}/mongo/"*.archive.gz 2>/dev/null || echo "  No backups found"
            ;;
        all)
            echo ""
            log "PostgreSQL backups:"
            ls -lht "${BACKUP_DIR}/postgres/"*.dump 2>/dev/null || echo "  No backups found"
            echo ""
            log "MySQL backups:"
            ls -lht "${BACKUP_DIR}/mysql/"*.sql.gz 2>/dev/null || echo "  No backups found"
            echo ""
            log "MongoDB backups:"
            ls -lht "${BACKUP_DIR}/mongo/"*.archive.gz 2>/dev/null || echo "  No backups found"
            ;;
    esac
}

# =============================================================================
# CLEANUP OLD BACKUPS
# =============================================================================
cleanup_backups() {
    log "=========================================="
    log "Cleaning up backups older than ${RETENTION_DAYS} days"
    log "=========================================="
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would delete the following files:"
        find "${BACKUP_DIR}" -type f \( -name "*.dump" -o -name "*.sql.gz" -o -name "*.archive.gz" \) -mtime +${RETENTION_DAYS} 2>/dev/null
        return 0
    fi
    
    local deleted_count=0
    
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted_count++))
        log "Deleted: $file"
    done < <(find "${BACKUP_DIR}" -type f \( -name "*.dump" -o -name "*.sql.gz" -o -name "*.archive.gz" \) -mtime +${RETENTION_DAYS} -print0 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        log "Cleaned up ${deleted_count} old backup(s)"
    else
        log "No old backups to clean up"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
log "=========================================="
log "Backup Orchestrator"
log "=========================================="
log "Command: ${COMMAND}"
log "Environment: ${ENVIRONMENT}"
log "Database: ${DATABASE}"
log "=========================================="

FAILED=0

case $COMMAND in
    dump)
        case $DATABASE in
            postgres) dump_postgres ;;
            mysql) dump_mysql ;;
            mongo) dump_mongo ;;
            all)
                dump_postgres || FAILED=1
                dump_mysql || FAILED=1
                dump_mongo || FAILED=1
                ;;
        esac
        cleanup_backups
        ;;
    restore)
        case $DATABASE in
            postgres) restore_postgres ;;
            mysql) restore_mysql ;;
            mongo) restore_mongo ;;
            all)
                log "ERROR: Cannot restore 'all' databases. Specify one: postgres, mysql, or mongo"
                exit 1
                ;;
        esac
        ;;
    list)
        list_backups
        ;;
    cleanup)
        cleanup_backups
        ;;
esac

# Summary
echo ""
log "=========================================="
if [[ $FAILED -eq 0 ]]; then
    log "SUCCESS: Operation completed!"
else
    log "ERROR: Operation completed with errors"
    exit 1
fi
log "=========================================="

exit 0
