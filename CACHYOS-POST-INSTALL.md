# CachyOS Post-Install — Migrasi Lengkap dari Windows + WSL (Coding + Office)

> Target: CachyOS (disarankan **GNOME Edition** agar 1:1 dengan dokumen Fedora Anda) di PC `MRPEPENG` — Ryzen 5 5500GT + Radeon iGPU (Cezanne 0x1638), A520M-HVS, 16GB RAM, NVMe Kingston SNV2S1000G, LAN Realtek 8168 + WiFi Broadcom 2.10, Dual monitor 1080p (HDMI AOC + DP-to-VGA), Audio AMD + Logi C270 + Mic USB MCN-10.
> Varian: **Docker via pacman + Zsh 1:1 dari WSL + mise (bahasa via mise, bukan pacman)** — sama seperti varian Fedora Anda.
> Sumber inventaris: `DxDiag.txt` + `winget list` Windows 11 Home 26200 + WSL Ubuntu 26.04.1 (git 2.53, node v24.21 via nvm, python 3.14, java 21 + maven, dotnet SDK 10, go, gcc 15, docker 29.8 + postgres:16-alpine + redis:7-alpine tetap pakai Docker, VS Code 1.138 + 30 extensions).
> Basis dokumen ini: `README.md` Fedora Anda, diterjemahkan penuh ke Arch/CachyOS (`pacman + paru`, bukan `dnf + RPM Fusion`).

Cara pakai dokumen ini: ikuti tahap berurutan. Setiap tahap punya pola **Apa itu → Kegunaan untuk Anda → Instalasi → Verifikasi**.

Perbedaan kunci Fedora → CachyOS yang harus dipegang dari awal:

| Fedora Anda | CachyOS | Dampak untuk Anda |
|---|---|---|
| `dnf upgrade` | `sudo pacman -Syu` (jangan pernah `-Sy` tanpa `-u` = partial upgrade merusak Arch) | Update kernel `linux-cachyos` (BORE scheduler) + Mesa optimasi x86-64-v3/v4 ikut satu perintah |
| RPM Fusion (codec/wl/nvidia) | **Tidak ada / tidak perlu.** Repo `cachyos + extra + multilib` sudah bawa `ffmpeg` full, `broadcom-wl-dkms`, `nvidia-dkms` | Hapus Tahap 2 Fedora dari kepala; gantinya cek repo + `paru`/AUR |
| `akmod + MOK enroll` | `dkms + sbctl` (Secure Boot CachyOS pakai `sbctl`, Limine pakai `limine-enroll-config`) | DKMS rebuild otomatis tiap ganti kernel via hook, tapi butuh `linux-cachyos-headers` |
| `SELinux + label :Z` | **Tidak ada SELinux** (default AppArmor/non-enforcing). Compose **tanpa `:Z`** | File volume milik user langsung, `permission denied` SELinux hilang |
| `fedora-workstation-repositories / google-chrome RPM` | `paru -S google-chrome` (AUR) | Tidak ada repo Google manual |
| `code` via repo Microsoft | `paru -S visual-studio-code-bin` (AUR) | Update ikut `paru -Syu`, bukan repo Microsoft |
| `msttcore-fonts-installer RPM` | `paru -S ttf-ms-fonts` (AUR) | Sama-sama butuh `fc-cache` |
| `mesa-va-drivers-freeworld` (swap) | **Tidak perlu swap.** `mesa` CachyOS/Arch sudah full (termasuk `radeonsi_drv_video.so`) | `vainfo` langsung `returns 0` kalau paket benar |
| `timeshift` | `snapper + btrfs-assistant` (CachyOS default **btrfs + snapper**, bukan ext4) | Snapshot otomatis tiap `pacman` transaction, rollback dari boot menu |
| `gnome-software` saja | `gnome-software` (edisi GNOME) / `Discover` (edisi KDE) + `octopi` + `cachy-hello` | Jangan campur update GUI + terminal bersamaan (lock `pacman`) |

---

## Tahap 0 — Pra-Install (Sebelum Wipe Windows)

### Apa itu?
Persiapan sebelum install CachyOS menggantikan Windows. Meliputi backup, mematikan BitLocker/Fast Startup, membuat Live USB CachyOS, dan uji hardware via Live mode.

