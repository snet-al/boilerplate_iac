#!/bin/bash
# =============================================================================
# MONGODB DUMP EXECUTOR
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
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate required params
for var in CONNECTION_TYPE DB_USER DB_PASSWORD DB_NAME OUTPUT_FILE; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Missing required parameter: --${var,,}"
        exit 1
    fi
done

# Create output directory
mkdir -p "$(dirname "${OUTPUT_FILE}")"

# Execute dump based on connection type
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
    
    # Execute dump via docker exec
    if docker exec "${CONTAINER}" \
        mongodump \
        --uri="mongodb://${DB_USER}:${DB_PASSWORD}@localhost:27017/${DB_NAME}?authSource=admin" \
        --archive \
        --gzip \
        2>/dev/null > "${OUTPUT_FILE}"; then
        
        if [[ -s "${OUTPUT_FILE}" ]]; then
            size=$(du -h "${OUTPUT_FILE}" | cut -f1)
            echo "SUCCESS: ${OUTPUT_FILE} (${size})"
            exit 0
        fi
    fi
    
else
    # Host connection - use Docker image to run mongodump
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
    
    # Execute dump via Docker image (no need to install mongodump on host)
    if docker run --rm ${NETWORK_FLAG} "${DB_IMAGE}" \
        mongodump \
        --uri="mongodb://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?authSource=admin" \
        --archive \
        --gzip \
        2>/dev/null > "${OUTPUT_FILE}"; then
        
        if [[ -s "${OUTPUT_FILE}" ]]; then
            size=$(du -h "${OUTPUT_FILE}" | cut -f1)
            echo "SUCCESS: ${OUTPUT_FILE} (${size})"
            exit 0
        fi
    fi
fi

echo "ERROR: Dump failed"
rm -f "${OUTPUT_FILE}"
exit 1
