#!/bin/sh
set -eu

PRIMARY_HOST="${POSTGRES_PRIMARY_HOST:?POSTGRES_PRIMARY_HOST is required}"
PRIMARY_PORT="${POSTGRES_PRIMARY_PORT:-5432}"
REPLICATION_USER="${POSTGRES_REPLICATION_USER:?POSTGRES_REPLICATION_USER is required}"
REPLICATION_PASSWORD="${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD is required}"
REPLICATION_SLOT="${POSTGRES_REPLICATION_SLOT:-secondary_slot}"
PGDATA="${PGDATA:-/var/lib/postgresql/data}"

export PGPASSWORD="$REPLICATION_PASSWORD"

mkdir -p "$PGDATA"
chmod 700 "$PGDATA"

if [ "${1:-}" = "postgres" ] && [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "Waiting for primary postgres at ${PRIMARY_HOST}:${PRIMARY_PORT}..."
  until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$REPLICATION_USER" -d postgres >/dev/null 2>&1; do
    sleep 2
  done

  rm -rf "${PGDATA:?}"/*

  if ! pg_basebackup \
    -h "$PRIMARY_HOST" \
    -p "$PRIMARY_PORT" \
    -U "$REPLICATION_USER" \
    -D "$PGDATA" \
    -Fp \
    -Xs \
    -P \
    -R \
    --slot="$REPLICATION_SLOT" \
    --create-slot; then
    echo "Retrying base backup using existing replication slot..."
    rm -rf "${PGDATA:?}"/*
    pg_basebackup \
      -h "$PRIMARY_HOST" \
      -p "$PRIMARY_PORT" \
      -U "$REPLICATION_USER" \
      -D "$PGDATA" \
      -Fp \
      -Xs \
      -P \
      -R \
      --slot="$REPLICATION_SLOT"
  fi

  chown -R postgres:postgres "$PGDATA" 2>/dev/null || true
fi

exec docker-entrypoint.sh "$@"