### Kegunaan untuk Anda
Sama seperti Fedora: drive `C: 440GB + D: 512GB` hilang kalau salah partisi. Office LTSC + OneDrive tidak ada versi Linux-nya, file `.docx/.xlsx` + folder sync harus aman dulu. Uji Live satu-satunya cara memastikan WiFi Broadcom terdeteksi sebelum wipe.

### Instalasi
1. Backup: Dokumen, `~/.ssh`, `.gitconfig`, compose file (`postgres:16-alpine + redis:7-alpine` untuk dipakai via `docker compose` — **hapus label `:Z` versi Fedora**), export VS Code Settings Sync ON, catat lisensi Office/IDM.
2. Di Windows: matikan BitLocker (`Manage BitLocker → Turn off`), matikan Fast Startup (`Power Options → Choose what power buttons do → uncheck Fast Startup`).
3. Download ISO dari `cachyos.org/download` → pilih **GNOME Edition** (agar 1:1 dengan dokumen Fedora; KDE juga boleh tapi nama paket software-center beda). Verifikasi checksum (SHA256 yang disediakan di halaman download), flash dengan **Ventoy** (disarankan CachyOS) / Fedora Media Writer / Rufus (mode DD).
4. Boot Live USB → pilih `Boot CachyOS` → cek: LAN kabel jalan? WiFi muncul? Suara keluar? Kedua monitor tampil? Suspend/wake? Buka `cachy-hello` sekilas untuk lihat opsi installer.
5. Saat install (Calamares): pilih `Erase disk` untuk replace total, pastikan partisi EFI tetap ada. **Pilih filesystem `btrfs`** (default CachyOS, syarat `snapper` di Tahap 13). Pilih kernel `linux-cachyos` default (jangan ganti ke LTS dulu kecuali butuh stabilitas ekstra). Pilih bootloader `limine` (default baru) atau `grub` — keduanya OK, perintah Secure Boot di Tahap 4 beda sedikit.

### Verifikasi
Kalau di Live saja WiFi tidak muncul dan Anda hanya punya WiFi (tanpa kabel), **berhenti dulu**. Siapkan kabel LAN atau catat Tahap 4 (`broadcom-wl-dkms` butuh internet sekali untuk install — siapkan tethering USB HP sebagai jembatan). Kalau LAN + suara + display OK, lanjut install.

---

## Tahap 1 — Update Base + Firmware (Pengganti Windows Update)

### Apa itu?
`pacman` adalah package manager CachyOS/Arch (seperti `dnf` di Fedora, `apt` di WSL). `paru` adalah wrapper `pacman` + AUR helper (sudah preinstalled di CachyOS, pengganti `yay`). `fwupd` sama seperti di Fedora (update firmware via LVFS). `cachy-hello / octopi / cachy-update` adalah GUI/tray updater — jangan dipakai bersamaan dengan `pacman` di terminal (lock).

### Kegunaan untuk Anda
Di Windows Anda terbiasa `Windows Update + AMD Adrenalin`. Di CachyOS, satu perintah mengupdate kernel `linux-cachyos` + Mesa-CachyOS + semua app repo. Firmware Kingston NV2 juga dari `fwupd`, bukan exe vendor.

### Instalasi
```bash
# 1. Rate mirrors dulu sekali (khusus CachyOS, agar download kencang)
sudo cachyos-rate-mirrors

# 2. Update full — JANGAN sudo pacman -Sy (tanpa -u)
sudo pacman -Syu
sudo reboot

# 3. Firmware (sama seperti Fedora, best-effort)
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update
sudo reboot
```

Opsional (boleh skip, jangan aktifkan kalau belum paham): `cachy-hello → Tweaks → enable cachy-update` untuk tray notifikasi update, atau `sudo pacman -S pacman-offline` untuk offline-update ala Windows. Jangan aktifkan auto-update buta di mesin dev — Arch rolling + reboot kernel butuh sadar.

### Verifikasi
```bash
cat /etc/cachyos-release 2>/dev/null || cat /etc/os-release | head -n 5
uname -r   # harus ada kata cachyos, mis. 6.x-cachyos
pacman --version
paru --version
fwupdmgr get-devices | head -n 40
```

---

## Tahap 2 — Repo CachyOS + multilib + AUR (Pengganti RPM Fusion)

