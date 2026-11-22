
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PURGE=0; YES=0
for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --purge) PURGE=1 ;;
    --yes|-y) YES=1 ;;
    *) usage_error "Opsi tidak dikenal: $a" ;;
  esac
done

need_cmd docker find


clean_dir() {
  local d="$1"
  case "$d" in
    "$ROOT_DIR/backup-local"|"$ROOT_DIR/backup-remote"|"$ROOT_DIR/restore-output") ;;
    *) fail "Menolak menghapus di luar folder proyek: $d" ;;
  esac
  [ -d "$d" ] || return 0
  find "$d" -mindepth 1 ! -name .gitkeep -delete \
    || fail "Gagal menghapus isi $d (cek ownership file; file dari container biasanya milik uid 1000)"
}

if [ "$PURGE" -eq 1 ] && [ "$YES" -eq 0 ]; then
  printf 'Ini akan MENGHAPUS volume Docker proyek serta isi backup-local/ dan backup-remote/. Lanjut? ketik "ya": '
  read -r answer
  [ "$answer" = "ya" ] || { log 'CLEANUP dibatalkan oleh pengguna'; exit 1; }
fi

if [ "$PURGE" -eq 1 ]; then
  docker compose -f "$ROOT_DIR/docker-compose.yml" down --remove-orphans --volumes
  clean_dir "$ROOT_DIR/backup-local"
  clean_dir "$ROOT_DIR/backup-remote"
else
  docker compose -f "$ROOT_DIR/docker-compose.yml" down --remove-orphans
fi
clean_dir "$ROOT_DIR/restore-output"

if [ "$PURGE" -eq 1 ]; then
  log 'CLEANUP_OK: container, volume, backup, dan hasil restore dibersihkan'
else
  log 'CLEANUP_OK: container dihentikan dan hasil restore dibersihkan. Backup tetap dipertahankan.'
fi
