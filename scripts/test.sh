
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
set +e
trap - ERR
set -u

[ $# -eq 0 ] || { echo "Pemakaian: $0   (tanpa argumen)"; exit 2; }

mkdir -p "$ROOT_DIR/evidence"
EVIDENCE="$ROOT_DIR/evidence/test-results-$(date -u +%Y%m%dT%H%M%SZ).txt"
exec > >(tee "$EVIDENCE") 2>&1

S="$ROOT_DIR/scripts"
COMPOSE=(docker compose -f "$ROOT_DIR/docker-compose.yml")
EXPECT_MEM_BYTES="${EXPECT_MEM_BYTES:-134217728}"     # mem_limit: 128m
EXPECT_NANO_CPUS="${EXPECT_NANO_CPUS:-250000000}"     # cpus: 0.25

need_cmd docker ssh ssh-keygen scp sha256sum tar find
need_ssh_key
for c in "$SERVICE_CONTAINER" "$BACKUP_CONTAINER"; do
  if [ "$(container_status "$c")" != running ]; then
    echo "Container $c belum berjalan. Jalankan dulu: docker compose up -d --build"
    exit 2
  fi
done


PASS=0; FAILED=0; RESULTS=()


check() {
  local name="$1" expect="$2"; shift 2
  local out rc ok=0
  out="$("$@" 2>&1)"; rc=$?
  if [ "$expect" = nz ]; then [ "$rc" -ne 0 ] && ok=1; else [ "$rc" -eq "$expect" ] && ok=1; fi
  printf '\n--- %s\n    perintah: %s\n    exit=%s (diharapkan: %s)\n' "$name" "$*" "$rc" "$expect"
  if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/    | /'; fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS+1)); RESULTS+=("PASS  $name"); echo "    HASIL: PASS"
  else
    FAILED=$((FAILED+1)); RESULTS+=("FAIL  $name"); echo "    HASIL: FAIL"
  fi
}

count_archives() { find "$ROOT_DIR/backup-local" -maxdepth 1 -type f -name 'backup-*.tar.gz' | wc -l; }
latest_archive() { find "$ROOT_DIR/backup-local" -maxdepth 1 -type f -name 'backup-*.tar.gz' | sort | tail -n 1; }

wait_healthy() {
  local c="$1" t="${2:-60}" i
  for ((i=0; i<t; i++)); do
    [ "$(container_status "$c")" = running ] && [ "$(container_health "$c")" = healthy ] && return 0
    sleep 1
  done
  return 1
}
wait_ssh() {
  local i
  for ((i=0; i<30; i++)); do remote_ssh true >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}


expect_denied() {
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  [ "$rc" -ne 0 ] && grep -q 'Permission denied' <<<"$out"
}
SSH_PLAIN=(-p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)


t_backup_rejected() {
  local before after rc
  before="$(count_archives)"
  docker stop "$SERVICE_CONTAINER" >/dev/null || return 1
  "$S/backup.sh"; rc=$?
  after="$(count_archives)"
  docker start "$SERVICE_CONTAINER" >/dev/null
  wait_healthy "$SERVICE_CONTAINER" 60 || { echo "service tidak kembali healthy setelah recovery"; return 1; }
  [ "$rc" -ne 0 ] || { echo "backup seharusnya ditolak tetapi exit=0"; return 1; }
  [ "$before" -eq "$after" ] || { echo "arsip baru terbentuk padahal backup ditolak ($before -> $after)"; return 1; }
  echo "backup ditolak (exit=$rc), tidak ada arsip baru ($before -> $after), service pulih healthy"
}

t_backup_success() {
  local before after out archive base
  before="$(count_archives)"
  out="$("$S/backup.sh")" || { echo "$out"; return 1; }
  echo "$out"
  after="$(count_archives)"
  [ "$after" -eq $((before+1)) ] || { echo "jumlah arsip lokal tidak bertambah 1 ($before -> $after)"; return 1; }
  archive="$(printf '%s\n' "$out" | tail -n 1)"; base="$(basename "$archive")"
  [ -f "$ROOT_DIR/backup-remote/$base" ] || { echo "arsip tidak ada di backup-remote/: $base"; return 1; }
  [ -f "$ROOT_DIR/backup-remote/$base.sha256" ] || { echo "checksum tidak ada di backup-remote/"; return 1; }
  cmp -s "$archive" "$ROOT_DIR/backup-remote/$base" || { echo "isi arsip lokal dan remote berbeda"; return 1; }
  echo "arsip lokal dan salinan di backup-server identik: $base"
}

t_restore_corrupt() {
  local latest base tmp rc
  latest="$(latest_archive)"
  [ -n "$latest" ] || { echo "tidak ada arsip untuk diuji"; return 1; }
  base="$(basename "$latest")"
  tmp="$(mktemp -d "$ROOT_DIR/restore-output/.test-XXXXXX")" || return 1
  cp "$latest" "$latest.sha256" "$tmp/"
  printf 'rusak' >> "$tmp/$base"            # simulasi arsip berubah/rusak
  "$S/restore.sh" "$tmp/$base"; rc=$?
  rm -rf "$tmp"
  [ "$rc" -eq 1 ] || { echo "diharapkan exit 1 (checksum gagal), dapat exit $rc"; return 1; }
  echo "restore menolak arsip yang berubah (exit=1)"
}

t_key_perms() {
  local m d
  m="$(stat -c '%a' "$SSH_KEY")"; d="$(stat -c '%a' "$ROOT_DIR/config/ssh")"
  echo "private key mode=$m (harus 600/400), config/ssh mode=$d (harus 700)"
  { [ "$m" = 600 ] || [ "$m" = 400 ]; } && [ "$d" = 700 ]
}

t_remote_perms() {
  local out
  out="$(remote_ssh "stat -c '%U:%a' /home/backupuser/.ssh")" || return 1
  echo "/home/backupuser/.ssh di backup-server: $out (harus backupuser:700)"
  [ "$out" = "backupuser:700" ]
}

t_authkeys_perms() {
  local out
  out="$(remote_ssh "stat -c '%U:%a' /home/backupuser/.ssh/authorized_keys")" || return 1
  echo "authorized_keys di backup-server: $out (harus backupuser:600)"
  [ "$out" = "backupuser:600" ]
}

t_wrong_key() {
  local tmp rc
  tmp="$(mktemp -d)"
  ssh-keygen -q -t ed25519 -N '' -f "$tmp/wrong" || { rm -rf "$tmp"; return 1; }
  expect_denied ssh "${SSH_PLAIN[@]}" -i "$tmp/wrong" -o IdentitiesOnly=yes "$SSH_USER@$SSH_HOST" true
  rc=$?
  rm -rf "$tmp"
  return $rc
}

t_limits() {
  local c mem cpu bad=0
  for c in "$SERVICE_CONTAINER" "$BACKUP_CONTAINER"; do
    mem="$(docker inspect -f '{{.HostConfig.Memory}}' "$c")"
    cpu="$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$c")"
    echo "$c memory=${mem}B (harus $EXPECT_MEM_BYTES) nano_cpus=$cpu (harus $EXPECT_NANO_CPUS)"
    { [ "$mem" = "$EXPECT_MEM_BYTES" ] && [ "$cpu" = "$EXPECT_NANO_CPUS" ]; } || bad=1
  done
  docker stats --no-stream --format 'stats: {{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}} ({{.MemPerc}})' \
    "$SERVICE_CONTAINER" "$BACKUP_CONTAINER"
  return $bad
}