### Apa itu?
Fedora butuh RPM Fusion karena repo default disunat lisensi. **CachyOS/Arch tidak butuh itu.** Yang ada: repo `core + extra + multilib` (Arch) + `cachyos + cachyos-extra-v3/v4` (optimasi) + **AUR** (repo komunitas, diakses via `paru`). `multilib` wajib ON untuk Steam/Wine/Chrome 32-bit libs.

### Kegunaan untuk Anda
Tanpa tahap ini, Anda akan bingung cari "RPM Fusion versi Arch". Jawabannya: tidak ada. Semua Tahap 3-4 bergantung pada repo yang sudah aktif + `paru`.

### Instalasi
```bash
# Cek repo aktif (cachyos + multilib harus muncul)
grep -v "^#" /etc/pacman.conf | grep -A1 "^\["
pacman -Sl cachyos | head -n 5

# Jika [multilib] masih komen (#), buka dan uncomment:
sudo nano /etc/pacman.conf
# Pastikan ada (tanpa #):
# [multilib]
# Include = /etc/pacman.d/mirrorlist
sudo pacman -Syu

# paru sudah bawaan CachyOS — verifikasi, jangan install yay dobel
command -v paru && paru --version
# Jika paru tidak ada
# sudo pacman -S paru
# Update sistem + AUR ke depan cukup:
# sudo pacman -Syu      # repo resmi saja
# paru -Syu             # repo resmi + AUR
```

### Verifikasi
```bash
pacman -Sl | grep -i "^cachyos " | head
pacman -Sg | head
paru -S --help | head -n 5
```

---

## Tahap 3 — Codec Multimedia (Pengganti K-Lite / MPC-HC)

### Apa itu?
`ffmpeg + gstreamer plugins` adalah decoder audio/video. Bedanya dengan Fedora: **Arch tidak sunat codec** — `ffmpeg` dari `extra` sudah full (H264/H265/MP3/VP9/AV1 decode), tidak perlu `swap ffmpeg-free → ffmpeg`, tidak perlu `freeworld`.

### Kegunaan untuk Anda
Pengganti MPC-HC 1.7 + HEVC/AV1 Extension di Windows Anda. Agar video Zoom, MP4 screen-record, dan Spotify preview jalan.

### Instalasi
```bash
# Codec full — satu perintah, tanpa swap
sudo pacman -S --needed \
  ffmpeg \
  gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly \
  gst-libav gstreamer-vaapi \
  lame libdvdcss

# Player (pilih satu utama, jangan dobel pacman+flatpak untuk app yang sama)
sudo pacman -S --needed vlc celluloid
# Fallback flatpak hanya jika pacman gagal total:
# flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# flatpak install -y flathub org.videolan.VLC
```

### Verifikasi
```bash
ffmpeg -version | head -n 1
gst-inspect-1.0 --version
# putar 1 file mp4/h265 di VLC/Celluloid
```

---

## Tahap 4 — Driver (AMD + Realtek + Broadcom + Audio/Webcam)

### Apa itu?
Sama seperti Fedora: 90% driver ada di kernel (`amdgpu`, `r8169`, `snd_hda`, `uvcvideo`, `usb-audio`). Bedanya: Fedora pakai `akmod + MOK`, CachyOS/Arch pakai **`dkms + sbctl`** dan paket `mesa` sudah termasuk driver VA-API (`libva-mesa-driver` adalah provides dari `mesa`, bukan paket terpisah yang perlu di-swap).

### Kegunaan untuk Anda
* **AMD Radeon iGPU Cezanne:** nol action untuk display, tapi pastikan `vulkan-radeon + mesa-utils` ada untuk Vulkan/`glxinfo`.
* **Realtek GbE 8168:** nol action (`r8169` in-kernel).
* **Broadcom WiFi 2.10:** perlu `broadcom-wl-dkms` + `linux-cachyos-headers` + `dkms`. **Butuh internet sekali** (kabel LAN / tethering USB) untuk install.
* **AMD Audio + MCN-10 + C270:** via PipeWire + UVC, nol action.
* **Secure Boot:** Fedora = MOK biru. CachyOS = `sbctl` (+ `limine-enroll-config` jika bootloader Limine). Modul DKMS (broadcom/nvidia) **harus signed** kalau Secure Boot ON — kalau tidak, `modprobe: Operation not permitted`.

