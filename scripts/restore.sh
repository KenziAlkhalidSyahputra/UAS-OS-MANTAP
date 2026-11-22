source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [ $# -gt 1 ]; then usage_error "Terlalu banyak argumen. Pemakaian: $0 [arsip.tar.gz]"; fi
case "${1:-}" in
  -h|--help) echo "Pemakaian: $0 [backup-YYYYMMDDTHHMMSSZ.tar.gz]"; exit 0 ;;
esac

need_cmd tar sha256sum diff find sort tail

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
  ARCHIVE="$(find "$ROOT_DIR/backup-local" -maxdepth 1 -type f -name 'backup-*.tar.gz' | sort | tail -n 1)"
  [ -n "$ARCHIVE" ] || usage_error 'Tidak ada arsip backup di backup-local/'
fi

[ -f "$ARCHIVE" ] || usage_error "Arsip backup tidak ditemukan: $ARCHIVE"
[[ "$(basename "$ARCHIVE")" =~ ^backup-[0-9]{8}T[0-9]{6}Z\.tar\.gz$ ]] \
  || usage_error "Nama arsip tidak valid (harus backup-YYYYMMDDTHHMMSSZ.tar.gz): $(basename "$ARCHIVE")"

CHECKSUM="$ARCHIVE.sha256"
[ -f "$CHECKSUM" ] || fail "File checksum tidak ditemukan: $CHECKSUM"

( cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$CHECKSUM")" >/dev/null ) \
  || fail 'Verifikasi checksum arsip gagal'

members="$(tar -tzf "$ARCHIVE")" || fail 'Arsip tidak dapat dibaca'
if grep -Ev '^data-simulasi(/|$)' <<<"$members" | grep . >/dev/null; then
  fail 'Arsip berisi path di luar data-simulasi/, restore dibatalkan'
fi
if grep -Eq '(^|/)\.\.(/|$)' <<<"$members"; then
  fail 'Arsip berisi path berbahaya (..), restore dibatalkan'
fi

OUT="$ROOT_DIR/restore-output"
mkdir -p "$OUT"
rm -rf "$OUT/data-simulasi"
tar -xzf "$ARCHIVE" -C "$OUT" --no-same-owner

[ -d "$OUT/data-simulasi" ] || fail 'Folder hasil restore tidak ditemukan'
diff -rq "$ROOT_DIR/data-simulasi" "$OUT/data-simulasi" >/dev/null || fail 'Verifikasi isi hasil restore gagal'

log "RESTORE_OK: arsip $(basename "$ARCHIVE") diverifikasi dan isi sama dengan data asli"
printf '%s\n' "$OUT/data-simulasi"
