#!/bin/sh
set -eu

TEMPLATE_PATH="/etc/postgresql/pg_hba.conf.template"
RENDERED_PATH="/tmp/postgresql/pg_hba.conf"
SECONDARY_CIDR="${POSTGRES_SECONDARY_HOST:-0.0.0.0/0}"

case "$SECONDARY_CIDR" in
  */*) ;;
  "") SECONDARY_CIDR="0.0.0.0/0" ;;
  *) SECONDARY_CIDR="${SECONDARY_CIDR}/32" ;;
esac

mkdir -p "$(dirname "$RENDERED_PATH")"
sed "s#__POSTGRES_SECONDARY_CIDR__#${SECONDARY_CIDR}#g" "$TEMPLATE_PATH" > "$RENDERED_PATH"

exec docker-entrypoint.sh "$@"
