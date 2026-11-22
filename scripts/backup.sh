source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [ $# -gt 0 ]; then
  case "$1" in
    -h|--help) echo "Pemakaian: $0   (tanpa argumen)"; exit 0 ;;
    *) usage_error "Argumen tidak dikenal: $1" ;;
  esac
fi

need_cmd tar sha256sum scp ssh
need_ssh_key

SRC="$ROOT_DIR/data-simulasi"
[ -d "$SRC" ] || usage_error "Folder sumber tidak ada: $SRC (jalankan scripts/setup-demo.sh)"
[ -n "$(ls -A "$SRC")" ] || usage_error "Folder sumber kosong: $SRC"

"$ROOT_DIR/scripts/monitor.sh" || fail 'Backup ditolak karena monitoring gagal'

mkdir -p "$ROOT_DIR/backup-local"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="$ROOT_DIR/backup-local/backup-$STAMP.tar.gz"
CHECKSUM="$ARCHIVE.sha256"
[ ! -e "$ARCHIVE" ] || fail "Arsip dengan timestamp sama sudah ada: $ARCHIVE (tunggu 1 detik lalu ulangi)"

trap 'rm -f "$ARCHIVE.part"' EXIT
tar -czf "$ARCHIVE.part" -C "$ROOT_DIR" data-simulasi
mv "$ARCHIVE.part" "$ARCHIVE"
( cd "$ROOT_DIR/backup-local" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")" )
log "BACKUP: arsip lokal dibuat $(basename "$ARCHIVE")"

remote_scp "$ARCHIVE" "$CHECKSUM" "$SSH_USER@$SSH_HOST:$REMOTE_DIR/" \
  || fail "Pengiriman SCP gagal (cek: docker logs $BACKUP_CONTAINER; permission config/ssh dan backup-remote)"

remote_ssh "cd '$REMOTE_DIR' && sha256sum -c '$(basename "$CHECKSUM")'" >/dev/null \
  || fail 'Verifikasi checksum di backup-server gagal (file rusak saat transfer)'

log "BACKUP_OK: $ARCHIVE dikirim ke backup-server dan checksum terverifikasi"
printf '%s\n' "$ARCHIVE"