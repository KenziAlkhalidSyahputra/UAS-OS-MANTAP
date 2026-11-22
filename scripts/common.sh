if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "common.sh harus di-source oleh script lain, bukan dijalankan langsung." >&2
  exit 2
fi

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
LOG_FILE="$LOG_DIR/systembackup.log"
mkdir -p "$LOG_DIR"

SERVICE_CONTAINER="${SERVICE_CONTAINER:-systembackup-demo-service}"
BACKUP_CONTAINER="${BACKUP_CONTAINER:-systembackup-backup-server}"
MIN_FREE_MB="${MIN_FREE_MB:-100}"
SSH_HOST="${SSH_HOST:-127.0.0.1}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-backupuser}"
SSH_KEY="${SSH_KEY:-$ROOT_DIR/config/ssh/id_ed25519}"
REMOTE_DIR="${REMOTE_DIR:-/home/backupuser/incoming}"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG_FILE"; }

fail() { log "ERROR: $*"; exit 1; }

usage_error() { log "ERROR(input): $*"; exit 2; }

trap 'rc=$?; log "ERROR: ${0##*/} gagal di baris $LINENO (exit=$rc): $BASH_COMMAND"' ERR

need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || fail "Perintah tidak ditemukan: $c"
  done
}

is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
is_container_name() { [[ "${1:-}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$ ]]; }

container_status() { docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || echo "not-found"; }
container_health() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo "not-found"
}

SSH_COMMON_OPTS=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

need_ssh_key() {
  [ -f "$SSH_KEY" ] || fail "Private key tidak ditemukan ($SSH_KEY). Jalankan scripts/setup-demo.sh dulu."
  local mode
  mode="$(stat -c '%a' "$SSH_KEY")"
  case "$mode" in
    600|400) ;;
    *) fail "Permission private key harus 600/400, sekarang $mode. Jalankan: chmod 600 $SSH_KEY" ;;
  esac
}

remote_ssh() { ssh -p "$SSH_PORT" "${SSH_COMMON_OPTS[@]}" "$SSH_USER@$SSH_HOST" "$@"; }
remote_scp() { scp -q -P "$SSH_PORT" "${SSH_COMMON_OPTS[@]}" "$@"; }