### Instalasi
```bash
# Cek dulu (jangan install membabi-buta)
sudo pacman -S --needed pciutils usbutils mesa-utils v4l-utils
lspci | grep -iE "vga|3d|display|network|audio|ethernet"
lsusb | grep -iE "logi|c270|wireless|broadcom"

# Firmware + microcode (biasanya sudah bawaan, pastikan ada)
sudo pacman -S --needed linux-firmware amd-ucode
# Intel: sudo pacman -S --needed intel-ucode

# GPU (pilih sesuai hasil lspci, jangan semua):
# AMD Cezanne Vega (mesin ini):
sudo pacman -S --needed mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
  libva libva-utils vulkan-tools
# Intel (varian): sudo pacman -S --needed mesa lib32-mesa vulkan-intel intel-media-driver libva libva-utils
# Nvidia (varian, MANUAL — pilih sadar, butuh headers + reboot):
# sudo pacman -S --needed linux-cachyos-headers nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
# Tetap nouveau (open-source) = tidak perlu install apa-apa.

# Hanya jika terdeteksi Broadcom (PCI maupun USB):
sudo pacman -S --needed linux-cachyos-headers dkms broadcom-wl-dkms
sudo modprobe wl
# Jika Secure Boot AKTIF, sign modul DKMS via sbctl (lihat wiki.cachyos.org Secure Boot Setup):
# sudo pacman -S --needed sbctl
# sudo sbctl status
# sudo sbctl create-keys && sudo sbctl enroll-keys --microsoft
# Limine: sudo limine-enroll-config && sudo limine-update
sudo reboot
# Setelah reboot cek: modinfo wl ; dkms status
```

Catatan monitor `DP2VGA V235` Anda: sama seperti Fedora — native 1024x768 dipaksa 1080p via konverter aktif. Kalau di `Settings → Displays` resolusi aneh, set manual ke 1920x1080@60 atau 1024x768 native.

### Verifikasi
```bash
glxinfo | grep "OpenGL renderer"   # harus: AMD Radeon Graphics
vainfo | grep VAProfile            # H264/HEVCMain/VP9 ada, AV1 tidak ada = normal (Vega)
wpctl status                       # audio PipeWire terlihat
ls /dev/video* && v4l2-ctl --list-devices  # C270 terlihat
nmcli device status                # wifi/ethernet connected
dkms status
# test: suspend 10 detik → wake, cabut-colok mic USB
```

---

## Tahap 5 — Flathub / Flatpak (Tempat Install App User)

### Apa itu?
Sama seperti Fedora: 2 jalur — `pacman/AUR` untuk system + toolchain, `Flatpak/Flathub` untuk app desktop terisolasi. Jangan campur keduanya untuk app yang sama. Di CachyOS GNOME pakai `gnome-software`, di KDE pakai `Discover` + `octopi` untuk pacman GUI.

### Kegunaan untuk Anda
Aturan main sama: base tools dev via pacman (Tahap 8), app desktop (OnlyOffice, DBeaver) via Flatpak agar mudah rollback dan tidak merusak base rolling.

### Instalasi
```bash
sudo pacman -S --needed flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak update -y

# GNOME Edition (disarankan, 1:1 Fedora):
sudo pacman -S --needed gnome-software gnome-tweaks extension-manager
# KDE Edition (varian): sudo pacman -S --needed discover packagekit-qt6
```

### Verifikasi
```bash
flatpak remotes
flatpak list | head
```

---

## Tahap 6 — Docker (bukan bawaan, install via pacman)

### Apa itu?
Docker di CachyOS **bukan bawaan** — install via `pacman` dari repo `extra`, tanpa repo eksternal `download.docker.com` seperti di Fedora. Perbedaan penting vs Fedora: **tanpa `container-selinux`, tanpa label `:Z`** — volume langsung jalan.

### Kegunaan untuk Anda
Menjalankan `postgres:16-alpine + redis:7-alpine` persis seperti di WSL, update ikut `pacman -Syu`, kompatibel penuh dengan Testcontainers / Dev Containers tanpa setting `DOCKER_HOST` tambahan.

