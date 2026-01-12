#!/bin/bash
# =============================================================================
# MYSQL RESTORE EXECUTOR
# =============================================================================
# Simple executor script - receives all parameters from orchestrator
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
    
    docker exec "${CONTAINER}" \
        mysql --user="${DB_USER}" --password="${DB_PASSWORD}" -e \
        "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" \
        2>/dev/null || true
    
    docker exec "${CONTAINER}" \
        mysql --user="${DB_USER}" --password="${DB_PASSWORD}" -e \
        "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
        2>/dev/null || true
fi

# Restore based on file type
echo "Restoring to database: ${DB_NAME}"

if [[ "${BACKUP_FILE}" == *.gz ]]; then
    # Check if backup contains CREATE DATABASE
    if gunzip -c "${BACKUP_FILE}" | head -100 | grep -q "CREATE DATABASE"; then
        gunzip -c "${BACKUP_FILE}" | docker exec -i "${CONTAINER}" \
            mysql --user="${DB_USER}" --password="${DB_PASSWORD}" 2>&1
    else
        gunzip -c "${BACKUP_FILE}" | docker exec -i "${CONTAINER}" \
            mysql --user="${DB_USER}" --password="${DB_PASSWORD}" "${DB_NAME}" 2>&1
    fi
else
    docker exec -i "${CONTAINER}" \
        mysql --user="${DB_USER}" --password="${DB_PASSWORD}" "${DB_NAME}" < "${BACKUP_FILE}" 2>&1
fi

# Verify
table_count=$(docker exec "${CONTAINER}" \
    mysql --user="${DB_USER}" --password="${DB_PASSWORD}" -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}';" \
    2>/dev/null || echo "0")

echo "SUCCESS: Restored ${table_count:-0} tables"
exit 0
