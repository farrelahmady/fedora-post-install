# Rclone Google Drive di Fedora KDE

Setup: remote `personal-gdrive` → `~/GoogleDrive/personal-gdrive` (Fedora 44, Plasma 6.7, rclone 1.74.3).

## 1. Apa itu Rclone dan kegunaannya

Rclone adalah tool CLI untuk mengelola cloud storage (Google Drive, S3, Dropbox, dll) lewat satu perintah. Bukan sync client seperti Dropbox Desktop yang punya tray icon.

Kegunaan utama:
- `rclone lsd/ls/copy/sync/bisync` — akses Drive langsung via API, tanpa mount.
- `rclone mount` — menipu aplikasi Linux seolah Drive adalah folder lokal (via FUSE), sehingga Dolphin, LibreOffice, VS Code bisa buka/save langsung.
- `rclone config` — menyimpan OAuth + nama remote di `~/.config/rclone/rclone.conf` (format INI, tiap `[nama]` = 1 remote).

Kenapa perlu paham FUSE: Google Drive API hanya bisa upload file utuh, tidak bisa tulis acak maju-mundur seperti filesystem. Rclone menjembatani dengan cache lokal (lihat section 4a).

## 2. Cara install dan uninstall cleanup

Install:
```bash
sudo dnf install rclone fuse3
rclone --version
```

Uninstall bersih (lepas semua mount + hapus program, config, cache, dan SEMUA menu klik kanan per-remote):
```bash
# lepas semua mount rclone di ~/GoogleDrive (bukan cuma satu)
for m in ~/GoogleDrive/*/; do fusermount -u "$m" 2>/dev/null; done
pkill -f "rclone mount" 2>/dev/null
sudo dnf remove rclone
rm -rf ~/.config/rclone/ ~/.cache/rclone/
rm -f ~/.local/share/kio/servicemenus/gdrive-upload-*.desktop
rmdir ~/GoogleDrive/*/ ~/GoogleDrive 2>/dev/null
# opsional: hapus script helper-nya juga (termasuk nama lama bila ada)
rm -f ~/.local/bin/rclone-gdrive ~/.local/bin/gdrive-setup
```

Kenapa `gdrive-upload-*.desktop` (wildcard): setiap `rclone-gdrive connect <nama>` membuat satu file `gdrive-upload-<nama>.desktop`, jadi cleanup harus menghapus semuanya, bukan satu file saja. Verifikasi sisa:
```bash
mount | grep GoogleDrive || echo "no mounts left"
ls ~/.local/share/kio/servicemenus/ | grep gdrive || echo "no gdrive menus left"
```

Catatan: `rm ~/.config/rclone/rclone.conf` = hapus semua remote + token OAuth. Backup dulu jika perlu:
```bash
cp ~/.config/rclone/rclone.conf ~/.config/rclone/rclone.conf.bak
```

## 3. Cara connect ke Gdrive (rclone config)

Cara otomatis (dipakai script section 9) — menjawab semua pertanyaan wizard dengan default, tinggal klik Allow di browser:
```bash
rclone config create personal-gdrive drive scope drive
```

Batasnya jujur: 100% non-interaktif itu mustahil untuk Drive pribadi, karena Google mewajibkan consent manusia di browser (desain keamanan OAuth, bukan keterbatasan rclone). Yang bisa diotomatiskan = semuanya kecuali klik Allow itu. Untuk mesin headless/SSH tanpa browser, polanya berbeda: jalankan `rclone authorize "drive"` di mesin yang ada browsernya, lalu tempel tokennya di mesin headless — atau salin `~/.config/rclone/rclone.conf` seperti catatan di section 9.

Cara manual (fallback bila otomatis gagal) — jalankan interaktif:
```bash
rclone config
```

Langkah wizard yang dipakai untuk `personal-gdrive`:
1. `n` (new remote) > nama: `personal-gdrive` (disarankan huruf kecil tanpa spasi agar tidak perlu kutip tiap perintah).
2. Storage: ketik `drive` > pilih `Google Drive`.
3. `client_id` + `client_secret`: kosongkan (Enter), kecuali punya GCP project sendiri.
4. `scope`: pilih `1` (full access).
5. `root_folder_id`, `service_account_file`: kosongkan.
6. `Edit advanced?`: `n`.
7. `Use auto config?`: `y` > browser terbuka > login Google > Allow.
8. `Configure as team drive?`: `n` > `y` untuk simpan > `q` keluar.