> Catatan compose: hapus `:Z` dari file Fedora Anda. Di CachyOS/Arch `:Z` tidak dikenal dan bikin error.

Contoh compose CachyOS (`~/dev-db/docker-compose.yml`):
```yaml
services:
  postgres:
    image: docker.io/postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: dev
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
  redis:
    image: docker.io/redis:7-alpine
    restart: unless-stopped
    ports: ["6379:6379"]
volumes:
  pgdata:
```

### Instalasi
```bash
sudo pacman -S --needed docker docker-compose
sudo systemctl enable --now docker.service
sudo usermod -aG docker "$USER"
# relogin (atau newgrp docker) agar grup docker aktif tanpa sudo tiap perintah:
newgrp docker || true

docker run --rm hello-world
docker compose -f ~/dev-db/docker-compose.yml up -d
docker ps
# autostart DB sudah ditangani restart: unless-stopped + docker.service enable — tanpa systemd unit manual
```

### Verifikasi
```bash
docker version
docker compose version
docker images | grep -E "postgres|redis"
docker ps
# dari Spring/Go/Node connect ke localhost:5432 + localhost:6379
```

---

## Tahap 7 — Zsh 1:1 dari WSL (Oh My Zsh + pengshell + mise)

### Apa itu?
Sama seperti Fedora: Zsh + Oh My Zsh + theme `pengshell` + plugin community + `mise` (pengganti `nvm/sdkman` — bahasa via `mise`, bukan via `pacman`).

### Kegunaan untuk Anda
Membawa 26 plugins WSL (`git docker docker-compose kubectl helm terraform aws gcloud azure ansible python pip node npm yarn golang rust sudo extract z history command-not-found vscode`), history 10000 + `SHARE_HISTORY`, alias `zshconfig/reload`, agar muscle-memory sama.

### Instalasi
```bash
sudo pacman -S --needed zsh git curl fzf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# fzf-tab standalone (tanpa plugin oh-my-zsh, di-source manual dari .zshrc)
mkdir -p ~/.local/share/zsh/plugins
git clone https://github.com/Aloxaf/fzf-tab ~/.local/share/zsh/plugins/fzf-tab

# mise ke zsh (pengganti nvm; bahasa di-install belakangan via `mise use -g`)
curl -fsSL https://mise.run/zsh | sh

chsh -s $(which zsh)
```

Lalu copy `~/.zshrc` dari WSL, pastikan ada aktivasi mise:
```bash
eval "$(mise activate zsh)"
```
Bahasa (node/python/java/go/dotnet) BELUM di-install di sini — pakai `mise` belakangan, misal `mise use -g node@lts python@latest go@latest java@temurin-25`.

> Pola `.zshrc` untuk fzf (standalone, tanpa plugin oh-my-zsh): **jangan** taruh `fzf`/`fzf-tab` di `plugins=(...)`. Source manual sesudah `source $ZSH/oh-my-zsh.sh`:
> ```zsh
> # Arch/CachyOS: /usr/share/fzf/*.zsh (tanpa subfolder shell/ seperti Fedora)
> if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
>   source /usr/share/fzf/completion.zsh
>   source /usr/share/fzf/key-bindings.zsh
> elif command -v fzf >/dev/null 2>&1; then
>   source <(fzf --zsh)
> fi
> [[ -f "$HOME/.local/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh" ]] && source "$HOME/.local/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh"
> ```
> `.zshrc` yang sama bisa dipakai di Fedora + CachyOS bila pakai pengecekan dua path (`shell/` vs langsung). `fzf-tab` wajib sesudah `compinit`. Verifikasi: `fzf --version`, `Ctrl-R`, `cd <Tab>` muncul popup + preview.
>
> Catatan CachyOS: tidak perlu `touch /etc/containers/nodocker` seperti di Fedora.

> Oh-my-posh di `AppData/.../oh-my-posh` Windows tidak dibawa — yang dibawa adalah Oh My Zsh WSL sesuai permintaan.

### Verifikasi
```bash
echo $SHELL; echo $ZSH_THEME
omz plugin list | tr ' ' '\n' | grep -E "autosuggest|syntax|docker|golang"
command -v mise && mise --version
# ketik `git sta` + TAB, restart terminal cek history tetap ada
```

---

