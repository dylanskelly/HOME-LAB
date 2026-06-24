#!/usr/bin/env bash
###############################################################################
# backup-daily.sh
#
# Backup Tier:
#   Daily = Operational Recovery
#
# Purpose:
#   Creates a fast daily backup for short-term rollback of a Docker homelab.
#
# Protects against:
#   - Bad config changes
#   - Broken container updates
#   - Accidental file deletion
#   - Application-level data corruption caught quickly
#
# Includes:
#   - Docker Compose stack files
#   - Scripts
#   - Documentation
#   - Application data
#   - Safe database dumps
#
# Excludes by default:
#   - secrets/
#   - .env files
#   - private keys
#   - certificates
#   - Cloudflare tokens
#   - backup archives
#   - live raw database files where dumped safely
#
# Restore use case:
#   Restore recent working application state or rollback a broken change.
#
# Retention:
#   Keeps the latest 7 matching daily backup archives by default.
#
# Secrets:
#   Secrets are NOT included unless INCLUDE_SECRETS=true is explicitly set.
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
HOSTNAME_SAFE="$(hostname | tr -cd '[:alnum:]-')"

INCLUDE_SECRETS="${INCLUDE_SECRETS:-false}"
BACKUP_ROOT="${BACKUP_ROOT:-${HOMELAB_ROOT}/backups}"
BACKUP_DIR="${DAILY_BACKUP_DIR:-${BACKUP_ROOT}/daily}"
RETENTION_COUNT="${DAILY_RETENTION_COUNT:-7}"

BACKUP_NAME="homelab-daily-${HOSTNAME_SAFE}-${TIMESTAMP}"
TMP_DIR="$(mktemp -d)"
STAGING_DIR="${TMP_DIR}/${BACKUP_NAME}"
DB_DUMP_DIR="${STAGING_DIR}/database-dumps"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
LOG_FILE="${BACKUP_DIR}/${BACKUP_NAME}.log"

NEXTCLOUD_CONTAINER="${NEXTCLOUD_CONTAINER:-nextcloud}"
POSTGRES_CONTAINERS="${POSTGRES_CONTAINERS:-nextcloud-db}"
MYSQL_CONTAINERS="${MYSQL_CONTAINERS:-}"
SQLITE_FILES="${SQLITE_FILES:-}"

STOPPED_STACKS=()
MAINTENANCE_ENABLED=false

mkdir -p "${BACKUP_DIR}" "${STAGING_DIR}" "${DB_DUMP_DIR}"

log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "${LOG_FILE}"
}

fail() {
  log "[ERROR] $*"
  exit 1
}

docker_exists() {
  docker ps --format '{{.Names}}' | grep -qx "$1"
}

get_container_env() {
  local container="$1"
  local key="$2"

  docker inspect "${container}" \
    --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | awk -F= -v k="${key}" '$1 == k {print substr($0, length(k)+2)}' \
    | tail -n 1
}

compose_cmd() {
  local stack_dir="$1"

  local cmd=(docker compose)

  if [[ -f "${HOMELAB_ROOT}/.env" ]]; then
    cmd+=(--env-file "${HOMELAB_ROOT}/.env")
  fi

  if [[ -f "${stack_dir}/.env" ]]; then
    cmd+=(--env-file "${stack_dir}/.env")
  fi

  cmd+=(-f "${stack_dir}/compose.yml")

  "${cmd[@]}" "${@:2}"
}

enable_maintenance_mode() {
  if docker_exists "${NEXTCLOUD_CONTAINER}"; then
    log "Enabling Nextcloud maintenance mode"
    docker exec --user www-data "${NEXTCLOUD_CONTAINER}" php occ maintenance:mode --on || true
    MAINTENANCE_ENABLED=true
  fi
}

disable_maintenance_mode() {
  if [[ "${MAINTENANCE_ENABLED}" == "true" ]] && docker_exists "${NEXTCLOUD_CONTAINER}"; then
    log "Disabling Nextcloud maintenance mode"
    docker exec --user www-data "${NEXTCLOUD_CONTAINER}" php occ maintenance:mode --off || true
    MAINTENANCE_ENABLED=false
  fi
}

dump_postgres() {
  local container="$1"

  if ! docker_exists "${container}"; then
    log "PostgreSQL container not running, skipping: ${container}"
    return 0
  fi

  local user
  user="$(get_container_env "${container}" POSTGRES_USER)"
  user="${user:-postgres}"

  local dump_file="${DB_DUMP_DIR}/${container}-pg_dumpall.sql"

  log "Dumping PostgreSQL database from ${container}"
  docker exec "${container}" pg_dumpall -U "${user}" > "${dump_file}"

  [[ -s "${dump_file}" ]] || fail "PostgreSQL dump failed or empty: ${dump_file}"
}