Error paling sering di tahap ini:
```
Failed to create file system for "gdrive:": didn't find section in config file
```
Artinya nama remote salah. Nama harus persis dengan isi config. Cek:
```bash
rclone listremotes
rclone config file
grep -E "^\[.+\]" ~/.config/rclone/rclone.conf
```

Validasi connect:
```bash
rclone lsd personal-gdrive: -P
```
Jika keluar daftar folder (Bhapbite, Finance, dll) = OAuth beres.

## 4. Cara mount agar muncul pada Dolphin

Dolphin membaca folder biasa, jadi mountpoint FUSE otomatis muncul di Dolphin seperti folder lokal. Contoh manual (nama `Personal` hanya ilustrasi; script section 9 memakai konvensi `~/GoogleDrive/<nama-remote>`, jadi `connect personal-gdrive` me-mount ke `~/GoogleDrive/personal-gdrive`).

```bash
mkdir -p ~/GoogleDrive/Personal
rclone mount personal-gdrive: ~/GoogleDrive/Personal --vfs-cache-mode writes --dir-cache-time 10m --vfs-cache-max-size 5G --poll-interval 30s --daemon
ls ~/GoogleDrive/Personal
mount | grep GoogleDrive
ps aux | grep "[r]clone mount"
```

Hasil akhir:
```
~/GoogleDrive/         = folder lokal biasa
~/GoogleDrive/Personal = mountpoint FUSE ke root Drive
```

### 4a. Flag yang bisa digunakan

- `--vfs-cache-mode writes|off|minimal|full` (dipakai: `writes`).
  `writes` = tulis ke cache SSD dulu (`~/.cache/rclone`), pas file di-`close` baru upload. Tanpa ini LibreOffice/Dolphin sering gagal save (error I/O, file 0 byte) karena Drive tidak support tulis acak. `off` hemat disk tapi rapuh untuk app desktop. `full` wajib untuk streaming video/ISO/baca acak, tapi boros cache.
- `--dir-cache-time 10m`.
  Umur maksimal ingatan daftar file. `ls` cepat + hemat API (Google batasi ~1000 call/100 detik). Efek samping: file dari HP/web maksimal 10 menit baru terlihat jika tanpa poll. Jangan set `0` — Dolphin yang `ls` berkali-kali (list + thumbnail + size) akan lemot dan kena `403 rateLimitExceeded`.
- `--poll-interval 30s` (default `1m`, `0` = mati).
  Tiap N detik cek ringan ke Changes API: ada yang berubah? Jika ya, cache direktori langsung dibuang walau belum 10 menit. Harus `< dir-cache-time` dan hanya jalan di remote yang support (Drive termasuk). Rumus: `dir-cache-time` panjang = cepat + hemat, `poll-interval` pendek = tetap fresh dengan biaya kecil.
- `--vfs-cache-max-size 5G`.
  Batas cache upload. Mencegah SSD penuh saat copy besar.
- `--vfs-write-back 5s` (default, tidak ditulis eksplisit).
  Jeda setelah file di-`close` sebelum upload background dimulai. Makanya `cp` terasa instan tapi `rclone ls` remote belum ada 5–15 detik.
- `--daemon`.
  Jalan di background agar terminal bisa ditutup. Konsekuensi: harus di-`kill`/unmount manual, tidak mati sendiri saat terminal ditutup.
- `--log-file ~/.cache/rclone/mount.log --log-format date,time -v`.
  Opsional untuk debugging + watcher notifikasi (lihat section 7). Tanpa ini mount bisu saat error.

Contoh mount hemat untuk arsip pribadi vs kolaboratif:
```bash
# arsip sendiri: cache lama, poll standar
rclone mount personal-gdrive: ~/GoogleDrive/Personal --vfs-cache-mode writes --dir-cache-time 30m --poll-interval 1m --vfs-cache-max-size 5G --daemon
# folder rame (sering dari HP/teman): cache pendek + poll cepat
rclone mount personal-gdrive: ~/GoogleDrive/Personal --vfs-cache-mode writes --dir-cache-time 1m --poll-interval 15s --vfs-cache-max-size 5G --daemon
```