## Tahap 8 — Base Tools Dev (tanpa bahasa, bahasa via mise belakangan)

### Apa itu?
Tool build dasar + CLI pendukung coding, TANPA compiler/interpreter bahasa. Bahasa sengaja tidak di-install via `pacman` agar tidak dobel dengan `mise` (Tahap 7). Di Arch, `base-devel` adalah grup wajib (isi `gcc/make/patch/fakeroot` dkk — syarat build AUR via `paru`).

### Kegunaan untuk Anda
`git/gh` untuk repo, `gcc/make` untuk build native + build AUR, `vim/direnv` untuk edit + env per-project, `curl/wget/unzip/7zip` untuk unduh/arsip.

### Instalasi
```bash
sudo pacman -S --needed base-devel git github-cli gcc make vim direnv \
  curl wget unzip 7zip
```

Catatan nama paket Arch: `gh` = paket `github-cli`, `p7zip` lama = sekarang `7zip`. Kalau script lama Anda masih tulis `p7zip`, ganti ke `7zip`.

### SSH GitHub personal + `gh` login (wajib sebelum clone repo privat)
```bash
# 1. Git identity personal (restore dari backup Tahap 0, atau set baru):
git config --global user.name "Nama Personal Anda"
git config --global user.email "email-personal-anda@example.com"

# 2. Generate key personal — SKIP jika ~/.ssh/github-personal.pub sudah ada (hasil restore Tahap 0):
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ls ~/.ssh/github-personal.pub || ssh-keygen -t ed25519 -C "email-personal-anda@example.com" -f ~/.ssh/github-personal
chmod 600 ~/.ssh/github-personal
chmod 644 ~/.ssh/github-personal.pub

# 3. Config SSH — wajib karena nama key non-default (bukan id_ed25519):
cat > ~/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github-personal
  IdentitiesOnly yes
  AddKeysToAgent yes
EOF
chmod 600 ~/.ssh/config

# 4. Agent + load key untuk sesi ini:
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github-personal
ssh-add -l

# 5. Login gh (pilih: GitHub.com → SSH → Login with a web browser, ikuti kode one-time):
gh auth login
# 6. Upload public key personal ke GitHub via gh (tanpa buka browser manual):
#    TITLE full-variable: os-user@host-personal → unik per mesin + user
TITLE="$(. /etc/os-release && echo "$ID")-$(whoami)@$(hostname)-personal"
echo "$TITLE"
# contoh: cachyos-farrel@MRPEPENG-personal
gh ssh-key add ~/.ssh/github-personal.pub --title "$TITLE"
gh ssh-key list
```

> Kalau `gh auth login` gagal buka browser (minimal install / SSH remote), ulangi dengan `gh auth login --web -h github.com` atau tempel token klasik (`ghp_...`, scope `admin:public_key, repo, read:org`). Jangan simpan token di history — pakai 1x lalu `history -c`.

> Jika bentrok — install ulang dengan hostname sama / title sudah ada — hapus key lama by title lalu add ulang (`gh ssh-key delete` butuh ID, bukan title, jadi ambil ID via API dulu):
> ```bash
> TITLE="$(. /etc/os-release && echo "$ID")-$(whoami)@$(hostname)-personal"
> gh ssh-key list
> # lihat ID dari title yang bentrok:
> gh api user/keys --jq '.[] | "\(.id) \(.title)"' | grep -F "$TITLE"
> KEY_ID=$(gh api user/keys --jq ".[] | select(.title==\"$TITLE\") | .id" | head -n1)
> echo "ID lama: $KEY_ID"
> [ -n "$KEY_ID" ] && gh ssh-key delete "$KEY_ID" --yes
> gh ssh-key add ~/.ssh/github-personal.pub --title "$TITLE"
> gh ssh-key list
> ```
> Jika error `key is already in use` (material key sudah terdaftar di title lain, misal hasil restore): list semua `gh api user/keys --jq '.[] | "\(.id) \(.title)"'`, hapus ID yang menampung key lama itu, baru add ulang.

> Akun kedua (kerja) nanti: generate `~/.ssh/github-kerja`, tambah blok `Host github-kerja` + `HostName github.com` + `IdentityFile ~/.ssh/github-kerja` di `~/.ssh/config`, clone via `git@github-kerja:org/repo`. Jangan timpa blok `Host github.com` personal di atas.

