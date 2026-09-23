# Fedora Post-Install — Migrasi Lengkap dari Windows + WSL (Coding + Office)

> Target: Fedora Workstation (GNOME) di PC `MRPEPENG` — Ryzen 5 5500GT + Radeon iGPU (Cezanne 0x1638), A520M-HVS, 16GB RAM, NVMe Kingston SNV2S1000G, LAN Realtek 8168 + WiFi Broadcom 2.10, Dual monitor 1080p (HDMI AOC + DP-to-VGA), Audio AMD + Logi C270 + Mic USB MCN-10.
> Varian: **Podman rootless (native Fedora)** + **Zsh 1:1 dari WSL + mise (bahasa via mise, bukan dnf)**.
> Sumber inventaris: `DxDiag.txt` + `winget list` Windows 11 Home 26200 + WSL Ubuntu 26.04.1 (git 2.53, node v24.21 via nvm, python 3.14, java 21 + maven, dotnet SDK 10, go, gcc 15, docker 29.8 + postgres:16-alpine + redis:7-alpine dimigrasi ke Podman, VS Code 1.138 + 30 extensions).

Cara pakai dokumen ini: ikuti tahap berurutan. Setiap tahap punya pola **Apa itu → Kegunaan untuk Anda → Instalasi → Verifikasi**.

---

## Tahap 0 — Pra-Install (Sebelum Wipe Windows)

### Apa itu?
Proses persiapan sebelum install Fedora menggantikan Windows. Meliputi backup, mematikan BitLocker/Fast Startup, membuat Live USB, dan uji hardware via Live mode.

### Kegunaan untuk Anda
Drive `C: 440GB + D: 512GB` Anda akan hilang kalau salah partisi. Office LTSC + OneDrive Anda tidak ada versi Linux-nya, jadi file `.docx/.xlsx` + folder sync harus aman dulu. Uji Live juga satu-satunya cara memastikan WiFi Broadcom Anda terdeteksi sebelum wipe.

### Instalasi
1. Backup: Dokumen, `~/.ssh`, `.gitconfig`, compose file (`postgres:16-alpine + redis:7-alpine` untuk dipakai via `podman compose`), export VS Code Settings Sync ON, catat lisensi Office/IDM jika masih perlu di Windows lain.
2. Di Windows: matikan BitLocker (`Manage BitLocker → Turn off`), matikan Fast Startup (`Power Options → Choose what power buttons do → uncheck Fast Startup`).
3. Download ISO dari `fedoraproject.org/workstation`, verifikasi checksum (SHA256), flash dengan Fedora Media Writer / Ventoy / Rufus.
4. Boot Live USB → pilih `Try Fedora` → cek: LAN kabel jalan? WiFi muncul? Suara keluar? Kedua monitor tampil? Suspend/wake?

### Verifikasi
Kalau di Live saja WiFi tidak muncul dan Anda hanya punya WiFi (tanpa kabel), **berhenti dulu**. Siapkan kabel LAN atau installer `broadcom-wl` offline (lihat Tahap 4). Kalau LAN + suara + display OK, lanjut install (pilih `Erase disk` untuk replace total, pastikan EFI partition tetap ada).

---

## Tahap 1 — Update Base + Firmware (Pengganti Windows Update)

### Apa itu?
`dnf` adalah package manager Fedora (seperti `apt` di Ubuntu WSL Anda, tapi bukan `winget`). `fwupd` adalah update firmware hardware (BIOS/SSD/monitor) via Linux Vendor Firmware Service.

### Kegunaan untuk Anda
Di Windows Anda terbiasa `Windows Update + AMD Adrenalin`. Di Fedora, satu perintah mengupdate kernel + Mesa (driver AMD) + semua app DNF. Firmware Kingston NV2 Anda juga diupdate dari sini, bukan dari exe vendor.

### Instalasi
```bash
sudo dnf upgrade --refresh -y
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update
sudo reboot
```

### Verifikasi
```bash
cat /etc/fedora-release
uname -r
fwupdmgr get-devices | head -n 40
```

---

## Tahap 2 — RPM Fusion (Repo Pihak Ketiga Wajib)

### Apa itu?
Fedora default hanya bawa software free/open-source murni (kebijakan lisensi). RPM Fusion adalah repo komunitas untuk codec proprietary, driver `broadcom-wl`, Steam, dll. Analoginya: PPA di Ubuntu, tapi resmi dan terkurasi.

