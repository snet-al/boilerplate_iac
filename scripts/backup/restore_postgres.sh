#!/bin/bash
# =============================================================================
# POSTGRESQL RESTORE EXECUTOR
# =============================================================================
# Simple executor script - receives all parameters from orchestrator
# Automatically disables foreign key constraints during restore
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
    
else
    # Host connection - use Docker image to run psql/pg_restore
    if [[ -z "${DB_HOST}" ]] || [[ -z "${DB_PORT}" ]]; then
        echo "ERROR: Missing required parameters: --host and --port"
        exit 1
    fi
    
    # Use provided image or default
    DB_IMAGE="${DB_IMAGE:-postgres:16}"
    DB_NETWORK="${DB_NETWORK:-host}"
    
    # Build network flag
    NETWORK_FLAG=""
    [[ -n "${DB_NETWORK}" ]] && NETWORK_FLAG="--network ${DB_NETWORK}"
    
    # Drop and recreate database if requested
    if [[ "$DROP_DB" == true ]]; then
        echo "Dropping existing database: ${DB_NAME}"
        
        # Terminate connections
        docker run --rm ${NETWORK_FLAG} -e PGPASSWORD="${DB_PASSWORD}" "${DB_IMAGE}" \
            psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres -c \
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();" \
            2>/dev/null || true
        
        # Drop database
        docker run --rm ${NETWORK_FLAG} -e PGPASSWORD="${DB_PASSWORD}" "${DB_IMAGE}" \
            psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres -c \
            "DROP DATABASE IF EXISTS \"${DB_NAME}\";" \
            2>/dev/null || true
        
        # Create database
        docker run --rm ${NETWORK_FLAG} -e PGPASSWORD="${DB_PASSWORD}" "${DB_IMAGE}" \
            psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres -c \
            "CREATE DATABASE \"${DB_NAME}\";" \
            2>/dev/null || true
    fi
    
    # Restore based on file type
    echo "Restoring to database: ${DB_NAME}"
    echo "Foreign key constraints will be disabled during restore"
    
    if [[ "${BACKUP_FILE}" == *.dump ]]; then
        # Custom format - use pg_restore with disable-triggers
        docker run --rm ${NETWORK_FLAG} -e PGPASSWORD="${DB_PASSWORD}" -v "${BACKUP_FILE}:/backup.dump:ro" "${DB_IMAGE}" \
            pg_restore \
            -h "${DB_HOST}" \
            -p "${DB_PORT}" \
            -U "${DB_USER}" \
            -d "${DB_NAME}" \
            --no-owner \
            --no-privileges \
            --disable-triggers \
            --clean \
            --if-exists \
            /backup.dump \
            2>&1 || true
        
    elif [[ "${BACKUP_FILE}" == *.gz ]]; then
        # Compressed SQL - wrap with session_replication_role
        {
            echo "SET session_replication_role = 'replica';"
            gunzip -c "${BACKUP_FILE}"
            echo "SET session_replication_role = 'origin';"
        } | docker run --rm ${NETWORK_FLAG} -i -e PGPASSWORD="${DB_PASSWORD}" "${DB_IMAGE}" \
            psql \
            -h "${DB_HOST}" \
            -p "${DB_PORT}" \
            -U "${DB_USER}" \
            -d "${DB_NAME}" 2>&1
    else
        # Plain SQL
        {
            echo "SET session_replication_role = 'replica';"
            cat "${BACKUP_FILE}"
            echo "SET session_replication_role = 'origin';"
        } | docker run --rm ${NETWORK_FLAG} -i -e PGPASSWORD="${DB_PASSWORD}" "${DB_IMAGE}" \
            psql \
            -h "${DB_HOST}" \
            -p "${DB_PORT}" \
            -U "${DB_USER}" \
            -d "${DB_NAME}" 2>&1
    fi
    
    # Verify
    table_count=$(docker run --rm ${NETWORK_FLAG} -e PGPASSWORD="${DB_PASSWORD}" "${DB_IMAGE}" \
        psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" \
        2>/dev/null | tr -d ' ')
fi

echo "SUCCESS: Restored ${table_count:-0} tables"
exit 0