dump_mysql() {
  local container="$1"

  if ! docker_exists "${container}"; then
    log "MySQL/MariaDB container not running, skipping: ${container}"
    return 0
  fi

  local user password dump_file
  user="$(get_container_env "${container}" MYSQL_USER)"
  user="${user:-root}"

  password="$(get_container_env "${container}" MYSQL_PASSWORD)"
  password="${password:-$(get_container_env "${container}" MYSQL_ROOT_PASSWORD)}"

  dump_file="${DB_DUMP_DIR}/${container}-mysqldump.sql"

  log "Dumping MySQL/MariaDB database from ${container}"

  if [[ -n "${password}" ]]; then
    docker exec "${container}" sh -c "exec mysqldump --all-databases -u'${user}' -p\"\${MYSQL_PASSWORD:-\${MYSQL_ROOT_PASSWORD}}\"" > "${dump_file}"
  else
    docker exec "${container}" sh -c "exec mysqldump --all-databases -u'${user}'" > "${dump_file}"
  fi

  [[ -s "${dump_file}" ]] || fail "MySQL/MariaDB dump failed or empty: ${dump_file}"
}

dump_sqlite() {
  local sqlite_file="$1"

  if [[ ! -f "${sqlite_file}" ]]; then
    log "SQLite file not found, skipping: ${sqlite_file}"
    return 0
  fi

  local name
  name="$(basename "${sqlite_file}")"

  local dump_file="${DB_DUMP_DIR}/${name}.backup"

  log "Backing up SQLite database: ${sqlite_file}"

  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "${sqlite_file}" ".backup '${dump_file}'"
  else
    log "Host sqlite3 not found. Using temporary sqlite helper container."
    docker run --rm \
      --user "$(id -u):$(id -g)" \
      -v "$(dirname "${sqlite_file}"):/source:ro" \
      -v "${DB_DUMP_DIR}:/backup:rw" \
      keinos/sqlite3 \
      "/source/${name}" ".backup /backup/${name}.backup"
  fi

  [[ -s "${dump_file}" ]] || fail "SQLite backup failed or empty: ${dump_file}"
}

dump_databases() {
  log "Starting database dump phase"

  for container in ${POSTGRES_CONTAINERS}; do
    dump_postgres "${container}"
  done

  for container in ${MYSQL_CONTAINERS}; do
    dump_mysql "${container}"
  done
  
  if [[ -n "${SQLITE_FILES}" ]]; then
    for sqlite_file in ${SQLITE_FILES}; do
      dump_sqlite "${sqlite_file}"
    done
  else
    log "No SQLite files configured, skipping SQLite backup"
  fi

}

copy_backup_sources() {
  log "Copying backup sources into staging directory"

  mkdir -p "${STAGING_DIR}/homelab"

  rsync -a \
    --exclude 'backups/' \
    --exclude 'secrets/' \
    --exclude '.env' \
    --exclude '*.env' \
    --exclude '*.key' \
    --exclude '*.pem' \
    --exclude '*.crt' \
    --exclude '*.p12' \
    --exclude '*.tar' \
    --exclude '*.tar.gz' \
    --exclude 'data/nextcloud/db/' \
    --exclude 'data/nextcloud/redis/' \
    --exclude 'data/vaultwarden/db.sqlite3' \
    --exclude 'data/vaultwarden/db.sqlite3-shm' \
    --exclude 'data/vaultwarden/db.sqlite3-wal' \
    "${HOMELAB_ROOT}/README.md" \
    "${HOMELAB_ROOT}/data" \
    "${HOMELAB_ROOT}/documents" \
    "${HOMELAB_ROOT}/scripts" \
    "${HOMELAB_ROOT}/stacks" \
    "${STAGING_DIR}/homelab/"

  if [[ "${INCLUDE_SECRETS}" == "true" ]]; then
    log "WARNING: INCLUDE_SECRETS=true. Secrets will be included. Do not share this archive."
    rsync -a "${HOMELAB_ROOT}/secrets" "${STAGING_DIR}/homelab/"
    [[ -f "${HOMELAB_ROOT}/.env" ]] && cp "${HOMELAB_ROOT}/.env" "${STAGING_DIR}/homelab/.env"
  fi
}

create_archive() {
  log "Creating archive: ${BACKUP_FILE}"
  tar -czf "${BACKUP_FILE}" -C "${TMP_DIR}" "${BACKUP_NAME}"
}

verify_backup() {
  log "Verifying backup archive"

  [[ -f "${BACKUP_FILE}" ]] || fail "Backup archive does not exist"
  [[ -s "${BACKUP_FILE}" ]] || fail "Backup archive is empty"

  tar -tzf "${BACKUP_FILE}" >/dev/null
  log "Backup verified successfully: ${BACKUP_FILE}"
}

rotate_backups() {
  log "Rotating daily backups, keeping latest ${RETENTION_COUNT}"

  find "${BACKUP_DIR}" -maxdepth 1 -type f -name "homelab-daily-*.tar.gz" \
    | sort -r \
    | tail -n +$((RETENTION_COUNT + 1)) \
    | xargs -r rm -f
}

cleanup() {
  disable_maintenance_mode
  log "Cleaning up temporary files"
  rm -rf "${TMP_DIR}"
}

trap 'log "[ERROR] Backup failed on line ${LINENO}"; cleanup; exit 1' ERR
trap 'cleanup' EXIT

log "Starting daily backup"
log "Homelab root: ${HOMELAB_ROOT}"
log "Backup destination: ${BACKUP_FILE}"
log "Include secrets: ${INCLUDE_SECRETS}"

enable_maintenance_mode
dump_databases
copy_backup_sources
create_archive
verify_backup
rotate_backups

log "Daily backup completed successfully"