### Kegunaan untuk Anda
Tanpa ini, MP4/H265, WiFi Broadcom, dan banyak Flatpak runtime tidak bisa diinstall. Semua Tahap 3-4 bergantung padanya.

### Instalasi
```bash
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf upgrade --refresh -y
```

### Verifikasi
```bash
dnf repolist | grep -i rpmfusion
```

---

## Tahap 3 — Codec Multimedia (Pengganti K-Lite / MPC-HC)

### Apa itu?
`ffmpeg + gstreamer plugins` adalah decoder audio/video. Fedora tidak bawaan H264/H265/MP3 karena paten.

### Kegunaan untuk Anda
Pengganti MPC-HC 1.7 + HEVC/AV1 Extension di Windows Anda. Agar video Zoom, MP4 screen-record, dan Spotify preview jalan.

### Instalasi
```bash
# Fedora bawaan ada ffmpeg-free -> harus swap ke ffmpeg RPM Fusion, bukan install dobel
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y ffmpeg \
  "gstreamer1-plugins-bad-*" "gstreamer1-plugins-good-*" \
  "gstreamer1-plugins-base" "gstreamer1-plugins-ugly-*" \
  "gstreamer1-plugins-bad-freeworld*" \
  gstreamer1-plugin-openh264 gstreamer1-libav "lame*" \
  --exclude=gstreamer1-plugins-bad-free-devel

# Player (pisah, hindari duplikat dnf+flatpak)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo dnf install -y celluloid || echo "celluloid via dnf gagal, lanjut vlc"
sudo dnf install -y vlc || flatpak install -y flathub org.videolan.VLC
```

### Verifikasi
```bash
ffmpeg -version | head -n 1
# putar 1 file mp4/h265 di VLC/Celluloid
```

---

## Tahap 4 — Driver (AMD + Realtek + Broadcom + Audio/Webcam)

### Apa itu?
Berbeda dengan Windows (download exe per vendor), 90% driver Linux ada di kernel (`amdgpu`, `r8169`, `snd_hda`, `uvcvideo`, `usb-audio`). Yang perlu install manual hanya pengecualian proprietary.

### Kegunaan untuk Anda
* **AMD Radeon iGPU Cezanne:** nol action, driver `amdgpu + Mesa RADV` sudah di kernel. Jangan cari Adrenalin.
* **Realtek GbE 8168:** nol action (`r8169` in-kernel).
* **Broadcom WiFi 2.10 (terdeteksi di winget, tidak di DxDiag):** ini satu-satunya yang perlu paket `broadcom-wl` dari RPM Fusion.
* **AMD Audio + MCN-10 + C270:** via PipeWire + UVC, nol action.

### Instalasi
```bash
# Cek dulu (jangan langsung install membabi-buta)
sudo dnf install -y pciutils usbutils
lspci | grep -iE "vga|3d|display|network|audio|ethernet"
lsusb | grep -iE "logi|c270|wireless|broadcom"

# Hanya jika terdeteksi Broadcom (PCI maupun USB):
sudo dnf install -y akmod-wl broadcom-wl
# Jika Secure Boot AKTIF: butuh MOK enroll setelah reboot (ikuti prompt biru MOK).
# akmod butuh 2-5 menit build setelah reboot. Cek: modinfo wl
sudo reboot

# Firmware umum (sudah bawaan kernel, pastikan ada):
sudo dnf install -y linux-firmware
# CPU AMD: amd-ucode-firmware / CPU Intel: microcode_ctl (biasanya sudah bawaan)

# GPU (pilih sesuai hasil lspci, jangan semua):
# AMD -> sudo dnf install -y mesa-vulkan-drivers xorg-x11-drv-amdgpu   # in-kernel amdgpu+Mesa
# Intel -> sudo dnf install -y mesa-vulkan-drivers intel-media-driver
# Nvidia -> MANUAL, pilih satu: sudo dnf install -y akmod-nvidia (proprietary + MOK jika Secure Boot),
#           atau biarkan nouveau open-source (tanpa install apa-apa). Script TIDAK auto-install Nvidia.
```

Catatan monitor `DP2VGA V235` Anda: native 1024x768 dipaksa 1080p via konverter aktif. Kalau di `Settings → Displays` resolusi aneh, set manual ke 1920x1080@60 atau 1024x768 native.

### Verifikasi
```bash
glxinfo | grep "OpenGL renderer"   # harus: AMD Radeon Graphics
wpctl status                        # audio PipeWire terlihat
ls /dev/video* && v4l2-ctl --list-devices  # C270 terlihat
nmcli device status                 # wifi/ethernet connected
# test: suspend 10 detik → wake, cabut-colok mic USB
```