## 5. Cara unmount

```bash
fusermount -u ~/GoogleDrive/Personal
mount | grep GoogleDrive      # harus kosong = sudah lepas
ps aux | grep "[r]clone mount" # daemon harus mati
```

`fusermount` = helper FUSE agar user bisa unmount tanpa `sudo`. Tanpa flag = mau mount, `-u` = unmount, `-z` = lazy unmount (paksa walau busy), alternatif `umount ~/GoogleDrive/Personal` juga bisa.

Jika `device is busy` (Dolphin/terminal masih buka folder itu): tutup Dolphin/tab terminal dulu, atau:
```bash
fusermount -uz ~/GoogleDrive/Personal
```

Jangan `rm -rf` saat masih ke-mount — yang terhapus bisa isi Drive, bukan folder lokal.

### 5a. Mengatasi jika terhapus dari Dolphin (bukan unmount via fuse)

Dua kasus beda, penanganannya beda:

A. Menghapus **isi** (`~/GoogleDrive/Personal/file.pdf` via Dolphin) saat masih ke-mount = menghapus file beneran di Google Drive (masuk Trash Drive 30 hari). Pulihkan via web drive.google.com > Trash, bukan via `rm` lokal.

B. Menghapus **mountpoint itu sendiri** (`~/GoogleDrive/Personal` foldernya di-delete Dolphin) saat masih ke-mount = berbahaya/membingungkan: FUSE masih nempel tapi path hilang, `mount` masih ada, `ls` error. Jangan dibuat ulang manual saat masih nempel. Pulihkan:
```bash
mount | grep GoogleDrive
fusermount -uz ~/GoogleDrive/Personal 2>/dev/null; pkill -f "rclone mount personal-gdrive" 2>/dev/null
sleep 1
mount | grep GoogleDrive  # pastikan kosong
mkdir -p ~/GoogleDrive/Personal
rclone mount personal-gdrive: ~/GoogleDrive/Personal --vfs-cache-mode writes --dir-cache-time 10m --vfs-cache-max-size 5G --poll-interval 30s --daemon
ls ~/GoogleDrive/Personal
```

Pencegahan: anggap `~/GoogleDrive/Personal` sebagai drive, bukan folder biasa. Untuk lepas selalu `fusermount -u`, jangan Delete dari Dolphin. Untuk hapus file selalu sadar itu hapus di cloud.

## 6. Copy via Dolphin vs command

Jalur beda:
- Dolphin: `~/GoogleDrive/Personal/file` → `~/` lewat FUSE (2 lapis terjemahan, non-blocking, tanpa retry/checksum/resume).
- Command: `personal-gdrive:file` → `~/` langsung ke API (paralel, retry, checksum, progress jujur).

Aturan:
- `< 50MB, 1–5 file santai` → Dolphin boleh (misal ambil CV untuk email).
- `> 100MB / > 20 file / dokumen penting (Ijazah, Transkrip, Keuangan)` → wajib command.

```bash
rclone copyto "personal-gdrive:CV_Farrel_Ahmad_Yudithia.pdf" ~/CV.pdf -P
rclone copy "personal-gdrive:Finance" ~/Backup/Finance -P --transfers 4 --checkers 8 --retries 3
rclone copy "personal-gdrive:Finance" ~/Backup/Finance --dry-run
```

`copy` aman (hanya nambah), `sync` destruktif (hapus yang beda di tujuan) — selalu `--dry-run` dulu. `bisync` butuh `--resync` pertama kali.

Untuk upload (kebalikan): `cp` ke mount = cepat balik tapi belum dijamin di Google (eventual, tergantung `--vfs-write-back 5s` + antrean `--transfers`), sedangkan `rclone copy file personal-gdrive: -P` = lama balik tapi balik = sudah di Google. Cek antrean mount via `du -sh ~/.cache/rclone/vfs/*` dan `rclone lsl personal-gdrive:namafile`.

## 7. Notifikasi upload

`rclone mount` bisu by design. Notif harus dari script pembungkus (`notify-send` sudah tersedia di Fedora KDE ini).

