source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NEW_KEY=0
for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --new-key) NEW_KEY=1 ;;
    *) usage_error "Opsi tidak dikenal: $a (pakai --help)" ;;
  esac
done

need_cmd ssh-keygen

mkdir -p "$ROOT_DIR"/{data-simulasi,backup-local,backup-remote,restore-output,logs,evidence,config/ssh}
for d in backup-local backup-remote restore-output logs evidence; do
  touch "$ROOT_DIR/$d/.gitkeep"
done

SAMPLE="$ROOT_DIR/data-simulasi/sample.txt"
if [ ! -f "$SAMPLE" ]; then
  printf '%s\n' 'data simulasi Sistem Operasi' > "$SAMPLE"
  printf '%s\n' 'baris kedua untuk verifikasi backup dan restore' >> "$SAMPLE"
  log "SETUP: data simulasi dibuat di $SAMPLE"
fi

KEY="$SSH_KEY"
AUTH="$ROOT_DIR/config/ssh/authorized_keys"
if [ -d "$AUTH" ]; then
  fail "$AUTH berupa direktori (biasanya dibuat Docker saat file belum ada). Jalankan: docker compose down; rm -rf $AUTH; lalu ulangi setup."
fi

if [ "$NEW_KEY" -eq 1 ]; then
  rm -f "$KEY" "$KEY.pub"
  log "SETUP: key lama dihapus (--new-key)"
fi
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N '' -C sysbackup-demo -f "$KEY" >/dev/null
  log "SETUP: key pair demo baru dibuat"
elif [ ! -f "$KEY.pub" ]; then
  ssh-keygen -y -f "$KEY" > "$KEY.pub"
  log "SETUP: public key dibuat ulang dari private key"
fi
cp "$KEY.pub" "$AUTH"                 
chmod 600 "$KEY" "$AUTH"
chmod 700 "$ROOT_DIR/config/ssh"
 
if [ "$NEW_KEY" -eq 1 ] && command -v docker >/dev/null 2>&1 \
   && [ "$(container_status "$BACKUP_CONTAINER")" != "not-found" ]; then
  if docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --force-recreate backup-server >/dev/null 2>&1; then
    log "SETUP: container backup-server dibuat ulang agar memakai key baru"
  else
    log "PERINGATAN: gagal membuat ulang backup-server. Jalankan manual: docker compose up -d --force-recreate backup-server"
  fi
fi

if [ "$(id -u)" != "1000" ]; then
  log "PERINGATAN: uid host = $(id -u), bukan 1000. Jika scp ke backup-server ditolak karena permission, samakan ownership folder backup-remote."
fi

log "SETUP_OK: public key di $KEY.pub"