---

## Tahap 5 — Flathub / Flatpak (Tempat Install App User)

### Apa itu?
Fedora punya 2 jalur: `DNF/RPM` untuk system (kernel, driver, toolchain) dan `Flatpak/Flathub` untuk app desktop terisolasi (seperti MS Store, tapi open). Jangan campur keduanya untuk app yang sama.

### Kegunaan untuk Anda
Aturan main: base tools dev via DNF (Tahap 8), app desktop (OnlyOffice, DBeaver, Chrome via RPM di Tahap 12) dipisah agar tidak merusak base dan mudah rollback. Flatpak untuk app desktop terisolasi, DNF/RPM untuk system.

### Instalasi
```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak update -y
sudo dnf install -y gnome-software gnome-tweaks extension-manager
```

### Verifikasi
```bash
flatpak remotes
flatpak list | head
```

---

## Tahap 6 — Podman (Native Fedora, Rootless)

### Apa itu?
Podman adalah container runtime bawaan Fedora: daemonless (tanpa daemon root seperti `dockerd`), default rootless (jalan sebagai user Anda via user-namespace), dan terintegrasi `systemd + SELinux + firewalld`. Perintahnya 95% kompatibel dengan Docker (`podman run/ps/images/compose`).

### Kegunaan untuk Anda
Menjalankan `postgres:16-alpine + redis:7-alpine` persis seperti di WSL, tapi tanpa repo eksternal, tanpa daemon root always-on, file volume milik user (bukan `root`), dan update ikut `dnf upgrade`.

Trade-off yang Anda terima vs Docker-ce: image/tool yang mengharapkan `/var/run/docker.sock` (Testcontainers lama, Dev Containers lama) perlu setting socket manual, volume wajib label `:Z` di Fedora kalau kena `permission denied`, port <1024 tidak bisa bind rootless, dan jawaban StackOverflow lebih sedikit.

### Instalasi
```bash
# Podman sudah bawaan Fedora, pastikan lengkap + kompatibilitas Docker CLI
sudo dnf install -y podman podman-compose podman-docker buildah container-selinux
sudo dnf remove -y docker-ce docker-ce-cli 2>/dev/null || true

# Socket user untuk Testcontainers / Dev Containers / API kompatibel Docker
systemctl --user enable --now podman.socket
loginctl enable-linger "${USER}"
ls -l "$XDG_RUNTIME_DIR/podman/podman.sock"
# Untuk Testcontainers/Dev Containers: export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
```

> Catatan (tidak di-install script, opsional manual): alias `docker=podman` di `~/.zshrc`, compose DB `~/dev-db/docker-compose.yml` (`postgres:16-alpine + redis:7-alpine` dengan label `:Z`), dan autostart via `podman generate systemd` — lihat contoh di bawah.

Contoh compose sesuai WSL Anda (`~/dev-db/docker-compose.yml`, dipakai via `podman compose`):
```yaml
services:
  postgres:
    image: docker.io/postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: dev
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data:Z"]
  redis:
    image: docker.io/redis:7-alpine
    ports: ["6379:6379"]
volumes:
  pgdata:
```

```bash
podman run --rm hello-world
podman compose -f ~/dev-db/docker-compose.yml up -d
podman ps
# autostart saat boot (opsional, setelah compose jalan):
podman generate systemd --new --name dev-db-postgres-1 > ~/.config/systemd/user/postgres-dev.service
systemctl --user daemon-reload
systemctl --user enable --now postgres-dev.service
```

Untuk Testcontainers (Java/Spring) / VS Code Dev Containers set:
```bash
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
# di VS Code settings: "dev.containers.dockerPath": "podman"
```

### Verifikasi
```bash
podman version
podman compose version
podman images | grep -E "postgres|redis"
podman ps
# dari Spring/Go/Node connect ke localhost:5432 + localhost:6379
```

---

## Tahap 6b — Perbandingan: Jika Implement dengan Docker vs Podman

> Jalur utama dokumen ini tetap **Podman** (Tahap 6). Bagian ini hanya pembanding jika Anda tetap mau Docker-ce seperti di WSL, agar bedanya jelas sebelum eksekusi.

