#!/bin/bash
# =============================================================================
# Interactive backup.env / backup.prod.env generator
# =============================================================================
# Run from repository root:
#   bash scripts/backup/setup-backup-env.sh
#   bash scripts/backup/setup-backup-env.sh prod
#   bash scripts/backup/setup-backup-env.sh dev
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

prompt() {
    local def=$2
    local text=$1
    if [[ -n "$def" ]]; then
        read -r -p "${text} [${def}]: " val
        echo "${val:-$def}"
    else
        read -r -p "${text}: " val
        echo "$val"
    fi
}

prompt_secret() {
    read -r -s -p "$1: " val
    echo ""
    echo "$val"
}

choose_env_profile() {
    local a="${1:-}"
    if [[ "$a" == "dev" || "$a" == "prod" ]]; then
        echo "$a"
        return
    fi
    while true; do
        read -r -p "Environment — type dev or prod: " a
        case "${a,,}" in
            dev|development) echo "dev"; return ;;
            prod|production) echo "prod"; return ;;
            *) echo "  Enter dev or prod." ;;
        esac
    done
}

default_port_for_db() {
    case $1 in
        postgres) echo "5432" ;;
        mysql) echo "3306" ;;
        mongo) echo "27017" ;;
        *) echo "" ;;
    esac
}