Cara 1 — `gpush` (reliabel, untuk file penting):
`~/bin/gpush`:
```bash
#!/bin/bash
# pakai: gpush ~/file.pdf "Personal/Backup"
SRC="$1"
DST="personal-gdrive:${2:-}"
rclone copy "$SRC" "$DST" -P --transfers 4 --retries 3
if [ $? -eq 0 ]; then
  notify-send "Drive ✓ Selesai" "$SRC → $DST"
else
  notify-send -u critical "Drive ✗ Gagal" "$SRC"
fi
```
```bash
chmod +x ~/bin/gpush
gpush ~/Dokumen/Ijazah.pdf "Personal/"
```

Cara 2 — watcher log (untuk drag-drop Dolphin ke mount):
```bash
fusermount -u ~/GoogleDrive/Personal
rclone mount personal-gdrive: ~/GoogleDrive/Personal --vfs-cache-mode writes --dir-cache-time 10m --vfs-cache-max-size 5G --poll-interval 30s --daemon --log-file ~/.cache/rclone/mount.log --log-format date,time -v
tail -n0 -F ~/.cache/rclone/mount.log | grep --line-buffered -i "copied\|uploaded" | while read -r line; do
  notify-send "Drive ↑ Terupload" "$line"
done
```
Kelemahan cara 2: log berisik, tidak seakurat return code `rclone copy`. Pola: santai → Dolphin, penting → `gpush`.

## 8. Integrasi klik kanan Dolphin

Menu klik kanan bersifat per-remote (satu file `.desktop` per remote), karena target upload di-hardcode di baris `Exec`. `rclone-gdrive connect <nama>` otomatis membuatkannya: `~/.local/share/kio/servicemenus/gdrive-upload-<nama>.desktop` (sudah terverifikasi untuk `personal-gdrive`). Tidak perlu buat manual — restart Dolphin saja setelah connect. Sebaliknya `rclone-gdrive disconnect <nama>` menghapus file menu itu lagi.

Contoh hasil generate untuk `personal-gdrive`:
```ini
[Desktop Entry]
Type=Service
MimeType=all/all;
Actions=uploadTopersonalgdrive;

[Desktop Action uploadTopersonalgdrive]
Name=Upload to personal-gdrive
Icon=folder-remote
Exec=sh -c 'rclone copy "$1" "personal-gdrive:" -P --transfers 4 && notify-send "Drive Upload Done" "$1" || notify-send -u critical "Drive Upload Failed" "$1"' _ %f
```

Jika remote kedua ditambahkan (`rclone-gdrive connect my-drive`), file kedua `gdrive-upload-my-drive.desktop` muncul dengan `Name=Upload to my-drive` dan `Exec` menunjuk ke `my-drive:`, sehingga klik kanan menawarkan dua tujuan. `rclone-gdrive disconnect my-drive` menghapusnya lagi.

Arti baris: `[Desktop Entry]` header wajib, `Type=Service` = menu file manager (bukan launcher), `MimeType=all/all;` = tampil untuk semua file, `Actions=` harus cocok dengan section `[Desktop Action ...]` (dibuat unik per remote agar tidak tabrakan antar file), `%f` = file yang diklik diteruskan ke `$1` via `sh -c '...' _ %f` agar bisa pakai `&&/||` untuk notif. Jika menu dibuat manual tanpa script, ganti `DEST` dengan `namaremote:` atau `namaremote:Subfolder/` sesuai tujuan.

## 9. Script rclone-gdrive (connect / disconnect)

Satu command dengan dua subcommand. `connect` = config (bila belum ada) + mount + menu klik kanan + icon `folder-gdrive` untuk `~/GoogleDrive/` di Dolphin (via file `~/GoogleDrive/.directory`, hanya dibuat bila belum ada agar kustomisasi user tidak tertimpa). `disconnect` = unmount + hapus remote dari `rclone.conf` + hapus menu klik kanan + hapus direktori mount **beserta seluruh isinya** + hapus cache VFS orphaned. File cloud tidak tersentuh disconnect — yang hilang hanya data lokal (config, menu, folder mount, antrean upload yang belum terkirim).