### Apa itu?
Keduanya container runtime OCI untuk image yang sama (`postgres:16-alpine + redis:7-alpine`). Bedanya di arsitektur:
* **Docker-ce:** daemon sentral `dockerd` jalan sebagai root, client ngomong via `/var/run/docker.sock`. Standar industri, semua tutorial/CI mengasumsikan ini.
* **Podman:** daemonless + rootless (jalan sebagai user via user-namespace), terintegrasi `systemd + SELinux + firewalld` Fedora. Perintah 95% sama (`run/ps/images/compose`).

### Kegunaan untuk Anda
Anda dari `docker 29.8` di WSL hanya untuk 2 DB dev. Tabel ini menentukan apakah tetap Docker (nol adaptasi) atau pindah Podman (lebih bersih Fedora):

| Aspek | Docker-ce | Podman | Dampak untuk Anda |
|---|---|---|---|
| Install di Fedora | Repo eksternal `download.docker.com`, telat 1-2 minggu tiap rilis major | Bawaan `dnf install podman`, ikut base | Podman menang maintenance |
| Keamanan | Daemon root always-on, bypass `firewalld` via iptables | Rootless, hormat `firewalld + SELinux` | Podman menang untuk laptop office |
| File volume | Milik `root`, sering perlu `sudo chown` | Milik user langsung | Podman menang (`node_modules/target` aman) |
| Compose file | `volumes: ["pgdata:/var/lib/postgresql/data"]` langsung jalan | Wajib tambah `:Z` di Fedora: `["pgdata:/var/lib/postgresql/data:Z"]`, prefix `docker.io/` disarankan | Adaptasi kecil sekali |
| Autostart DB | `systemctl enable --now docker` (semua container ikut daemon) | `podman generate systemd` per container + `systemctl --user enable` | Podman lebih granular, Docker lebih simpel |
| Testcontainers (Java/Spring) + Dev Containers | Langsung jalan | Perlu `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` + `"dev.containers.dockerPath": "podman"` | Docker menang kompatibilitas |
| Port <1024 | Bisa bind | Tidak bisa rootless tanpa config | Tidak relevan (Anda pakai 5432/6379) |
| Docs/jawaban SO | Sangat banyak | Lebih sedikit | Docker menang saat debug aneh |
| Zsh plugins `docker/docker-compose` | Native | Tetap jalan via `podman-docker` + alias | Seri |

### Instalasi (side-by-side, pilih satu)

**Jika Podman (jalur utama, sudah di Tahap 6):**
```bash
sudo dnf install -y podman podman-compose podman-docker buildah container-selinux
systemctl --user enable --now podman.socket
podman compose -f ~/dev-db/docker-compose.yml up -d
```

**Jika Docker-ce (alternatif, persis WSL Anda):**
```bash
sudo dnf install -y dnf-plugins-core container-selinux
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker || true
docker run --rm hello-world
docker compose -f ~/dev-db/docker-compose.yml up -d
```

### Verifikasi (keduanya harus hasil sama)
```bash
# Podman:
podman compose -f ~/dev-db/docker-compose.yml ps
# Docker (jika pilih alternatif):
# docker compose -f ~/dev-db/docker-compose.yml ps
# Keduanya: Spring/Go/Node connect ke localhost:5432 + localhost:6379
```

Rekomendasi untuk Anda: tetap Podman untuk harian (alasan keamanan + maintenance Fedora), ingat setting `DOCKER_HOST` di atas hanya jika Testcontainers/Dev Containers protes. Pindah ke Docker hanya jika tim Anda memaksa `docker compose` mentah tanpa toleransi beda perilaku.

---

## Tahap 7 — Zsh 1:1 dari WSL (Oh My Zsh + pengshell + mise)

### Apa itu?
Zsh + Oh My Zsh adalah shell interaktif + framework theme/plugin. Theme `pengshell` Anda ada di `~/.oh-my-zsh/themes/`. Plugin community (`zsh-autosuggestions`, `zsh-syntax-highlighting`) ada di `custom/plugins`. `mise` adalah version manager pengganti `nvm/sdkman` — bahasa (node/python/java/go/dotnet) di-install belakangan via `mise`, bukan via `dnf` di tahap ini.

### Kegunaan untuk Anda
Membawa 26 plugins WSL (`git docker docker-compose kubectl helm terraform aws gcloud azure ansible python pip node npm yarn golang rust sudo extract z history command-not-found vscode`), history 10000 + `SHARE_HISTORY`, alias `zshconfig/reload`, agar muscle-memory sama. `mise` di-activate di zsh supaya perintah bahasa yang di-install belakangan langsung tersedia di PATH.

