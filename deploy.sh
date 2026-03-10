#!/bin/bash
# =============================================================================
# DEPLOY.SH - Docker Compose Deployment
# =============================================================================
# Deploys a client (env/<client>) with docker-compose using env files
# directly from the client folder. For Kubernetes use k.sh.
#
# Usage: ./deploy.sh -c <client> [options]
#
# Options:
#   -c, --client      Client name (folder inside env/) - required
#   -s, --site        Site: primary|secondary (default: primary)
#   -a, --apps        Comma-separated list of apps to deploy (default: all)
# =============================================================================

set -e

CLIENT=""
SITE="primary"
APPS=""
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$PROJECT_ROOT/env"

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--client) CLIENT="$2"; shift 2 ;;
        -s|--site) SITE="$2"; shift 2 ;;
        -a|--apps) APPS="$2"; shift 2 ;;
        *) echo "Error: Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$CLIENT" ]] && echo "Error: Client required (-c)" && exit 1

CLIENT_ENV_DIR="$ENV_DIR/$CLIENT"
if [[ ! -d "$CLIENT_ENV_DIR" ]]; then
    CLIENT_ENV_DIR="$ENV_DIR/client"
    [[ ! -d "$CLIENT_ENV_DIR" ]] && echo "Error: Client not found: $CLIENT and fallback env/client is missing" && exit 1
    echo "Client '$CLIENT' not found, using fallback: env/client"
fi
[[ "$SITE" != "primary" && "$SITE" != "secondary" ]] && echo "Error: Invalid site" && exit 1

compose_file="docker-compose.${SITE}.yaml"
[[ ! -f "$PROJECT_ROOT/$compose_file" ]] && echo "Error: $compose_file not found" && exit 1

echo "Deploying $CLIENT -> $SITE"

export COMPOSE_PROJECT_NAME="${CLIENT}-${SITE}"
export ENV_DIR="$CLIENT_ENV_DIR"
compose_cmd="docker-compose -f $PROJECT_ROOT/$compose_file"
apps_to_deploy=""
[[ -n "$APPS" ]] && IFS=',' read -ra APP_ARRAY <<< "$APPS" && apps_to_deploy="${APP_ARRAY[*]}"

eval "$compose_cmd up -d $apps_to_deploy"
eval "$compose_cmd ps"

echo "Done! Run ./monitor.sh -s $SITE to check status"