Script sudah terpasang di `~/.local/bin/rclone-gdrive` (masuk PATH, bisa dipanggil langsung).

Pakai:
```bash
rclone-gdrive connect my-drive        # remote my-drive → ~/GoogleDrive/my-drive (root Drive)
rclone-gdrive connect my-drive Kerja  # remote my-drive → ~/GoogleDrive/my-drive (isi my-drive:Kerja)
rclone-gdrive connect personal-gdrive # setup yang dipakai di file ini
rclone-gdrive disconnect my-drive     # tanya konfirmasi dulu (aman)
rclone-gdrive disconnect my-drive --yes # langsung eksekusi tanpa tanya
```

Cara kerja input: subcommand (`$1`) di-dispatch via `case` ke `cmd_connect`/`cmd_disconnect`, sisanya diteruskan (`shift; cmd_connect "$@"`). Di dalam handler, `$1` = nama remote, `$2` opsional = subfolder (`connect`) atau `--yes` (`disconnect`). `${1:-}` artinya ambil argumen atau string kosong bila tidak ada. Validasi regex `^[A-Za-z0-9_-]+$` menolak spasi agar pola `~/GoogleDrive/<nama>` tetap bersih.

### 9a. Isi script (`~/.local/bin/rclone-gdrive`)

```bash
#!/bin/bash
# Usage:
#   rclone-gdrive connect <remote> [drive-subfolder]  -> config (if missing) + mount + per-remote Dolphin menu
#   rclone-gdrive disconnect <remote> [--yes]          -> unmount + delete remote + remove Dolphin menu
set -euo pipefail # exit on error, undefined variable, or failed pipe
usage() { # print usage information
  echo "Usage:"
  echo "  rclone-gdrive connect <remote-name> [drive-subfolder]"
  echo "  rclone-gdrive disconnect <remote-name> [--yes]"
}
valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; } # remote names feed ~/GoogleDrive/<name>, so reject spaces/special chars
cmd_connect() { # $1 = remote name, $2 (optional) = subfolder inside Drive
  REMOTE="${1:-}"; SUBPATH="${2:-}"
  [[ "$REMOTE" == "-h" || "$REMOTE" == "--help" ]] && { usage; exit 0; } # help flag is not a remote name
  [[ -z "$REMOTE" ]] && { echo "Missing remote name."; usage; exit 1; } # show usage when empty
  valid_name "$REMOTE" || { echo "Invalid remote name '$REMOTE'. Use letters/numbers/_/- only, no spaces."; exit 1; } # keep mount path clean
  MOUNT="$HOME/GoogleDrive/$REMOTE" # local mountpoint derived from remote name
  SOURCE="${REMOTE}:${SUBPATH}" # remote source: Drive root or subfolder
  DEST="$SOURCE" # upload target for right-click menu (same place that gets mounted)
  command -v rclone >/dev/null || sudo dnf install -y rclone fuse3 # install only when missing
  if ! rclone listremotes | grep -qx "${REMOTE}:"; then echo "Remote '${REMOTE}:' not found. Creating it (browser opens once for Google consent)..."; rclone config create "$REMOTE" drive scope drive || { echo "Automatic setup failed. Run 'rclone config' for the manual wizard."; exit 1; }; fi # auto-create with defaults; only browser consent needs a human (Google OAuth requirement)
  if ! rclone listremotes | grep -qx "${REMOTE}:"; then echo "Remote '$REMOTE' still missing after config. Aborting."; exit 1; fi # abort if wizard did not create it
  echo "Checking content of ${SOURCE}:"; rclone lsd "$SOURCE" -P # verify remote is reachable before mounting
  mkdir -p "$MOUNT" # create mountpoint if needed
  BASE_DIR="$HOME/GoogleDrive"; if [[ ! -f "$BASE_DIR/.directory" ]]; then printf '[Desktop Entry]\nIcon=folder-gdrive\n' > "$BASE_DIR/.directory"; echo "Set Google Drive icon on $BASE_DIR."; fi # Dolphin folder icon (parent only — never inside $MOUNT, that would upload junk to Drive)
  fusermount -u "$MOUNT" 2>/dev/null || true # detach previous FUSE mount on same path
  pkill -f "rclone mount ${REMOTE}:" 2>/dev/null || true # kill leftover daemon for this remote
  sleep 1 # let kernel release old mount
  rclone mount "$SOURCE" "$MOUNT" --vfs-cache-mode writes --dir-cache-time 10m --vfs-cache-max-size 5G --poll-interval 30s --daemon # mount in background
  sleep 2; mount | grep -F "$MOUNT" || { echo "Mount failed"; exit 1; } # confirm mount is active
  ls "$MOUNT" # list mounted content as final check
  DESKTOP_DIR="$HOME/.local/share/kio/servicemenus"; DESKTOP_FILE="$DESKTOP_DIR/gdrive-upload-${REMOTE}.desktop" # one menu file per remote
  ACTION_ID="uploadTo$(echo "$REMOTE" | tr -cd 'A-Za-z0-9')" # unique action id per remote
  mkdir -p "$DESKTOP_DIR"
  cat > "$DESKTOP_FILE" <<EOF # inner heredoc unquoted so DEST expands now, \$1 stays literal for Dolphin
[Desktop Entry]
Type=Service
MimeType=all/all;
Actions=${ACTION_ID};

[Desktop Action ${ACTION_ID}]
Name=Upload to ${REMOTE}
Icon=folder-remote
Exec=sh -c 'rclone copy "\$1" "${DEST}" -P --transfers 4 && notify-send "Drive Upload Done" "\$1" || notify-send -u critical "Drive Upload Failed" "\$1"' _ %f
EOF
  echo "Right-click menu created: $DESKTOP_FILE (restart Dolphin to see it)."
  notify-send "Drive Mounted" "$SOURCE -> $MOUNT" 2>/dev/null || true # ignored if unavailable
}
cmd_disconnect() { # $1 = remote name, $2 (optional) = --yes to skip confirmation
  REMOTE="${1:-}"; CONFIRM="ask"
  [[ "$REMOTE" == "-h" || "$REMOTE" == "--help" ]] && { usage; exit 0; } # help flag is not a remote name
  if [[ "${2:-}" == "--yes" ]]; then CONFIRM="yes"; fi # if-statement (not &&) so set -e never trips here
  [[ -z "$REMOTE" ]] && { echo "Missing remote name."; usage; exit 1; }
  valid_name "$REMOTE" || { echo "Invalid remote name '$REMOTE'. Nothing to disconnect."; exit 1; }
  MOUNT="$HOME/GoogleDrive/$REMOTE"; DESKTOP_FILE="$HOME/.local/share/kio/servicemenus/gdrive-upload-${REMOTE}.desktop"
  if [[ "$CONFIRM" != "yes" ]]; then # confirmation because disconnect deletes local config AND the mount dir
    echo "This will:"; echo "  1. Unmount $MOUNT"; echo "  2. Delete remote '${REMOTE}:' from ~/.config/rclone/rclone.conf (cloud files stay untouched)"; echo "  3. Remove $DESKTOP_FILE"; echo "  4. Delete $MOUNT and ALL files inside it"
    read -r -p "Continue? [y/N] " ANSWER; [[ "$ANSWER" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
  fi
  fusermount -u "$MOUNT" 2>/dev/null || true; pkill -f "rclone mount ${REMOTE}:" 2>/dev/null || true; sleep 1 # detach mount + stop daemon
  if mount | grep -Fq "$MOUNT"; then echo "Mount $MOUNT is still active (device busy). Close Dolphin/terminals using it and retry."; exit 1; fi # after this $MOUNT is a plain local dir, rm -rf can never touch cloud files
  if [[ -z "$REMOTE" || "$MOUNT" != "$HOME/GoogleDrive/"* || "$MOUNT" == "$HOME/GoogleDrive/" ]]; then echo "Refusing to delete unexpected path: '$MOUNT'. Aborting."; exit 1; fi # guard: never rm -rf outside ~/GoogleDrive/<name>
  if rclone listremotes | grep -qx "${REMOTE}:"; then rclone config delete "$REMOTE"; echo "Remote '${REMOTE}:' deleted."; else echo "Remote '${REMOTE}:' not found, skipping delete."; fi
  if [[ -f "$DESKTOP_FILE" ]]; then rm -f "$DESKTOP_FILE"; echo "Removed $DESKTOP_FILE (restart Dolphin to refresh the menu)."; else echo "No menu file $DESKTOP_FILE, skipping."; fi
  if [[ -e "$MOUNT" ]]; then rm -rf "$MOUNT"; echo "Deleted $MOUNT and its contents."; else echo "$MOUNT already gone, skipping."; fi # recursive: only local leftovers remain post-unmount
  VFS_CACHE="$HOME/.cache/rclone/vfs/$REMOTE"; if [[ -e "$VFS_CACHE" ]]; then rm -rf "$VFS_CACHE"; echo "Deleted orphaned cache $VFS_CACHE."; fi # pending uploads die with it
  notify-send "Drive Disconnected" "$REMOTE" 2>/dev/null || true
}
CMD="${1:-}" # dispatch subcommand, rest forwarded to handler
case "$CMD" in
  connect) shift; cmd_connect "$@" ;;
  disconnect) shift; cmd_disconnect "$@" ;;
  -h|--help|help|"") usage ;;
  *) echo "Unknown command '$CMD'."; usage; exit 1 ;;
esac
```