### Instalasi
```bash
sudo dnf install -y zsh git curl util-linux-user
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# mise ke zsh (pengganti nvm; bahasa di-install belakangan via `mise use -g`)
curl -fsSL https://mise.run/zsh | sh

chsh -s $(which zsh)
```

Lalu copy `~/.zshrc` dari WSL, pastikan ada aktivasi mise:
```bash
eval "$(mise activate zsh)"
```
Bahasa (node/python/java/go/dotnet) BELUM di-install di sini — pakai `mise` belakangan, misal `mise use -g node@lts python@latest go@latest java@temurin-25`.

### Verifikasi
```bash
echo $SHELL; echo $ZSH_THEME
omz plugin list | tr ' ' '\n' | grep -E "autosuggest|syntax|docker|golang"
command -v mise && mise --version
# ketik `git sta` + TAB, restart terminal cek history tetap ada
```

> Oh-my-posh di `AppData/.../oh-my-posh` Windows tidak dibawa — yang dibawa adalah Oh My Zsh WSL sesuai permintaan.

---

## Tahap 8 — Base Tools Dev (tanpa bahasa, bahasa via mise belakangan)

### Apa itu?
Tool build dasar + CLI pendukung coding, TANPA compiler/interpreter bahasa. Bahasa sengaja tidak di-install via `dnf` agar tidak dobel dengan `mise` (Tahap 7).

### Kegunaan untuk Anda
`git/gh` untuk repo, `gcc/make` untuk build native, `vim/direnv` untuk edit + env per-project, `curl/wget/unzip/p7zip` untuk unduh/arsip. Semua bahasa (node/python/java/go/dotnet) menyusul via `mise use -g`.

### Instalasi
```bash
sudo dnf install -y git gh gcc make vim direnv \
  curl wget unzip p7zip p7zip-plugins
```

### Verifikasi
```bash
git --version; gh --version
gcc --version; make --version
mise --version
# bahasa belum ada di sini (normal): command -v node python3 java go dotnet || echo "belum di-install, pakai mise"
```

---

## Tahap 9 — VS Code

### Apa itu?
VS Code via repo resmi Microsoft (DNF), bukan Flatpak, agar `code` CLI + Podman/Testcontainers integrasi mulus. Extensions TIDAK di-install script — pakai Settings Sync setelah login.

### Kegunaan untuk Anda
Editor utama untuk project Spring/Go/.NET/Node. Install dari repo resmi agar update ikut `dnf upgrade`.

### Instalasi
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf install -y code
code --version
```

### Verifikasi
Buka 1 project Anda, login Settings Sync untuk mengembalikan extensions. `Dev Containers: Reopen in Container` pakai Podman socket (`DOCKER_HOST` Tahap 6).

---

## Tahap 10 — Office (OnlyOffice + Font MS)

### Apa itu?
MS Office LTSC tidak ada versi Linux. Pengganti yang di-install script: OnlyOffice (kompatibilitas `.docx/.xlsx` terbaik agar rapi dibuka di Word) + font MS agar dokumen tidak berantakan. Tidak termasuk client OneDrive/Email/PDF annotasi — di luar scope script ini.

### Kegunaan untuk Anda
90% kerja ketik-baca-print aman. 10% (macro VBA, template pixel-perfect) tidak akan 1:1 — itu batas yang diterima.

### Instalasi
```bash
# OnlyOffice (utama untuk .docx/.xlsx agar rapi dibuka di Word)
flatpak install -y flathub org.onlyoffice.desktopeditors

# Font Windows agar dokumen tidak berantakan
sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig
sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
fc-cache -f; fc-list | grep -i -E "calibri|cambria|arial|times" | head
```

### Verifikasi
Buka 1 `.docx` + 1 `.xlsx` tersulit Anda di OnlyOffice, cek font + tabel + print 1 halaman ke PDF.

---

## Tahap 11 — DB (DBeaver saja)

### Apa itu?
DBeaver Community (Flatpak) sebagai GUI database pengganti TablePlus (TablePlus tidak ada versi Linux — dibuang, bukan di-install).

### Kegunaan untuk Anda
Connect ke `postgres:16-alpine + redis:7-alpine` dari compose Podman Tahap 6. Tool DB lain (Beekeeper/pgAdmin/draw.io/tesseract) TIDAK di-install script — di luar scope.

### Instalasi
```bash
flatpak install -y flathub org.dbeaver.DBeaverCommunity
```

### Verifikasi
Connect DBeaver ke `localhost:5432` (compose Tahap 6 jalan).

---

## Tahap 12 — Chrome RPM + VA-API Cezanne

### Apa itu?
Chrome via repo RPM resmi Google, bukan Flatpak. Alasan: Flatpak portal sering bikin masalah mic, screen-share Wayland, dan `chrome://gpu` fallback ke software (SwANGLE). VA-API agar decode H.264/HEVC/VP9 lewat GPU (hemat CPU/baterai). Detail penuh: lihat `chrome-cezanne-vaapi.md`.

