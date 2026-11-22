source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<USAGE
Pemakaian: $0 [--stats] [NAMA_CONTAINER_LAYANAN]
  --stats   tambahkan penggunaan CPU/memori container ke log (informasi saja)
Env: MIN_FREE_MB = batas minimum storage kosong dalam MB (default 100)
USAGE
}

SHOW_STATS=0
SERVICE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --stats) SHOW_STATS=1 ;;
    -*) usage_error "Opsi tidak dikenal: $1" ;;
    *)
      [ -z "$SERVICE" ] || usage_error "Hanya satu nama container yang boleh diberikan"
      SERVICE="$1"
      ;;
  esac
  shift
done
SERVICE="${SERVICE:-$SERVICE_CONTAINER}"

is_container_name "$SERVICE" || usage_error "Nama container tidak valid: $SERVICE"
is_uint "$MIN_FREE_MB" || usage_error "MIN_FREE_MB harus bilangan bulat >= 0, nilai sekarang: $MIN_FREE_MB"

need_cmd docker df awk
docker info >/dev/null 2>&1 || { log 'MONITOR_FAIL: Docker daemon tidak dapat dihubungi'; exit 1; }

status="$(container_status "$SERVICE")"
health="$(container_health "$SERVICE")"
backup_status="$(container_status "$BACKUP_CONTAINER")"
free_mb="$(df -Pm "$ROOT_DIR" | awk 'NR==2 {print $4}')"
is_uint "$free_mb" || fail "Gagal membaca kapasitas storage (df mengembalikan: '$free_mb')"

log "service=$SERVICE status=$status health=$health backup_server=$backup_status free_mb=$free_mb"

if [ "$SHOW_STATS" -eq 1 ]; then
  docker stats --no-stream \
    --format 'container={{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}} mem_pct={{.MemPerc}}' \
    "$SERVICE" "$BACKUP_CONTAINER" 2>/dev/null \
    | while IFS= read -r line; do log "STATS: $line"; done || true
fi

rc=0
if [ "$status" != running ] || [ "$health" != healthy ]; then
  log 'MONITOR_FAIL: layanan tidak berjalan sehat'
  rc=1
fi
if [ "$backup_status" != running ]; then
  log 'MONITOR_FAIL: backup-server tidak berjalan'
  rc=1
fi
if [ "$free_mb" -lt "$MIN_FREE_MB" ]; then
  log "MONITOR_FAIL: storage kurang (minimum ${MIN_FREE_MB}MB)"
  rc=1
fi
[ "$rc" -eq 0 ] || exit 1

log 'MONITOR_OK: layanan sehat dan storage mencukupi'