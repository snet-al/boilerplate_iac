#!/bin/bash
# =============================================================================
# BACKUP ORCHESTRATION SCRIPT
# =============================================================================
# Central orchestrator for database backup/restore operations
# Configuration is loaded from backup.env or backup.prod.env
#
# Setup:
#   cp env/backup.env.example backup.env
#   cp env/backup.prod.env.example backup.prod.env
#   # Edit the .env files to configure which database to backup
#
# Usage: ./backup.sh <command> [options]
#
# Commands:
#   dump      Backup database configured in backup.env
#   restore   Restore database from backup
#   list      List available backups
#   cleanup   Remove old backups
#
# Options:
#   -e, --env           Environment (dev|prod) - default: dev
#   -n, --name          Override database name from config
#   -f, --file          Backup file for restore (required for restore)
#   -r, --retention     Days to keep backups (overrides env config)
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
DB_NAME_OVERRIDE=""
BACKUP_FILE=""
DROP_EXISTING=false
DRY_RUN=false
COMMAND=""
RESTORE_DATE=""
RESTORE_LATEST=false
RESTORE_TYPE=""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Determine backup type based on current date
determine_backup_type() {
    local backup_type="${BACKUP_TYPE:-auto}"
    
    if [[ "$backup_type" != "auto" ]]; then
        echo "$backup_type"
        return
    fi
    
    # Auto-determine based on day
    local day_of_month=$(date +%d)
    local day_of_week=$(date +%u)  # 1-7 (Monday-Sunday)
    
    # First day of month = monthly backup
    if [[ "$day_of_month" == "01" ]]; then
        echo "monthly"
    # Sunday = weekly backup
    elif [[ "$day_of_week" == "7" ]]; then
        echo "weekly"
    # Any other day = daily backup
    else
        echo "daily"
    fi
}