### Kegunaan untuk Anda
Browser utama + update ikut `dnf upgrade`. Driver VA-API dipilih sesuai GPU — jangan install semua sekaligus. AMD Cezanne Vega tidak punya decoder AV1 hardware (normal, batas hardware) → YouTube AV1 fallback CPU kecuali dipaksa H.264/VP9 via extension `enhanced-h264ify`.

### Instalasi
```bash
sudo dnf install -y fedora-workstation-repositories

# Fedora 41+ (DNF5):
sudo dnf config-manager setopt google-chrome.enabled=1
# Kalau DNF4 lama:
# sudo dnf config-manager --set-enabled google-chrome
# Fallback Spin tanpa fedora-workstation-repositories: tulis /etc/yum.repos.d/google-chrome.repo manual
# (baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64, gpgkey=linux_signing_key.pub)

sudo dnf install -y google-chrome-stable

# VA-API base (semua GPU):
sudo dnf install -y libva libva-utils ffmpeg-libs

# Pilih SATU sesuai GPU:
sudo dnf install -y mesa-va-drivers-freeworld   # AMD Cezanne Vega (swap dari mesa-va-drivers bila perlu)
# sudo dnf install -y intel-media-driver         # Intel gen 8+/Xe/Arc (jangan campur dengan paket AMD)
```

Flag Chrome permanen via override `~/.local` (awet `dnf upgrade`, per-user — jangan edit `/usr/share/applications/` milik RPM):
```bash
cp /usr/share/applications/google-chrome.desktop ~/.local/share/applications/
# Semua baris Exec= jadi:
# Exec=/usr/bin/google-chrome-stable --ozone-platform=wayland --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL %U
# Lalu killall chrome / logout agar reload.
# Troubleshoot F44: tambah --render-node-override=/dev/dri/renderD128
```

### Verifikasi
```bash
google-chrome-stable --version
dnf repolist | grep -i chrome
vainfo | grep VAProfile   # AMD Vega: H264/HEVCMain/VP9 ada, AV1 tidak ada = normal
# chrome://gpu → Video Decode: Hardware accelerated
# chrome://media-internals (video H.264/VP9) → VaapiVideoDecoder, kIsPlatformVideoDecoder: true
```

---

## Tahap 13 — Validasi Akhir + Tabel Gap Jujur

### Checklist 15 menit (jangan skip, sama dengan verifikasi script)
```bash
nmcli device status; glxinfo | grep renderer; wpctl status
ffmpeg -version | head -n 1
dnf repolist | grep -iE "rpmfusion|chrome"
google-chrome-stable --version
vainfo | grep -E "VAProfile|va_openDriver" | head -n 20
code --version
podman --version
fc-list | grep -ci "microsoft\|calibri"
```
Manual: suspend/wake, brightness, audio in/out, print 1 halaman, buka `.xlsx` kompleks, `mise --version`, `git clone` 1 project.

### Tabel gap (harus diterima)
| Windows Anda | Fedora | Status |
|---|---|---|
| Office LTSC macro VBA, template pixel-perfect | OnlyOffice/LibreOffice | 90% OK, macro kompleks pecah |
| OneDrive sync otomatis | rclone/OneDriver/browser | Tidak 1:1 |
| Acrobat Pro edit berat | Evince/Xournal++ | Baca/annotasi OK, edit berat tidak |
| TablePlus | DBeaver (Tahap 11) | Ganti, bukan install |
| Logi Options+ penuh | Solaar terbatas | Sebagian |
| Game Denuvo/SMASH/MTG Arena | Proton | Kemungkinan gagal |
| IDM, Samsung Flow, Phone Link | FDM/browser/KDE Connect | Ganti |

Backup otomatis dari hari pertama: `sudo dnf install -y timeshift` + Pika Backup untuk `~/`, jangan dimatikan SELinux/firewalld seperti kebiasaan di Windows.