t_not_privileged() {
  local c priv mounts bad=0
  for c in "$SERVICE_CONTAINER" "$BACKUP_CONTAINER"; do
    priv="$(docker inspect -f '{{.HostConfig.Privileged}}' "$c")"
    mounts="$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$c")"
    echo "$c privileged=$priv mounts: $mounts"
    [ "$priv" = false ] || bad=1
    grep -q 'docker.sock' <<<"$mounts" && bad=1
  done
  return $bad
}

t_network() {
  local n1 n2
  n1="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$SERVICE_CONTAINER")"
  n2="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$BACKUP_CONTAINER")"
  echo "network $SERVICE_CONTAINER: $n1"
  echo "network $BACKUP_CONTAINER: $n2"
  [ -n "$n1" ] && [ "$n1" = "$n2" ] || return 1
  docker exec "$SERVICE_CONTAINER" ping -c 1 -W 2 backup-server
}

t_persistence() {
  local old new before after
  old="$(docker inspect -f '{{.Id}}' "$BACKUP_CONTAINER")"
  before="$(ls -1 "$ROOT_DIR/backup-remote" | sort)"
  [ -n "$before" ] || { echo "backup-remote kosong; jalankan backup dulu"; return 1; }
  echo "isi backup-remote/ sebelum container dibuat ulang:"; echo "$before"
  "${COMPOSE[@]}" up -d --force-recreate backup-server >/dev/null 2>&1 || { echo "gagal membuat ulang container"; return 1; }
  new="$(docker inspect -f '{{.Id}}' "$BACKUP_CONTAINER")"
  wait_ssh || { echo "SSH backup-server tidak kembali setelah dibuat ulang"; return 1; }
  after="$(docker exec "$BACKUP_CONTAINER" ls -1 "$REMOTE_DIR" | sort)"
  echo "container lama: ${old:0:12}  container baru: ${new:0:12}"
  echo "isi $REMOTE_DIR di container baru:"; echo "$after"
  [ "$old" != "$new" ] && [ "$before" = "$after" ]
}


