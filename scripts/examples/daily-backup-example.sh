#!/bin/bash

###############################################################################
# Daily Backup Example - "The Son"
#
# Public-safe example script for a Docker-based homelab.
#
# Purpose:
#   Demonstrates a daily backup workflow for critical homelab services.
#
# Notes:
#   - Replace placeholder paths, container names, and credential file locations.
#   - Do not commit real secrets, tokens, passwords, or internal host details.
###############################################################################

set -Eeuo pipefail

trap 'echo "[ERROR] Backup failed on line $LINENO"; cleanup; disable_maintenance_mode; exit 1' ERR

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

HOMELAB_ROOT="/path/to/homelab"
BACKUP_DIR="${HOMELAB_ROOT}/backups/daily"
BACKUP_FILE="${BACKUP_DIR}/homelab-daily-${TIMESTAMP}.tar.gz"

TMP_DIR=$(mktemp -d)

# Stack directories
PROXY_STACK_DIR="${HOMELAB_ROOT}/stacks/proxy"
HTTP_STACK_DIR="${HOMELAB_ROOT}/stacks/http"
MANAGEMENT_STACK_DIR="${HOMELAB_ROOT}/stacks/management/example-service"
SECURITY_STACK_DIR="${HOMELAB_ROOT}/stacks/security/password-manager"
STORAGE_STACK_DIR="${HOMELAB_ROOT}/stacks/storage/file-platform"

# Example container names
APP_CONTAINER="file-platform-app"
DB_CONTAINER="file-platform-db"
PASSWORD_MANAGER_CONTAINER="password-manager"

# Example credential file
DB_PASSWORD_FILE="${HOMELAB_ROOT}/secrets/databases/db-password"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "${TMP_DIR}" ]; then
        rm -rf "${TMP_DIR}"
    fi
}

container_running() {
    docker ps --format '{{.Names}}' | grep -qx "$1"
}

disable_maintenance_mode() {
    if container_running "${APP_CONTAINER}"; then
        docker exec "${APP_CONTAINER}" \
            php occ maintenance:mode --off >/dev/null 2>&1 || true
    fi
}

log "Starting daily backup"

mkdir -p "${BACKUP_DIR}"
mkdir -p "${TMP_DIR}/databases"

[ -d "${HOMELAB_ROOT}" ] || { log "Homelab root not found"; exit 1; }
[ -f "${DB_PASSWORD_FILE}" ] || { log "Database password file not found"; exit 1; }

container_running "${APP_CONTAINER}" || { log "Application container not running"; exit 1; }
container_running "${DB_CONTAINER}" || { log "Database container not running"; exit 1; }
container_running "${PASSWORD_MANAGER_CONTAINER}" || { log "Password manager container not running"; exit 1; }

DB_PASSWORD=$(cat "${DB_PASSWORD_FILE}")

log "Enabling application maintenance mode"

docker exec "${APP_CONTAINER}" \
    php occ maintenance:mode --on

log "Dumping application database"

docker exec "${DB_CONTAINER}" \
    mariadb-dump \
    -u root \
    -p"${DB_PASSWORD}" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --all-databases \
    > "${TMP_DIR}/databases/application.sql"

log "Backing up password manager SQLite database"

docker exec "${PASSWORD_MANAGER_CONTAINER}" \
    sqlite3 /data/db.sqlite3 ".backup '/data/db-backup.sqlite3'"

docker cp \
    "${PASSWORD_MANAGER_CONTAINER}:/data/db-backup.sqlite3" \
    "${TMP_DIR}/databases/password-manager.sqlite3"

docker exec "${PASSWORD_MANAGER_CONTAINER}" \
    rm -f /data/db-backup.sqlite3

log "Creating backup archive"

tar \
    --exclude="${HOMELAB_ROOT}/backups" \
    --exclude="${HOMELAB_ROOT}/logs" \
    -czf "${BACKUP_FILE}" \
    "${PROXY_STACK_DIR}" \
    "${HTTP_STACK_DIR}" \
    "${MANAGEMENT_STACK_DIR}" \
    "${SECURITY_STACK_DIR}" \
    "${STORAGE_STACK_DIR}" \
    "${HOMELAB_ROOT}/data" \
    "${HOMELAB_ROOT}/docs" \
    "${HOMELAB_ROOT}/scripts" \
    "${HOMELAB_ROOT}/shared" \
    "${TMP_DIR}/databases"

log "Disabling application maintenance mode"

docker exec "${APP_CONTAINER}" \
    php occ maintenance:mode --off

log "Verifying archive integrity"

tar -tzf "${BACKUP_FILE}" >/dev/null

log "Removing backups older than 7 days"

find "${BACKUP_DIR}" \
    -type f \
    -name "*.tar.gz" \
    -mtime +7 \
    -delete

cleanup

BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | awk '{print $1}')

log "Backup completed successfully"
log "Archive: ${BACKUP_FILE}"
log "Size: ${BACKUP_SIZE}"

exit 0