# Find backup file by date and type
find_backup_by_date() {
    local db_type="$1"  # postgres, mysql, mongo
    local date="$2"     # YYYY-MM-DD
    local type="$3"     # daily, weekly, monthly (optional)
    
    local search_dirs=()
    
    if [[ -n "$type" ]]; then
        search_dirs=("${BACKUP_DIR}/${db_type}/${type}")
    else
        search_dirs=("${BACKUP_DIR}/${db_type}/daily" "${BACKUP_DIR}/${db_type}/weekly" "${BACKUP_DIR}/${db_type}/monthly")
    fi
    
    for dir in "${search_dirs[@]}"; do
        local pattern="${dir}/${date}_${db_type}_*."{dump,sql.gz,archive.gz}
        local found=$(ls ${pattern} 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            echo "$found"
            return 0
        fi
    done
    
    return 1
}

# Get latest backup
get_latest_backup() {
    local db_type="$1"  # postgres, mysql, mongo
    local type="$2"     # daily, weekly, monthly (optional)
    
    local search_dirs=()
    
    if [[ -n "$type" ]]; then
        search_dirs=("${BACKUP_DIR}/${db_type}/${type}")
    else
        search_dirs=("${BACKUP_DIR}/${db_type}/daily" "${BACKUP_DIR}/${db_type}/weekly" "${BACKUP_DIR}/${db_type}/monthly")
    fi
    
    local latest_file=""
    local latest_time=0
    
    for dir in "${search_dirs[@]}"; do
        for file in "${dir}"/*; do
            if [[ -f "$file" ]]; then
                local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
                if [[ $file_time -gt $latest_time ]]; then
                    latest_time=$file_time
                    latest_file="$file"
                fi
            fi
        done
    done
    
    if [[ -n "$latest_file" ]]; then
        echo "$latest_file"
        return 0
    fi
    
    return 1
}

# =============================================================================
# ENVIRONMENT LOADING
# =============================================================================
load_environment() {
    local env="$1"
    
    # Determine which env file to load
    local backup_env_file
    if [[ "$env" == "prod" ]]; then
        backup_env_file="${SCRIPT_DIR}/backup.prod.env"
    else
        backup_env_file="${SCRIPT_DIR}/backup.env"
    fi
    
    # Check if backup env file exists
    if [[ ! -f "$backup_env_file" ]]; then
        log "ERROR: Backup configuration file not found: ${backup_env_file}"
        log "Please copy the example file:"
        if [[ "$env" == "prod" ]]; then
            log "  cp env/backup.prod.env.example backup.prod.env"
        else
            log "  cp env/backup.env.example backup.env"
        fi
        exit 1
    fi
    
    # Load backup configuration
    log "Loading backup configuration from: ${backup_env_file}"
    set -a
    source "$backup_env_file"
    set +a
    
    # Validate BACKUP_DATABASE setting
    if [[ -z "${BACKUP_DATABASE:-}" ]] || [[ "${BACKUP_DATABASE}" == "none" ]]; then
        log "ERROR: BACKUP_DATABASE not configured in ${backup_env_file}"
        log "Please set BACKUP_DATABASE to one of: postgres, mysql, mongo"
        exit 1
    fi
    
    if [[ ! "${BACKUP_DATABASE}" =~ ^(postgres|mysql|mongo)$ ]]; then
        log "ERROR: Invalid BACKUP_DATABASE value: ${BACKUP_DATABASE}"
        log "Must be one of: postgres, mysql, mongo"
        exit 1
    fi
    
    # Validate CONNECTION_TYPE
    CONNECTION_TYPE="${CONNECTION_TYPE:-docker}"
    if [[ ! "${CONNECTION_TYPE}" =~ ^(docker|host)$ ]]; then
        log "ERROR: Invalid CONNECTION_TYPE value: ${CONNECTION_TYPE}"
        log "Must be one of: docker, host"
        exit 1
    fi
    
    # Validate connection-specific settings
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        if [[ -z "${CONTAINER:-}" ]]; then
            log "ERROR: CONTAINER not set for docker connection type"
            exit 1
        fi
    else
        if [[ -z "${DB_HOST:-}" ]]; then
            log "ERROR: DB_HOST not set for host connection type"
            exit 1
        fi
        if [[ -z "${DB_PORT:-}" ]]; then
            log "ERROR: DB_PORT not set for host connection type"
            exit 1
        fi
        
        # Handle DB_IMAGE: can be full image or service name
        if [[ -z "${DB_IMAGE:-}" ]]; then
            # Set default images if not specified
            case $BACKUP_DATABASE in
                postgres) DB_IMAGE="postgres:16" ;;
                mysql) DB_IMAGE="mysql:8.0" ;;
                mongo) DB_IMAGE="mongo:7" ;;
            esac
        elif [[ ! "${DB_IMAGE}" =~ [:\/] ]]; then
            # Looks like a service name - get image from that service's container
            local service_container="${COMPOSE_PROJECT_NAME:-dev}_${DB_IMAGE}"
            DB_IMAGE=$(docker inspect --format='{{.Config.Image}}' "${service_container}" 2>/dev/null || echo "${DB_IMAGE}")
        fi
        
        # Set default network if not specified
        DB_NETWORK="${DB_NETWORK:-host}"
        
        log "Using Docker image: ${DB_IMAGE}"
        log "Using Docker network: ${DB_NETWORK}"
    fi
    
    # Set retention defaults
    DAILY_RETENTION="${DAILY_RETENTION:-7}"
    WEEKLY_RETENTION="${WEEKLY_RETENTION:-4}"
    MONTHLY_RETENTION="${MONTHLY_RETENTION:-12}"
    
    # Determine backup type
    CURRENT_BACKUP_TYPE=$(determine_backup_type)
    
    # Use DB_NAME_OVERRIDE if provided via CLI
    if [[ -n "${DB_NAME_OVERRIDE:-}" ]]; then
        DB_NAME="${DB_NAME_OVERRIDE}"
    fi
    
    log "Configured database: ${BACKUP_DATABASE}"
    log "Connection type: ${CONNECTION_TYPE}"
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        log "Container: ${CONTAINER}"
    else
        log "Host: ${DB_HOST}:${DB_PORT}"
    fi
    log "Database: ${DB_NAME}"
}

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================
if [[ $# -eq 0 ]]; then
    echo "Usage: ./backup.sh <dump|restore|list|cleanup> [options]"
    exit 0
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
        -n|--name)
            DB_NAME_OVERRIDE="$2"
            shift 2
            ;;
        -f|--file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        --date)
            RESTORE_DATE="$2"
            shift 2
            ;;
        --latest)
            RESTORE_LATEST=true
            shift
            ;;
        --type)
            RESTORE_TYPE="$2"
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
            echo "Usage: ./backup.sh <dump|restore|list|cleanup> [options]"
            exit 0
            ;;
        *)
            log "ERROR: Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate command
if [[ ! "$COMMAND" =~ ^(dump|restore|list|cleanup)$ ]]; then
    log "ERROR: Invalid command: $COMMAND. Must be: dump|restore|list|cleanup"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    log "ERROR: Invalid environment: $ENVIRONMENT. Must be 'dev' or 'prod'."
    exit 1
fi

# Load environment configuration
load_environment "$ENVIRONMENT"

# Create backup directories with rotation structure
for db_type in postgres mysql mongo; do
    mkdir -p "${BACKUP_DIR}/${db_type}/daily"
    mkdir -p "${BACKUP_DIR}/${db_type}/weekly"
    mkdir -p "${BACKUP_DIR}/${db_type}/monthly"
done

# =============================================================================
# DUMP FUNCTIONS
# =============================================================================
dump_postgres() {
    local date_stamp=$(date +%Y-%m-%d)
    local output_file="${BACKUP_DIR}/postgres/${CURRENT_BACKUP_TYPE}/${date_stamp}_postgres_${DB_NAME}.dump"
    
    log "=========================================="
    log "PostgreSQL Dump (${CURRENT_BACKUP_TYPE})"
    log "=========================================="
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        log "Container: ${CONTAINER}"
    else
        log "Host: ${DB_HOST}:${DB_PORT}"
    fi
    log "Database: ${DB_NAME}"
    log "Backup type: ${CURRENT_BACKUP_TYPE}"
    log "Output: ${output_file}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would dump PostgreSQL database"
        return 0
    fi
    
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        "${SCRIPTS_DIR}/dump_postgres.sh" \
            --connection-type "docker" \
            --container "${CONTAINER}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --output "${output_file}"
    else
        "${SCRIPTS_DIR}/dump_postgres.sh" \
            --connection-type "host" \
            --host "${DB_HOST}" \
            --port "${DB_PORT}" \
            --image "${DB_IMAGE}" \
            --network "${DB_NETWORK}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --output "${output_file}"
    fi
}

dump_mysql() {
    local date_stamp=$(date +%Y-%m-%d)
    local output_file="${BACKUP_DIR}/mysql/${CURRENT_BACKUP_TYPE}/${date_stamp}_mysql_${DB_NAME}.sql.gz"
    
    log "=========================================="
    log "MySQL Dump (${CURRENT_BACKUP_TYPE})"
    log "=========================================="
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        log "Container: ${CONTAINER}"
    else
        log "Host: ${DB_HOST}:${DB_PORT}"
    fi
    log "Database: ${DB_NAME}"
    log "Backup type: ${CURRENT_BACKUP_TYPE}"
    log "Output: ${output_file}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would dump MySQL database"
        return 0
    fi
    
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        "${SCRIPTS_DIR}/dump_mysql.sh" \
            --connection-type "docker" \
            --container "${CONTAINER}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --output "${output_file}"
    else
        "${SCRIPTS_DIR}/dump_mysql.sh" \
            --connection-type "host" \
            --host "${DB_HOST}" \
            --port "${DB_PORT}" \
            --image "${DB_IMAGE}" \
            --network "${DB_NETWORK}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --output "${output_file}"
    fi
}

dump_mongo() {
    local date_stamp=$(date +%Y-%m-%d)
    local output_file="${BACKUP_DIR}/mongo/${CURRENT_BACKUP_TYPE}/${date_stamp}_mongo_${DB_NAME}.archive.gz"
    
    log "=========================================="
    log "MongoDB Dump (${CURRENT_BACKUP_TYPE})"
    log "=========================================="
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        log "Container: ${CONTAINER}"
    else
        log "Host: ${DB_HOST}:${DB_PORT}"
    fi
    log "Database: ${DB_NAME}"
    log "Backup type: ${CURRENT_BACKUP_TYPE}"
    log "Output: ${output_file}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would dump MongoDB database"
        return 0
    fi
    
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        "${SCRIPTS_DIR}/dump_mongo.sh" \
            --connection-type "docker" \
            --container "${CONTAINER}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --output "${output_file}"
    else
        "${SCRIPTS_DIR}/dump_mongo.sh" \
            --connection-type "host" \
            --host "${DB_HOST}" \
            --port "${DB_PORT}" \
            --image "${DB_IMAGE}" \
            --network "${DB_NETWORK}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --output "${output_file}"
    fi
}

# =============================================================================
# RESTORE FUNCTIONS
# =============================================================================
restore_postgres() {
    # Determine backup file to restore
    if [[ "$RESTORE_LATEST" == true ]]; then
        log "Finding latest PostgreSQL backup..."
        BACKUP_FILE=$(get_latest_backup "postgres" "${RESTORE_TYPE}")
        if [[ -z "$BACKUP_FILE" ]]; then
            log "ERROR: No backup found"
            exit 1
        fi
        log "Using latest backup: ${BACKUP_FILE}"
    elif [[ -n "$RESTORE_DATE" ]]; then
        log "Finding PostgreSQL backup for date: ${RESTORE_DATE}..."
        BACKUP_FILE=$(find_backup_by_date "postgres" "${RESTORE_DATE}" "${RESTORE_TYPE}")
        if [[ -z "$BACKUP_FILE" ]]; then
            log "ERROR: No backup found for date: ${RESTORE_DATE}"
            exit 1
        fi
        log "Using backup: ${BACKUP_FILE}"
    elif [[ -z "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file required. Use -f, --date, or --latest"
        exit 1
    fi
    
    # Resolve backup file path if just filename provided
    if [[ ! -f "$BACKUP_FILE" ]]; then
        # Try all subdirectories
        for type_dir in daily weekly monthly; do
            if [[ -f "${BACKUP_DIR}/postgres/${type_dir}/${BACKUP_FILE}" ]]; then
                BACKUP_FILE="${BACKUP_DIR}/postgres/${type_dir}/${BACKUP_FILE}"
                break
            fi
        done
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
    
    log "=========================================="
    log "PostgreSQL Restore"
    log "=========================================="
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        log "Container: ${CONTAINER}"
    else
        log "Host: ${DB_HOST}:${DB_PORT}"
    fi
    log "Database: ${DB_NAME}"
    log "File: ${BACKUP_FILE}"
    log "Drop existing: ${DROP_EXISTING}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would restore PostgreSQL database"
        return 0
    fi
    
    local drop_flag=""
    [[ "$DROP_EXISTING" == true ]] && drop_flag="--drop"
    
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        "${SCRIPTS_DIR}/restore_postgres.sh" \
            --connection-type "docker" \
            --container "${CONTAINER}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --file "${BACKUP_FILE}" \
            ${drop_flag}
    else
        "${SCRIPTS_DIR}/restore_postgres.sh" \
            --connection-type "host" \
            --host "${DB_HOST}" \
            --port "${DB_PORT}" \
            --image "${DB_IMAGE}" \
            --network "${DB_NETWORK}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --file "${BACKUP_FILE}" \
            ${drop_flag}
    fi
}

restore_mysql() {
    # Determine backup file to restore
    if [[ "$RESTORE_LATEST" == true ]]; then
        log "Finding latest MySQL backup..."
        BACKUP_FILE=$(get_latest_backup "mysql" "${RESTORE_TYPE}")
        if [[ -z "$BACKUP_FILE" ]]; then
            log "ERROR: No backup found"
            exit 1
        fi
        log "Using latest backup: ${BACKUP_FILE}"
    elif [[ -n "$RESTORE_DATE" ]]; then
        log "Finding MySQL backup for date: ${RESTORE_DATE}..."
        BACKUP_FILE=$(find_backup_by_date "mysql" "${RESTORE_DATE}" "${RESTORE_TYPE}")
        if [[ -z "$BACKUP_FILE" ]]; then
            log "ERROR: No backup found for date: ${RESTORE_DATE}"
            exit 1
        fi
        log "Using backup: ${BACKUP_FILE}"
    elif [[ -z "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file required. Use -f, --date, or --latest"
        exit 1
    fi
    
    # Resolve backup file path if just filename provided
    if [[ ! -f "$BACKUP_FILE" ]]; then
        # Try all subdirectories
        for type_dir in daily weekly monthly; do
            if [[ -f "${BACKUP_DIR}/mysql/${type_dir}/${BACKUP_FILE}" ]]; then
                BACKUP_FILE="${BACKUP_DIR}/mysql/${type_dir}/${BACKUP_FILE}"
                break
            fi
        done
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
    
    log "=========================================="
    log "MySQL Restore"
    log "=========================================="
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        log "Container: ${CONTAINER}"
    else
        log "Host: ${DB_HOST}:${DB_PORT}"
    fi
    log "Database: ${DB_NAME}"
    log "File: ${BACKUP_FILE}"
    log "Drop existing: ${DROP_EXISTING}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would restore MySQL database"
        return 0
    fi
    
    local drop_flag=""
    [[ "$DROP_EXISTING" == true ]] && drop_flag="--drop"
    
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        "${SCRIPTS_DIR}/restore_mysql.sh" \
            --connection-type "docker" \
            --container "${CONTAINER}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --file "${BACKUP_FILE}" \
            ${drop_flag}
    else
        "${SCRIPTS_DIR}/restore_mysql.sh" \
            --connection-type "host" \
            --host "${DB_HOST}" \
            --port "${DB_PORT}" \
            --image "${DB_IMAGE}" \
            --network "${DB_NETWORK}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --file "${BACKUP_FILE}" \
            ${drop_flag}
    fi
}

restore_mongo() {
    # Determine backup file to restore
    if [[ "$RESTORE_LATEST" == true ]]; then
        log "Finding latest MongoDB backup..."
        BACKUP_FILE=$(get_latest_backup "mongo" "${RESTORE_TYPE}")
        if [[ -z "$BACKUP_FILE" ]]; then
            log "ERROR: No backup found"
            exit 1
        fi
        log "Using latest backup: ${BACKUP_FILE}"
    elif [[ -n "$RESTORE_DATE" ]]; then
        log "Finding MongoDB backup for date: ${RESTORE_DATE}..."
        BACKUP_FILE=$(find_backup_by_date "mongo" "${RESTORE_DATE}" "${RESTORE_TYPE}")
        if [[ -z "$BACKUP_FILE" ]]; then
            log "ERROR: No backup found for date: ${RESTORE_DATE}"
            exit 1
        fi
        log "Using backup: ${BACKUP_FILE}"
    elif [[ -z "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file required. Use -f, --date, or --latest"
        exit 1
    fi
    
    # Resolve backup file path if just filename provided
    if [[ ! -f "$BACKUP_FILE" ]]; then
        # Try all subdirectories
        for type_dir in daily weekly monthly; do
            if [[ -f "${BACKUP_DIR}/mongo/${type_dir}/${BACKUP_FILE}" ]]; then
                BACKUP_FILE="${BACKUP_DIR}/mongo/${type_dir}/${BACKUP_FILE}"
                break
            fi
        done
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log "ERROR: Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
    
    log "=========================================="
    log "MongoDB Restore"
    log "=========================================="
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        log "Container: ${CONTAINER}"
    else
        log "Host: ${DB_HOST}:${DB_PORT}"
    fi
    log "Database: ${DB_NAME}"
    log "File: ${BACKUP_FILE}"
    log "Drop existing: ${DROP_EXISTING}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would restore MongoDB database"
        return 0
    fi
    
    local drop_flag=""
    [[ "$DROP_EXISTING" == true ]] && drop_flag="--drop"
    
    if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
        "${SCRIPTS_DIR}/restore_mongo.sh" \
            --connection-type "docker" \
            --container "${CONTAINER}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --file "${BACKUP_FILE}" \
            ${drop_flag}
    else
        "${SCRIPTS_DIR}/restore_mongo.sh" \
            --connection-type "host" \
            --host "${DB_HOST}" \
            --port "${DB_PORT}" \
            --image "${DB_IMAGE}" \
            --network "${DB_NETWORK}" \
            --user "${DB_USER}" \
            --password "${DB_PASSWORD}" \
            --database "${DB_NAME}" \
            --file "${BACKUP_FILE}" \
            ${drop_flag}
    fi
}

# =============================================================================
# LIST BACKUPS
# =============================================================================
list_backups() {
    log "=========================================="
    log "Available Backups (Organized by Type)"
    log "=========================================="
    
    for db_type in postgres mysql mongo; do
        echo ""
        log "${db_type^^} Backups:"
        for backup_type in daily weekly monthly; do
            echo "  ${backup_type^}:"
            local count=$(find "${BACKUP_DIR}/${db_type}/${backup_type}" -type f 2>/dev/null | wc -l)
            if [[ $count -gt 0 ]]; then
                ls -lht "${BACKUP_DIR}/${db_type}/${backup_type}/"* 2>/dev/null | head -5 | while read -r line; do
                    echo "    $line"
                done
                [[ $count -gt 5 ]] && echo "    ... and $((count - 5)) more"
            else
                echo "    No backups found"
            fi
        done
    done
}

# =============================================================================
# CLEANUP OLD BACKUPS (Rotation Strategy)
# =============================================================================
cleanup_backups() {
    log "=========================================="
    log "Cleaning up backups based on rotation policy"
    log "=========================================="
    log "Daily retention: ${DAILY_RETENTION} backups"
    log "Weekly retention: ${WEEKLY_RETENTION} backups"
    log "Monthly retention: ${MONTHLY_RETENTION} backups"
    log "=========================================="
    
    local total_deleted=0
    
    for db_type in postgres mysql mongo; do
        for backup_type in daily weekly monthly; do
            local backup_dir="${BACKUP_DIR}/${db_type}/${backup_type}"
            
            # Determine retention count based on type
            local retention_count
            case $backup_type in
                daily) retention_count=$DAILY_RETENTION ;;
                weekly) retention_count=$WEEKLY_RETENTION ;;
                monthly) retention_count=$MONTHLY_RETENTION ;;
            esac
            
            # Get list of backups sorted by modification time (newest first)
            local backups=($(ls -t "${backup_dir}"/* 2>/dev/null))
            local backup_count=${#backups[@]}
            
            if [[ $backup_count -gt $retention_count ]]; then
                log "Cleaning ${db_type} ${backup_type} backups (keeping ${retention_count}, removing $((backup_count - retention_count)))"
                
                # Delete old backups (keep only retention_count newest)
                for ((i=retention_count; i<backup_count; i++)); do
                    if [[ "$DRY_RUN" == true ]]; then
                        log "DRY-RUN: Would delete: ${backups[$i]}"
                    else
                        rm -f "${backups[$i]}"
                        log "Deleted: ${backups[$i]}"
                        ((total_deleted++))
                    fi
                done
            fi
        done
    done
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: No files actually deleted"
    elif [[ $total_deleted -gt 0 ]]; then
        log "Cleaned up ${total_deleted} old backup(s)"
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
log "Database Type: ${BACKUP_DATABASE}"
log "=========================================="

FAILED=0

case $COMMAND in
    dump)
        case $BACKUP_DATABASE in
            postgres) dump_postgres || FAILED=1 ;;
            mysql) dump_mysql || FAILED=1 ;;
            mongo) dump_mongo || FAILED=1 ;;
        esac
        cleanup_backups
        ;;
    restore)
        case $BACKUP_DATABASE in
            postgres) restore_postgres ;;
            mysql) restore_mysql ;;
            mongo) restore_mongo ;;
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
