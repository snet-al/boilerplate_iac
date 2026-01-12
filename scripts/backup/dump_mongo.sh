#!/bin/bash
# =============================================================================
# MONGODB DUMP EXECUTOR
# =============================================================================
# Simple executor script - receives all parameters from orchestrator
# =============================================================================

set -euo pipefail

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --container) CONTAINER="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --password) DB_PASSWORD="$2"; shift 2 ;;
        --database) DB_NAME="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate required params
for var in CONTAINER DB_USER DB_PASSWORD DB_NAME OUTPUT_FILE; do
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

# Create output directory
mkdir -p "$(dirname "${OUTPUT_FILE}")"

# Execute dump
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

echo "ERROR: Dump failed"
rm -f "${OUTPUT_FILE}"
exit 1
