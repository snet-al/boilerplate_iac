#!/bin/bash
# =============================================================================
# MONGODB RESTORE EXECUTOR
# =============================================================================
# Simple executor script - receives all parameters from orchestrator
# Supports both Docker container and host connections
# =============================================================================

set -euo pipefail

CONNECTION_TYPE=""
CONTAINER=""
DB_HOST=""
DB_PORT=""
DB_IMAGE=""
DB_NETWORK=""
DROP_DB=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --connection-type) CONNECTION_TYPE="$2"; shift 2 ;;
        --container) CONTAINER="$2"; shift 2 ;;
        --host) DB_HOST="$2"; shift 2 ;;
        --port) DB_PORT="$2"; shift 2 ;;
        --image) DB_IMAGE="$2"; shift 2 ;;
        --network) DB_NETWORK="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --password) DB_PASSWORD="$2"; shift 2 ;;
        --database) DB_NAME="$2"; shift 2 ;;
        --file) BACKUP_FILE="$2"; shift 2 ;;
        --drop) DROP_DB=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate required params
for var in CONNECTION_TYPE DB_USER DB_PASSWORD DB_NAME BACKUP_FILE; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Missing required parameter: --${var,,}"
        exit 1
    fi
done

# Check backup file exists
if [[ ! -f "${BACKUP_FILE}" ]]; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# Restore based on connection type
if [[ "${CONNECTION_TYPE}" == "docker" ]]; then
    # Docker container connection
    if [[ -z "${CONTAINER}" ]]; then
        echo "ERROR: Missing required parameter: --container"
        exit 1
    fi
    
    # Check container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo "ERROR: Container '${CONTAINER}' is not running"
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
    
else
    # Host connection - use Docker image to run mongorestore
    if [[ -z "${DB_HOST}" ]] || [[ -z "${DB_PORT}" ]]; then
        echo "ERROR: Missing required parameters: --host and --port"
        exit 1
    fi
    
    # Use provided image or default
    DB_IMAGE="${DB_IMAGE:-mongo:7}"
    DB_NETWORK="${DB_NETWORK:-host}"
    
    # Build network flag
    NETWORK_FLAG=""
    [[ -n "${DB_NETWORK}" ]] && NETWORK_FLAG="--network ${DB_NETWORK}"
    
    # Build restore options
    RESTORE_OPTS="--uri=mongodb://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}?authSource=admin"
    RESTORE_OPTS+=" --archive --gzip"
    
    [[ "$DROP_DB" == true ]] && RESTORE_OPTS+=" --drop"
    
    # Restore
    echo "Restoring to database: ${DB_NAME}"
    
    cat "${BACKUP_FILE}" | docker run --rm ${NETWORK_FLAG} -i "${DB_IMAGE}" \
        mongorestore ${RESTORE_OPTS} 2>&1
    
    # Verify
    collection_count=$(docker run --rm ${NETWORK_FLAG} "${DB_IMAGE}" \
        mongosh --quiet \
        --host "${DB_HOST}" \
        --port "${DB_PORT}" \
        --username "${DB_USER}" \
        --password "${DB_PASSWORD}" \
        --authenticationDatabase admin \
        "${DB_NAME}" \
        --eval "db.getCollectionNames().length" \
        2>/dev/null || echo "0")
fi

echo "SUCCESS: Restored ${collection_count:-0} collections"
exit 0
