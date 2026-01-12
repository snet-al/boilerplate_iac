#!/bin/bash
# =============================================================================
# MONGODB RESTORE EXECUTOR
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

# Build restore options
RESTORE_OPTS="--uri=mongodb://${DB_USER}:${DB_PASSWORD}@localhost:27017?authSource=admin"
RESTORE_OPTS+=" --archive --gzip"

[[ "$DROP_DB" == true ]] && RESTORE_OPTS+=" --drop"

# Restore
echo "Restoring to database: ${DB_NAME}"

cat "${BACKUP_FILE}" | docker exec -i "${CONTAINER}" \
    mongorestore ${RESTORE_OPTS} 2>&1

# Verify
collection_count=$(docker exec "${CONTAINER}" \
    mongosh --quiet \
    --username "${DB_USER}" \
    --password "${DB_PASSWORD}" \
    --authenticationDatabase admin \
    "${DB_NAME}" \
    --eval "db.getCollectionNames().length" \
    2>/dev/null || echo "0")

echo "SUCCESS: Restored ${collection_count:-0} collections"
exit 0