Catatan: versi di file aktual (`~/.local/bin/rclone-gdrive`) diformat multi-baris dengan comment per blok; di atas dipadatkan agar muat di doc — logikanya identik.

### 9b. Menjadikan script sebagai command

Agar bisa dipanggil langsung (bukan `bash /path/file.sh`), penuhi 3 syarat: lokasi di PATH + shebang + executable.

```bash
# 1. Pastikan folder bin ada dan masuk PATH (Fedora sudah termasuk ~/.local/bin)
mkdir -p ~/.local/bin
echo $PATH | grep -q "$HOME/.local/bin" && echo "PATH OK" || echo "PATH belum ada"

# 2. Buat file script. Versi lengkap ada di 9a — salin via nano:
nano ~/.local/bin/rclone-gdrive
# lalu paste seluruh isi 9a, simpan, keluar.
# Alternatif non-interaktif via cat + heredoc (pembungkus 'RCLONE_EOF' dikutip
# agar $1/$HOME tidak dieksekusi saat pembuatan; gunakan delimiter ini, BUKAN 'EOF',
# karena script mengandung heredoc <<EOF bagian .desktop di dalamnya):
cat > ~/.local/bin/rclone-gdrive <<'RCLONE_EOF'
# ... paste seluruh isi script dari 9a di sini ...
RCLONE_EOF
# Detail kenapa bukan 'EOF': baris `EOF` milik heredoc .desktop di dalam script
# akan memutus heredoc luar lebih awal bila delimiternya sama.

# 3. Jadikan executable + refresh cache shell agar langsung dikenali sebagai command
chmod +x ~/.local/bin/rclone-gdrive
hash -r
which rclone-gdrive
rclone-gdrive   # tanpa subcommand harus tampil Usage
```

Kenapa begitu:
- `#!/bin/bash` (shebang) = kernel tahu interpreter apa saat file dieksekusi langsung.
- `chmod +x` = beri izin eksekusi; tanpa ini muncul `Permission denied` walau di PATH.
- `~/.local/bin` dipilih karena sudah di `$PATH` (cek via `echo $PATH`), sedangkan `~/bin` tidak ada di PATH Fedora ini sehingga harus dipanggil dengan path penuh.
- Dispatch: `rclone-gdrive connect my-drive Kerja` → `CMD=connect`, `shift`, `cmd_connect my-drive Kerja` → `REMOTE=my-drive`, `SUBPATH=Kerja`.
- Peringatan `set -e`: baris seperti `[[ x == y ]] && var=...` sebagai statement tunggal akan meng-exit-kan script saat kondisi false — makanya semua kondisional ditulis sebagai `if` atau `||`/`&&` dengan penanganan eksplisit.

Untuk non-interaktif penuh (tanpa wizard, jika token sudah ada di mesin lain): copy `~/.config/rclone/rclone.conf` dari mesin lama, lalu langsung `rclone-gdrive connect <nama-remote>` — bagian `rclone config` akan dilewati otomatis karena remote sudah ada. `disconnect` tidak pernah butuh browser.
