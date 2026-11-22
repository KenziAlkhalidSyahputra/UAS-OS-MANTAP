# UAS-OS-MANTAP
# SysBackup Monitor

Proyek Akhir Praktikum Sistem Operasi — **Pilihan A: Backup dan Monitoring Layanan**.
Versi final: tag `P2-FINAL-v01`.

# Tujuan dan kebutuhan lingkungan

**Tujuan:** memastikan backup hanya berjalan saat layanan sehat dan storage cukup (modul monitoring),
lalu mengirim backup ke server terpisah secara aman dan memverifikasi hasil restore (modul backup/restore).

**Kebutuhan:** Linux atau WSL2 (jalankan dari `~/`, bukan `/mnt/c`), Docker Engine + Compose v2, `bash`,
`ssh`, `scp`, `tar`, `sha256sum`.

# Alur kerja

```
monitor.sh --OK--> backup.sh --> tar.gz + sha256 --SCP--> backup-server --> verifikasi checksum di server
    ↳ GAGAL--> backup ditolak (exit 1, tercatat di logs/sysbackup.log)
restore.sh --> verifikasi checksum --> ekstrak ke restore-output/ --> diff dengan data asli
```

Monitoring memeriksa: container layanan `running` dan `healthy`, container `backup-server` `running`,
dan storage kosong ≥ `MIN_FREE_MB` (default 100 MB).

# Arsitektur: host dan container

| Komponen | Tempat | Fungsi |

| `scripts/*.sh` | Host | Otomasi monitoring, backup, restore, cleanup, pengujian |
| `systembackup-demo-service` | Container | Layanan simulasi dengan health check |
| `systembackup-backup-server` | Container | OpenSSH server (key-only) penerima backup via SCP |
| `data-simulasi/`, `backup-local/`, `restore-output/` | Host | Data sumber, arsip lokal, hasil restore |
| `backup-remote/` | Host, bind mount ke `backup-server` | Penyimpanan server; **persisten** walau container dibuat ulang |

- **Network:** `sysbackup-net` (bridge). Kedua container saling menemukan lewat nama service.
  Satu-satunya port ke host: `127.0.0.1:2222 → backup-server:22`.
- **Resource limit:** `mem_limit: 128m` dan `cpus: 0.25` untuk kedua container. Tidak privileged, tanpa Docker socket.
- **Akses aman:** SSH key-only (password dan root ditolak). Key demo dibuat `setup-demo.sh`, mode `600`,
  **tidak di-commit**. Jangan pernah mengumpulkan `config/ssh/id_ed25519`.

## Instalasi dan menjalankan

```bash
git clone https://github.com/KenziAlkhalidSyahputra/UAS-OS-MANTAP.git
cd UAS-OS-MANTAP
chmod +x scripts/*.sh backup-server/entrypoint.sh service/service.sh
./scripts/setup-demo.sh            
docker compose up -d --build       
docker compose ps                 
./scripts/monitor.sh --stats       
./scripts/backup.sh               
./scripts/restore.sh             
```

Exit status semua script: `0` berhasil, `1` gagal, `2` input salah. Log aktivitas: `logs/sysbackup.log`.

## Menguji

```bash
./scripts/test.sh                 
```

20 skenario: monitoring sehat/gagal (A), backup ditolak saat layanan mati lalu recovery dan backup sukses
(B, integrasi), restore valid dan arsip rusak ditolak (C), akses key diizinkan serta password/key salah/root
ditolak (D), resource limit, network, dan persistensi setelah container dibuat ulang (E).

Kondisi gagal dan recovery secara manual:

```bash
docker stop systembackup-demo-service
./scripts/backup.sh               
docker start systembackup-demo-service
./scripts/backup.sh              
```

## Memantau

```bash
./scripts/monitor.sh --stats                
docker compose ps                             
docker stats --no-stream                      
docker logs systembackup-backup-server       
tail -f logs/sysbackup.log                   
```

## Cleanup dan rollback

```bash
./scripts/cleanup.sh               
./scripts/cleanup.sh --purge       
```

Rollback: **data** -> `./scripts/restore.sh backup-local/backup-<timestamp>.tar.gz` lalu
`cp -a restore-output/data-simulasi/. data-simulasi/`; **lingkungan** -> `cleanup.sh` lalu
`docker compose up -d --build`; **kode** -> `git checkout <commit>` atau `git revert <commit>`.

## Keterbatasan

- `StrictHostKeyChecking=no` dipakai karena host key SSH dibuat ulang tiap container baru.
- Key demo tanpa passphrase, hanya untuk simulasi.
- Ownership `backup-remote/` mengikuti uid 1000 di container; jika uid host berbeda, `scp` atau
  `cleanup.sh --purge` bisa gagal karena permission.
- `restore.sh` membandingkan dengan data *saat ini*; jika data sumber berubah setelah backup, verifikasi gagal.
- Restore hanya dari `backup-local/`; belum ada rotasi/retensi backup dan belum diuji di luar satu mesin.

## Kontribusi anggota

Anggota Bidang 
File 

 misaki-07 (Rakha), Container dan network:  
`docker-compose.yml`, `.gitignore`, `backup-server/Dockerfile`

 Diandra_Farrel,  Akses aman (SSH) dan fondasi: 
`backup-server/entrypoint.sh`, `scripts/common.sh`, `scripts/setup-demo.sh`

 KenziAlkhalidSyahputra,  Monitoring, backup, restore  
`scripts/monitor.sh`, `scripts/backup.sh`, `scripts/restore.sh` 

 Pr4mbors (Prama),  Pengujian, cleanup, dokumentasi  
`scripts/cleanup.sh`, `scripts/test.sh`, `README.md` |