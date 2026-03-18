#!/bin/bash
set -e

# =============================================================================
# Ensure the PostgreSQL replication role exists on a running primary.
#
# Init scripts in /docker-entrypoint-initdb.d only run on first initialization
# of an empty data directory. This script handles the migration case where the
# primary already has data and needs the replication role created or updated.
#
# Usage: ./ensure-replication-user.sh <env-file> <compose-args...>
#   env-file       Path to the deployed .env.postgres file
#   compose-args   Arguments forwarded to docker-compose (e.g. -f compose.yaml)
#
# Example:
#   ./ensure-replication-user.sh .deploy/acme/.env.postgres -f docker-compose.primary.yaml
# =============================================================================

POSTGRES_ENV="${1:?Usage: $0 <env-file> <compose-args...>}"
shift
COMPOSE_ARGS=("$@")

[[ ! -f "$POSTGRES_ENV" ]] && exit 0

REPL_USER=$(grep -m1 '^POSTGRES_REPLICATION_USER=' "$POSTGRES_ENV" | cut -d= -f2-)
REPL_PASS=$(grep -m1 '^POSTGRES_REPLICATION_PASSWORD=' "$POSTGRES_ENV" | cut -d= -f2-)
PG_USER=$(grep -m1 '^POSTGRES_USER=' "$POSTGRES_ENV" | cut -d= -f2-)

if [[ -z "$REPL_USER" || -z "$REPL_PASS" || -z "$PG_USER" ]]; then
    echo "Warning: Replication env vars missing in $POSTGRES_ENV, skipping"
    exit 0
fi

echo "Waiting for postgres-primary to accept connections..."
attempts=0
while [[ $attempts -lt 30 ]]; do
    if docker-compose "${COMPOSE_ARGS[@]}" exec -T postgres-primary \
        pg_isready -U "$PG_USER" >/dev/null 2>&1; then
        break
    fi
    sleep 2
    ((attempts++))
done

if [[ $attempts -ge 30 ]]; then
    echo "Warning: postgres-primary not ready after 60s, skipping replication user verification"
    exit 0
fi

echo "Ensuring PostgreSQL replication role exists..."
docker-compose "${COMPOSE_ARGS[@]}" exec -T postgres-primary \
    psql -U "$PG_USER" -d postgres -v ON_ERROR_STOP=1 \
    --set replication_user="$REPL_USER" \
    --set replication_password="$REPL_PASS" <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'replication_user') THEN
        EXECUTE format(
            'CREATE ROLE %I WITH REPLICATION LOGIN PASSWORD %L',
            :'replication_user',
            :'replication_password'
        );
        RAISE NOTICE 'Created replication role: %', :'replication_user';
    ELSE
        EXECUTE format(
            'ALTER ROLE %I WITH REPLICATION LOGIN PASSWORD %L',
            :'replication_user',
            :'replication_password'
        );
        RAISE NOTICE 'Updated replication role: %', :'replication_user';
    END IF;
END
$$;
SQL
echo "PostgreSQL replication role ready"