### Verifikasi
```bash
git --version; gh --version
gcc --version; make --version
mise --version
gh auth status
ssh -G github.com | grep -i identityfile
ssh -T git@github.com 2>&1 | head -n 3
# harus: "Hi USERNAME! You've successfully authenticated..."
# bahasa belum ada di sini (normal): command -v node python3 java go dotnet || echo "belum di-install, pakai mise"
```

---

## Tahap 9 — VS Code

### Apa itu?
VS Code via **AUR (`visual-studio-code-bin`)**, bukan repo Microsoft manual seperti di Fedora, bukan Flatpak (agar `code` CLI + Docker/Testcontainers integrasi mulus). Update ikut `paru -Syu`. Extensions TIDAK di-install script — pakai Settings Sync setelah login.

### Kegunaan untuk Anda
Editor utama untuk project Spring/Go/.NET/Node. Install dari AUR agar update ikut sistem rolling.

### Instalasi
```bash
paru -S --needed visual-studio-code-bin
code --version
```

Jika belum ada `paru` (instalasi minimal/netinstall):
```bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git /tmp/paru && cd /tmp/paru && makepkg -si
```

### Verifikasi
Buka 1 project Anda, login Settings Sync untuk mengembalikan extensions. `Dev Containers: Reopen in Container` langsung jalan via `/var/run/docker.sock` — tanpa setting `DOCKER_HOST` tambahan.

---

## Tahap 10 — Office (OnlyOffice + Font MS)

### Apa itu?
MS Office LTSC tidak ada versi Linux. Pengganti: OnlyOffice (kompatibilitas `.docx/.xlsx` terbaik) + font MS agar dokumen tidak berantakan. Tidak termasuk client OneDrive/Email/PDF annotasi — di luar scope.

### Kegunaan untuk Anda
90% kerja ketik-baca-print aman. 10% (macro VBA, template pixel-perfect) tidak 1:1 — batas yang diterima.

### Instalasi
```bash
# OnlyOffice (utama untuk .docx/.xlsx agar rapi dibuka di Word)
flatpak install -y flathub org.onlyoffice.desktopeditors

# Font Windows agar dokumen tidak berantakan (AUR, bukan RPM)
paru -S --needed ttf-ms-fonts
# Alternatif font Win11 lengkap (Calibri/Cambria terbaru): paru -S ttf-ms-win11-auto
fc-cache -f; fc-list | grep -i -E "calibri|cambria|arial|times" | head
```

### Verifikasi
Buka 1 `.docx` + 1 `.xlsx` tersulit Anda di OnlyOffice, cek font + tabel + print 1 halaman ke PDF.

---

## Tahap 11 — DB (DBeaver saja)

### Apa itu?
DBeaver Community (Flatpak) sebagai GUI database pengganti TablePlus (TablePlus tidak ada versi Linux — dibuang). Identik dengan Fedora.

### Kegunaan untuk Anda
Connect ke `postgres:16-alpine + redis:7-alpine` dari compose Docker Tahap 6. Tool DB lain (Beekeeper/pgAdmin/draw.io/tesseract) TIDAK di-install — di luar scope.

### Instalasi
```bash
flatpak install -y flathub io.dbeaver.DBeaverCommunity
```

### Verifikasi
Connect DBeaver ke `localhost:5432` (compose Tahap 6 jalan).

---

## Tahap 12 — Chrome AUR + VA-API Cezanne

### Apa itu?
Chrome via **AUR (`google-chrome`)**, bukan Flatpak, bukan RPM. Alasan sama seperti Fedora: Flatpak portal sering bikin masalah mic, screen-share Wayland, dan `chrome://gpu` fallback ke software (SwANGLE). VA-API agar decode H.264/HEVC/VP9 lewat GPU. Bedanya: **tidak perlu `freeworld` swap** — `mesa` CachyOS sudah full.

### Kegunaan untuk Anda
Browser utama + update ikut `paru -Syu`. AMD Cezanne Vega tidak punya decoder AV1 hardware (normal, batas hardware) → YouTube AV1 fallback CPU kecuali dipaksa H.264/VP9 via extension `enhanced-h264ify`.

