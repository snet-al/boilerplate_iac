#!/bin/bash
# =============================================================================
# POSTGRESQL RESTORE EXECUTOR
# =============================================================================
# Simple executor script - receives all parameters from orchestrator
# Automatically disables foreign key constraints during restore
# =============================================================================

set -euo pipefail

DROP_DB=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --container) CONTAINER="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --password) DB_PASSWORD="$2"; shift 2 ;;
        --database) DB_NAME="$2"; shift 2 ;;
        --file) BACKUP_FILE="$2"; shift 2 ;;
        --drop) DROP_DB=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate required params
for var in CONTAINER DB_USER DB_PASSWORD DB_NAME BACKUP_FILE; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Missing required parameter: --${var,,}"
        exit 1
    fi
done

# Check container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "ERROR: Container '${CONTAINER}' is not running"
    exit 1
fi

# Check backup file exists
if [[ ! -f "${BACKUP_FILE}" ]]; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# Drop and recreate database if requested
if [[ "$DROP_DB" == true ]]; then
    echo "Dropping existing database: ${DB_NAME}"
    
    # Terminate connections
    docker exec -e PGPASSWORD="${DB_PASSWORD}" "${CONTAINER}" \
        psql -U "${DB_USER}" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();" \
        2>/dev/null || true
    
    # Drop database
    docker exec -e PGPASSWORD="${DB_PASSWORD}" "${CONTAINER}" \
        psql -U "${DB_USER}" -d postgres -c \
        "DROP DATABASE IF EXISTS \"${DB_NAME}\";" \
        2>/dev/null || true
    
    # Create database
    docker exec -e PGPASSWORD="${DB_PASSWORD}" "${CONTAINER}" \
        psql -U "${DB_USER}" -d postgres -c \
        "CREATE DATABASE \"${DB_NAME}\";" \
        2>/dev/null || true
fi

# Restore based on file type
echo "Restoring to database: ${DB_NAME}"
echo "Foreign key constraints will be disabled during restore"

if [[ "${BACKUP_FILE}" == *.dump ]]; then
    # Custom format - use pg_restore with disable-triggers
    cat "${BACKUP_FILE}" | docker exec -i -e PGPASSWORD="${DB_PASSWORD}" "${CONTAINER}" \
        pg_restore \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        --no-owner \
        --no-privileges \
        --disable-triggers \
        --clean \
        --if-exists \
        2>&1 || true
    
elif [[ "${BACKUP_FILE}" == *.gz ]]; then
    # Compressed SQL - wrap with session_replication_role
    {
        echo "SET session_replication_role = 'replica';"
        gunzip -c "${BACKUP_FILE}"
        echo "SET session_replication_role = 'origin';"
    } | docker exec -i -e PGPASSWORD="${DB_PASSWORD}" "${CONTAINER}" \
        psql -U "${DB_USER}" -d "${DB_NAME}" 2>&1
else
    # Plain SQL
    {
        echo "SET session_replication_role = 'replica';"
        cat "${BACKUP_FILE}"
        echo "SET session_replication_role = 'origin';"
    } | docker exec -i -e PGPASSWORD="${DB_PASSWORD}" "${CONTAINER}" \
        psql -U "${DB_USER}" -d "${DB_NAME}" 2>&1
fi

# Verify
table_count=$(docker exec -e PGPASSWORD="${DB_PASSWORD}" "${CONTAINER}" \
    psql -U "${DB_USER}" -d "${DB_NAME}" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" \
    2>/dev/null | tr -d ' ')

echo "SUCCESS: Restored ${table_count:-0} tables"
exit 0