main() {
    cd "$PROJECT_ROOT"

    local profile
    profile="$(choose_env_profile "${1:-}")"

    local example dest label eflag
    if [[ "$profile" == "prod" ]]; then
        example="${PROJECT_ROOT}/env/backup.prod.env.example"
        dest="${PROJECT_ROOT}/backup.prod.env"
        label="production"
        eflag="prod"
    else
        example="${PROJECT_ROOT}/env/backup.env.example"
        dest="${PROJECT_ROOT}/backup.env"
        label="development"
        eflag="dev"
    fi

    if [[ ! -f "$example" ]]; then
        echo "ERROR: Example file missing: $example"
        exit 1
    fi

    if [[ -f "$dest" ]]; then
        read -r -p "File exists: ${dest#"$PROJECT_ROOT"/}. Overwrite? [y/N]: " ow
        if [[ ! "${ow,,}" =~ ^y(es)?$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    echo ""
    echo "=== Backup configuration (${label}) ==="
    echo ""

    local dbtype
    while true; do
        read -r -p "Database to backup (postgres | mysql | mongo): " dbtype
        dbtype="${dbtype,,}"
        case "$dbtype" in
            postgres|mysql|mongo) break ;;
            *) echo "  Invalid. Use postgres, mysql, or mongo." ;;
        esac
    done

    local conn
    while true; do
        read -r -p "Connection type (docker = docker exec into container | host = TCP, e.g. remote DB): " conn
        conn="${conn,,}"
        case "$conn" in
            docker|host) break ;;
            *) echo "  Enter docker or host." ;;
        esac
    done

    local defport
    defport="$(default_port_for_db "$dbtype")"

    local CONTAINER="" DB_HOST="" DB_PORT="" DB_IMAGE="" DB_NETWORK="host"
    local DB_USER="" DB_PASSWORD="" DB_NAME=""
    local BACKUP_DIR="${PROJECT_ROOT}/backups/data"
    local BACKUP_TYPE="auto"
    local DAILY_RETENTION WEEKLY_RETENTION MONTHLY_RETENTION

    if [[ "$profile" == "prod" ]]; then
        DAILY_RETENTION=7
        WEEKLY_RETENTION=8
        MONTHLY_RETENTION=12
    else
        DAILY_RETENTION=7
        WEEKLY_RETENTION=4
        MONTHLY_RETENTION=12
    fi

    if [[ "$conn" == "docker" ]]; then
        CONTAINER="$(prompt "Docker container name (exact, as in docker ps)" "")"
        [[ -z "$CONTAINER" ]] && echo "ERROR: CONTAINER is required." && exit 1
    else
        DB_HOST="$(prompt "Database host (hostname or IP)" "")"
        DB_PORT="$(prompt "Database port" "$defport")"
        [[ -z "$DB_HOST" ]] && echo "ERROR: DB_HOST is required." && exit 1
        [[ -z "$DB_PORT" ]] && echo "ERROR: DB_PORT is required." && exit 1
        DB_IMAGE="$(prompt "Docker image for mysqldump/psql/mongo tools (empty = backup.sh default)" "")"
        DB_NETWORK="$(prompt "Docker network for host-mode client (host | bridge | custom name)" "host")"
    fi

    DB_USER="$(prompt "Database user" "")"
    DB_PASSWORD="$(prompt_secret "Database password")"
    [[ -z "$DB_USER" ]] && echo "ERROR: DB_USER is required." && exit 1
    [[ -z "$DB_PASSWORD" ]] && echo "ERROR: DB_PASSWORD is required." && exit 1

    DB_NAME="$(prompt "Database name" "")"
    [[ -z "$DB_NAME" ]] && echo "ERROR: DB_NAME is required." && exit 1

    BACKUP_DIR="$(prompt "Backup directory (absolute path recommended)" "$BACKUP_DIR")"
    BACKUP_TYPE="$(prompt "BACKUP_TYPE (auto | daily | weekly | monthly)" "$BACKUP_TYPE")"

    DAILY_RETENTION="$(prompt "DAILY_RETENTION" "$DAILY_RETENTION")"
    WEEKLY_RETENTION="$(prompt "WEEKLY_RETENTION" "$WEEKLY_RETENTION")"
    MONTHLY_RETENTION="$(prompt "MONTHLY_RETENTION" "$MONTHLY_RETENTION")"

    umask 077
    {
        echo "# ============================================================================="
        echo "# BACKUP CONFIGURATION — generated by scripts/backup/setup-backup-env.sh"
        echo "# ============================================================================="
        echo ""
        echo "# BACKUP_SETTINGS"
        printf 'BACKUP_DATABASE=%q\n' "$dbtype"
        printf 'BACKUP_DIR=%q\n' "$BACKUP_DIR"
        printf 'BACKUP_TYPE=%q\n' "$BACKUP_TYPE"
        echo "DAILY_RETENTION=${DAILY_RETENTION}"
        echo "WEEKLY_RETENTION=${WEEKLY_RETENTION}"
        echo "MONTHLY_RETENTION=${MONTHLY_RETENTION}"
        echo ""
        printf 'CONNECTION_TYPE=%q\n' "$conn"
        printf 'ENVIRONMENT=%q\n' "$profile"
        echo ""
        if [[ "$conn" == "docker" ]]; then
            printf 'CONTAINER=%q\n' "$CONTAINER"
            echo "# HOST_MODE_UNUSED"
            printf 'DB_HOST=%q\n' ""
            printf 'DB_PORT=%q\n' "$defport"
            printf 'DB_IMAGE=%q\n' ""
            printf 'DB_NETWORK=%q\n' "host"
        else
            echo "# DOCKER_EXEC_UNUSED"
            printf 'CONTAINER=%q\n' ""
            printf 'DB_HOST=%q\n' "$DB_HOST"
            printf 'DB_PORT=%q\n' "$DB_PORT"
            printf 'DB_IMAGE=%q\n' "$DB_IMAGE"
            printf 'DB_NETWORK=%q\n' "$DB_NETWORK"
        fi
        echo ""
        printf 'DB_USER=%q\n' "$DB_USER"
        printf 'DB_PASSWORD=%q\n' "$DB_PASSWORD"
        printf 'DB_NAME=%q\n' "$DB_NAME"
    } >"$dest"

    chmod 600 "$dest"

    echo ""
    echo "Wrote: $dest"
    echo ""

    build_cron_line() {
        local min=$1 hour=$2
        echo "${min} ${hour} * * * cd ${PROJECT_ROOT} && /bin/bash ./backup.sh dump -e ${eflag} >> ${HOME}/logs/mysql-backup.log 2>&1"
    }

    cron_field_ok() {
        local val=$1 max=$2
        [[ "$val" =~ ^[0-9]+$ ]] && (( val >= 0 && val <= max ))
    }

    append_cron_line_if_wanted() {
        local line=$1
        mkdir -p "${HOME}/logs"
        if crontab -l 2>/dev/null | grep -Fq "backup.sh dump -e ${eflag}"; then
            echo "Cron already contains a backup.sh dump -e ${eflag} line; not appending duplicate."
            return 0
        fi
        (crontab -l 2>/dev/null || true; echo "$line") | crontab -
        echo "Crontab updated. Run: crontab -l"
    }

    echo "--- Next steps (copy/paste), or answer y to run from this script ---"
    echo ""
    echo "1) Dry-run:"
    echo "   cd ${PROJECT_ROOT} && ./backup.sh dump -e ${eflag} --dry-run"
    echo ""
    read -r -p "Run dry-run now? [y/N]: " run_dry
    if [[ "${run_dry,,}" =~ ^y(es)?$ ]]; then
        (cd "${PROJECT_ROOT}" && ./backup.sh dump -e "${eflag}" --dry-run) || echo "(dry-run exited non-zero — check messages above)"
    fi

    echo ""
    echo "2) Real backup:"
    echo "   cd ${PROJECT_ROOT} && ./backup.sh dump -e ${eflag}"
    echo ""
    read -r -p "Run full backup now? [y/N]: " run_full
    if [[ "${run_full,,}" =~ ^y(es)?$ ]]; then
        (cd "${PROJECT_ROOT}" && ./backup.sh dump -e "${eflag}") || echo "(backup exited non-zero — check messages above)"
    fi

    echo ""
    echo "--- Cron scheduling ---"
    echo "  [1] Manual only — show the line; you add it in crontab yourself"
    echo "  [2] Enter minute + hour, then optionally install the line"
    read -r -p "Choose 1 or 2 [1]: " cron_mode
    cron_mode="${cron_mode:-1}"

    local cron_line
    if [[ "$cron_mode" == "2" ]]; then
        local cm ch
        while true; do
            cm="$(prompt "Cron minute (0-59)" "15")"
            ch="$(prompt "Cron hour (0-23, server local time)" "2")"
            if cron_field_ok "$cm" 59 && cron_field_ok "$ch" 23; then
                break
            fi
            echo "  Invalid: minute and hour must be numbers in range."
        done
        cron_line="$(build_cron_line "$cm" "$ch")"
        echo ""
        echo "Cron line:"
        echo "  ${cron_line}"
        echo ""
        read -r -p "Append this line to your crontab now? [y/N]: " docron
        if [[ "${docron,,}" =~ ^y(es)?$ ]]; then
            append_cron_line_if_wanted "$cron_line"
        else
            echo "Skipped. Add it later with: crontab -e"
            echo "Ensure log dir exists: mkdir -p ${HOME}/logs"
        fi
    else
        cron_line="$(build_cron_line 15 2)"
        echo ""
        echo "Do this yourself when ready:"
        echo "  mkdir -p ${HOME}/logs"
        echo "  crontab -e"
        echo "Add one line (example: daily at 02:15 — change first two fields for your schedule):"
        echo "  ${cron_line}"
        echo ""
        echo "Cron uses the server's local timezone. Fields: minute hour * * *"
    fi
}

main "$@"