### Instalasi
```bash
# Chrome dari AUR (repo cachyos tidak sediakan google-chrome)
paru -S --needed google-chrome

# VA-API base (semua GPU — mesa sudah termasuk radeonsi_drv_video.so, tidak perlu freeworld)
sudo pacman -S --needed libva libva-utils mesa

# Varian Intel (jangan campur dengan paket AMD bila tidak hybrid):
# sudo pacman -S --needed intel-media-driver
# Intel lama gen 7 ke bawah (legacy i965): sudo pacman -S --needed libva-intel-driver
```

Flag Chrome permanen via override `~/.local` (awet update, per-user — jangan edit `/usr/share/applications/` milik paket):
```bash
cp /usr/share/applications/google-chrome.desktop ~/.local/share/applications/
# Semua baris Exec= jadi:
# Exec=/usr/bin/google-chrome-stable --ozone-platform=wayland --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL %U
# Lalu killall chrome / logout agar reload.
# Troubleshoot: tambah --render-node-override=/dev/dri/renderD128 jika chrome://gpu bohong accelerated tapi vainfo tak init
```

Detail penuh VA-API + test `chrome://media-internals` + `radeontop`: lihat `chrome-cezanne-vaapi.md` Fedora Anda — langkah validasi sama, hanya perintah install paket yang diganti versi Arch di atas.

### Verifikasi
```bash
google-chrome-stable --version
paru -Qs google-chrome
vainfo | grep VAProfile   # AMD Vega: H264/HEVCMain/VP9 ada, AV1 tidak ada = normal
# chrome://gpu → Video Decode: Hardware accelerated
# chrome://media-internals (video H.264/VP9) → VaapiVideoDecoder, kIsPlatformVideoDecoder: true
```

---

## Tahap 13 — Validasi Akhir + Tabel Gap Jujur + Snapshot

### Checklist 15 menit (jangan skip)
```bash
nmcli device status; glxinfo | grep renderer; wpctl status
ffmpeg -version | head -n 1
grep -v "^#" /etc/pacman.conf | grep "^\[" | head -n 20
google-chrome-stable --version
vainfo | grep -E "VAProfile|va_openDriver" | head -n 20
code --version
docker --version
docker compose version
fc-list | grep -ci "microsoft\|calibri"
uname -r   # pastikan -cachyos
snapper list 2>/dev/null | head || sudo snapper list | head
```
Manual: suspend/wake, brightness, audio in/out, print 1 halaman, buka `.xlsx` kompleks, `mise --version`, `git clone` 1 project.

### Tabel gap (harus diterima — sama seperti Fedora)
| Windows Anda | CachyOS | Status |
|---|---|---|
| Office LTSC macro VBA, template pixel-perfect | OnlyOffice/LibreOffice | 90% OK, macro kompleks pecah |
| OneDrive sync otomatis | rclone/OneDriver/browser | Tidak 1:1 |
| Acrobat Pro edit berat | Evince/Xournal++ | Baca/annotasi OK, edit berat tidak |
| TablePlus | DBeaver (Tahap 11) | Ganti, bukan install |
| Logi Options+ penuh | Solaar terbatas | Sebagian |
| Game Denuvo/SMASH/MTG Arena | Proton (CachyOS unggul di sini: kernel BORE + `proton-cachyos` + GameMode pre-tuned) | Sebagian jalan jauh lebih baik dari Fedora, Denuvo tetap gagal |
| IDM, Samsung Flow, Phone Link | FDM/browser/KDE Connect | Ganti |

### Backup otomatis dari hari pertama (CachyOS way)
```bash
# CachyOS default btrfs + snapper — verifikasi aktif, jangan dimatikan:
sudo snapper list
sudo pacman -S --needed btrfs-assistant snapper-support pika-backup
# btrfs-assistant (GUI) untuk browse/restore snapshot, pika-backup untuk ~/ ke disk eksternal
# Snapshot pacman otomatis tiap transaksi via hook snapper — rollback dari boot menu (limine/grub-btrfs)
```

Jangan matikan firewall (`systemctl status firewalld`) seperti kebiasaan di Windows. Jangan pakai `sudo pacman -Sy <paket>` tanpa `-u`. Jangan update GUI (octopi/discover) bersamaan dengan `pacman/paru` di terminal.