echo "=== SysBackup Monitor - hasil pengujian ==="
echo "waktu     : $(date -u +%FT%TZ)"
echo "commit    : $(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'tidak ada git')"
echo "docker    : $(docker --version)"
echo "evidence  : $EVIDENCE"

echo; echo "##### A. MONITORING"
check "A1 monitor: layanan sehat -> OK"                    0  "$S/monitor.sh"
check "A2 monitor: statistik CPU/memori container"         0  "$S/monitor.sh" --stats
check "A3 monitor: storage kurang -> GAGAL (exit 1)"       1  env MIN_FREE_MB=999999999 "$S/monitor.sh"
check "A4 monitor: input tidak valid -> ditolak (exit 2)"  2  "$S/monitor.sh" 'nama;rusak'

echo; echo "##### B. BACKUP + INTEGRASI MONITORING"
check "B1 integrasi: service mati -> backup DITOLAK, lalu recovery" 0 t_backup_rejected
check "B2 integrasi: service sehat -> backup BERHASIL + terkirim ke server" 0 t_backup_success

echo; echo "##### C. RESTORE"
check "C1 restore: arsip valid -> terverifikasi"           0  "$S/restore.sh"
check "C2 restore: arsip berubah -> DITOLAK (checksum)"    0  t_restore_corrupt
check "C3 restore: arsip tidak ada -> ditolak (exit 2)"    2  "$S/restore.sh" /tmp/backup-20000101T000000Z.tar.gz

echo; echo "##### D. AKSES AMAN (SSH/SCP)"
check "D1 akses diizinkan: login dengan key milik proyek"  0  remote_ssh 'echo login-ok'
check "D2 akses ditolak: login password"                   0  expect_denied ssh "${SSH_PLAIN[@]}" -o PubkeyAuthentication=no -o PreferredAuthentications=password "$SSH_USER@$SSH_HOST" true
check "D3 akses ditolak: key yang tidak terdaftar"         0  t_wrong_key
check "D4 akses ditolak: login sebagai root"               0  expect_denied ssh "${SSH_PLAIN[@]}" -i "$SSH_KEY" -o IdentitiesOnly=yes "root@$SSH_HOST" true
check "D5 permission private key dan folder config/ssh"    0  t_key_perms
check "D6 ownership/permission .ssh di backup-server"      0  t_remote_perms
check "D7 ownership/permission authorized_keys di server"  0  t_authkeys_perms

echo; echo "##### E. CONTAINER, NETWORK, RESOURCE LIMIT, PERSISTENSI"
check "E1 resource limit CPU/memori + statistik"           0  t_limits
check "E2 container tidak privileged, tanpa docker.sock"   0  t_not_privileged
check "E3 network bersama + resolusi nama antar container" 0  t_network
check "E4 persistensi: data tetap ada setelah container dibuat ulang" 0 t_persistence

echo; echo "=== RINGKASAN ==="
printf '%s\n' "${RESULTS[@]}"
echo "PASS=$PASS FAIL=$FAILED"
sleep 1
[ "$FAILED" -eq 0 ]
