#!/usr/bin/env bash

set -Eeuo pipefail

# Determine homelab root automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

LOG_FILE="$HOMELAB_ROOT/logs/homelab-startup.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

fail() {
  log "ERROR: $*"
  exit 1
}

run_compose_stack() {
  local stack_name="$1"
  local stack_path="$2"
  shift 2

  local full_path="$HOMELAB_ROOT/stacks/$stack_path"

  [[ -d "$full_path" ]] || fail "$stack_name directory not found: $full_path"
  [[ -f "$full_path/compose.yml" ]] || fail "$stack_name compose.yml not found: $full_path/compose.yml"
  [[ -f "$full_path/.env" ]] || fail "$stack_name .env not found: $full_path/.env"
  [[ -f "$HOMELAB_ROOT/.env" ]] || fail "Global .env not found: $HOMELAB_ROOT/.env"

  if [[ "$#" -eq 0 ]]; then
    fail "$stack_name requires at least one service name"
  fi

  log "Starting $stack_name services: $*"

  cd "$full_path"

  docker compose \
    --env-file "$HOMELAB_ROOT/.env" \
    --env-file "$full_path/.env" \
    up -d "$@"

  log "Started $stack_name services: $*"
}

log "===== Homelab startup started ====="

log "Ensuring UFW is running"
systemctl is-active --quiet ufw || systemctl start ufw

log "Reloading UFW firewall rules"
ufw reload

sleep 5

log "Checking UFW status"
ufw status | grep -q "Status: active" || fail "UFW is not active"

log "Checking Docker service"
systemctl is-active --quiet docker || systemctl start docker

log "Waiting for Docker daemon"
until docker info >/dev/null 2>&1; do
  sleep 2
done

log "Checking Docker firewall passthrough"
iptables -S FORWARD | grep -q "DOCKER-USER" || fail "FORWARD chain is not passing through DOCKER-USER"

log "Checking Docker user firewall chain"
iptables -S DOCKER-USER >/dev/null 2>&1 || fail "DOCKER-USER chain not found"

run_compose_stack "Proxy stack" "proxy" traefik cloudflared

run_compose_stack "HTTP stack" "http" www tafe

run_compose_stack "Management stack" "management/dockhand" dockhand

run_compose_stack "Security stack" "security/vaultwarden" vaultwarden

run_compose_stack "Storage stack" "storage/nextcloud" nextcloud nextcloud-db nextcloud-redis nextcloud-cron

log "Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$LOG_FILE"

log "===== Homelab startup complete ====="
