#!/usr/bin/env bash
###############################################################################
# backup-weekly.sh
#
# Backup Tier:
#   Weekly = System Recovery
#
# Purpose:
#   Creates a broader weekly backup for rebuilding the Docker homelab after a
#   larger failure.
#
# Protects against:
#   - Failed updates
#   - Data loss across multiple services
#   - Broken host migration
#   - Stack misconfiguration
#
# Includes:
#   - Docker Compose stack definitions
#   - Documentation
#   - Scripts
#   - Logs
#   - Application data
#   - Safe database dumps
#
# Excludes by default:
#   - secrets/
#   - .env files
#   - private keys
#   - certificates
#   - Cloudflare tokens
#   - existing backup archives
#   - unsafe live database files where proper dumps are created
#
# Restore use case:
#   Rebuild the homelab onto another Linux host or recover from stack failure.
#
# Retention:
#   Keeps the latest 4 matching weekly backup archives by default.
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
BACKUP_DIR="${WEEKLY_BACKUP_DIR:-${BACKUP_ROOT}/weekly}"
RETENTION_COUNT="${WEEKLY_RETENTION_COUNT:-4}"

BACKUP_NAME="homelab-weekly-${HOSTNAME_SAFE}-${TIMESTAMP}"
TMP_DIR="$(mktemp -d)"
STAGING_DIR="${TMP_DIR}/${BACKUP_NAME}"
DB_DUMP_DIR="${STAGING_DIR}/database-dumps"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
LOG_FILE="${BACKUP_DIR}/${BACKUP_NAME}.log"

NEXTCLOUD_CONTAINER="${NEXTCLOUD_CONTAINER:-nextcloud}"
POSTGRES_CONTAINERS="${POSTGRES_CONTAINERS:-nextcloud-db}"
MYSQL_CONTAINERS="${MYSQL_CONTAINERS:-}"
SQLITE_FILES="${SQLITE_FILES:-}"

STOP_STACKS="${STOP_STACKS:-}"
START_STACKS="${START_STACKS:-storage/nextcloud security/vaultwarden}"
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
  shift

  local cmd=(docker compose)

  [[ -f "${HOMELAB_ROOT}/.env" ]] && cmd+=(--env-file "${HOMELAB_ROOT}/.env")
  [[ -f "${stack_dir}/.env" ]] && cmd+=(--env-file "${stack_dir}/.env")

  cmd+=(-f "${stack_dir}/compose.yml")

  "${cmd[@]}" "$@"
}

resolve_stack_dir() {
  local relative="$1"

  if [[ -f "${HOMELAB_ROOT}/stacks/${relative}/compose.yml" ]]; then
    echo "${HOMELAB_ROOT}/stacks/${relative}"
    return 0
  fi

  return 1
}

stack_services_var_name() {
  local relative="$1"
  echo "${relative^^}" | tr '/-' '__' | sed 's/$/_SERVICES/'
}

get_stack_services() {
  local relative="$1"
  local var_name
  var_name="$(stack_services_var_name "${relative}")"

  echo "${!var_name:-}"
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

stop_stack() {
  local relative="$1"
  local stack_dir

  stack_dir="$(resolve_stack_dir "${relative}")" || {
    log "Stack not found, skipping stop: ${relative}"
    return 0
  }

  log "Stopping stack: ${relative}"
  compose_cmd "${stack_dir}" down || true
  STOPPED_STACKS+=("${relative}")
}

start_stack() {
  local relative="$1"
  local stack_dir services

  stack_dir="$(resolve_stack_dir "${relative}")" || {
    log "Stack not found, skipping start: ${relative}"
    return 0
  }

  services="$(get_stack_services "${relative}")"

  if [[ -n "${services}" ]]; then
    log "Starting stack with explicit services: ${relative} -> ${services}"
    compose_cmd "${stack_dir}" up -d ${services}
  else
    log "Starting stack: ${relative}"
    compose_cmd "${stack_dir}" up -d
  fi
}

stop_services_for_consistency() {
  log "Stopping selected stacks for filesystem consistency"

  for stack in ${STOP_STACKS}; do
    stop_stack "${stack}"
  done
}

restart_services() {
  log "Restarting stopped services"

  for stack in ${START_STACKS}; do
    start_stack "${stack}" || true
  done
}

dump_postgres() {
  local container="$1"

  if ! docker_exists "${container}"; then
    log "PostgreSQL container not running, skipping: ${container}"
    return 0
  fi

  local user dump_file
  user="$(get_container_env "${container}" POSTGRES_USER)"
  user="${user:-postgres}"

  dump_file="${DB_DUMP_DIR}/${container}-pg_dumpall.sql"

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

  local user dump_file
  user="$(get_container_env "${container}" MYSQL_USER)"
  user="${user:-root}"

  dump_file="${DB_DUMP_DIR}/${container}-mysqldump.sql"

  log "Dumping MySQL/MariaDB database from ${container}"
  docker exec "${container}" sh -c "exec mysqldump --all-databases -u'${user}' -p\"\${MYSQL_PASSWORD:-\${MYSQL_ROOT_PASSWORD}}\"" > "${dump_file}"

  [[ -s "${dump_file}" ]] || fail "MySQL/MariaDB dump failed or empty: ${dump_file}"
}

dump_sqlite() {
  local sqlite_file="$1"

  if [[ ! -f "${sqlite_file}" ]]; then
    log "SQLite file not found, skipping: ${sqlite_file}"
    return 0
  fi

  local name dump_file
  name="$(basename "${sqlite_file}")"
  dump_file="${DB_DUMP_DIR}/${name}.backup"

  log "Backing up SQLite database: ${sqlite_file}"

  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "${sqlite_file}" ".backup '${dump_file}'"
  else
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

  for sqlite_file in ${SQLITE_FILES}; do
    dump_sqlite "${sqlite_file}"
  done
}

copy_backup_sources() {
  log "Copying weekly backup sources"

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
    "${HOMELAB_ROOT}/logs" \
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
  log "Verifying weekly backup archive"

  [[ -f "${BACKUP_FILE}" ]] || fail "Backup archive does not exist"
  [[ -s "${BACKUP_FILE}" ]] || fail "Backup archive is empty"

  tar -tzf "${BACKUP_FILE}" >/dev/null
  log "Backup verified successfully: ${BACKUP_FILE}"
}

rotate_backups() {
  log "Rotating weekly backups, keeping latest ${RETENTION_COUNT}"

  find "${BACKUP_DIR}" -maxdepth 1 -type f -name "homelab-weekly-*.tar.gz" \
    | sort -r \
    | tail -n +$((RETENTION_COUNT + 1)) \
    | xargs -r rm -f
}

cleanup() {
  disable_maintenance_mode
  restart_services
  log "Cleaning up temporary files"
  rm -rf "${TMP_DIR}"
}

trap 'log "[ERROR] Backup failed on line ${LINENO}"; cleanup; exit 1' ERR
trap 'cleanup' EXIT

log "Starting weekly backup"
log "Homelab root: ${HOMELAB_ROOT}"
log "Backup destination: ${BACKUP_FILE}"
log "Include secrets: ${INCLUDE_SECRETS}"

enable_maintenance_mode
dump_databases
stop_services_for_consistency
copy_backup_sources
create_archive
verify_backup
rotate_backups

log "Weekly backup completed successfully"
