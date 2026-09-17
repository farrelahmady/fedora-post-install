# Fedora Post-Install — Migrasi Lengkap dari Windows + WSL (Coding + Office)

> Target: Fedora Workstation (GNOME) di PC `MRPEPENG` — Ryzen 5 5500GT + Radeon iGPU (Cezanne 0x1638), A520M-HVS, 16GB RAM, NVMe Kingston SNV2S1000G, LAN Realtek 8168 + WiFi Broadcom 2.10, Dual monitor 1080p (HDMI AOC + DP-to-VGA), Audio AMD + Logi C270 + Mic USB MCN-10.
> Varian: **Podman rootless (native Fedora)** + **Zsh 1:1 dari WSL**.
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
sudo dnf install -y ffmpeg \
  gstreamer1-plugins-{bad-*,good-*,base} \
  gstreamer1-plugin-openh264 gstreamer1-libav lame* \
  --exclude=gstreamer1-plugins-bad-free-devel
sudo dnf install -y vlc celluloid || flatpak install -y flathub org.videolan.VLC io.github.celluloid_player.Celluloid
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
lspci | grep -iE "vga|network|audio|ethernet"
lsusb | grep -iE "logi|c270|wireless|broadcom"

# Hanya jika lspci menunjukkan Broadcom wireless:
sudo dnf install -y broadcom-wl akmod-wl
sudo reboot

# Firmware umum (AMD microcode + linux-firmware sudah bawaan, pastikan):
sudo dnf install -y linux-firmware amd-ucode-firmware 2>/dev/null || true
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
Aturan main: toolchain coding via DNF (Tahap 7), app desktop (OnlyOffice, OBS, DBeaver, Spotify, Discord) via Flatpak agar tidak merusak base dan mudah rollback.

### Instalasi
```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
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
loginctl enable-linger $USER
echo $XDG_RUNTIME_DIR/podman/podman.sock
ls -l $XDG_RUNTIME_DIR/podman/podman.sock

# Opsional: alias agar muscle-memory `docker` tetap jalan
echo 'alias docker=podman' >> ~/.zshrc

# Autostart DB via systemd (pengganti `systemctl enable docker`)
mkdir -p ~/dev-db
```

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

## Tahap 7 — Toolchain Coding (Samakan dengan WSL)

### Apa itu?
Compiler/interpreter + build tools + package manager untuk stack Anda (Java/Spring, Go, .NET, Node, Python).

### Kegunaan untuk Anda
Mereplikasi WSL Ubuntu 26.04 Anda di Fedora. Perbedaan utama: Fedora pakai `dnf`, Python `pip` terpisah, path JVM beda (`/usr/lib/jvm/java-21-openjdk`, bukan `-amd64`), Go via dnf di `/usr/bin` bukan `/usr/local/go/bin`.

### Instalasi
```bash
sudo dnf install -y git gh gcc make vim neovim direnv \
  python3 python3-pip \
  java-21-openjdk java-21-openjdk-devel maven gradle \
  golang gopls \
  curl wget unzip p7zip

# Node via nvm (sama persis dengan WSL v24.21.0)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 24.21.0
nvm alias default 24.21.0
npm i -g yarn

# .NET 10 via repo Microsoft (samakan dengan SDK 10.0.112 di WSL)
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/fedora/$(rpm -E %fedora)/packages-microsoft-prod.rpm
sudo dnf install -y dotnet-sdk-10.0

# Verifikasi versi samakan dengan WSL
git --version        # WSL: 2.53.0
node -v; npm -v      # WSL: v24.21.0 / 11.19.0
python3 --version    # WSL: 3.14.4
java -version        # WSL: 21.0.12
mvn -v; gradle -v
go version
dotnet --list-sdks   # WSL: 10.0.112
gcc --version; make --version
```

### Verifikasi
Clone 1 repo Java/Spring + 1 repo Go/Node Anda, `mvn compile`, `go build ./...`, `npm ci`, `dotnet build`, `podman compose up` DB-nya.

---

## Tahap 8 — Zsh 1:1 dari WSL (Oh My Zsh + pengshell)

### Apa itu?
Zsh + Oh My Zsh adalah shell interaktif + framework theme/plugin. Theme `pengshell` Anda ada di `~/.oh-my-zsh/themes/`. Plugin community (`zsh-autosuggestions`, `zsh-syntax-highlighting`) ada di `custom/plugins`.

### Kegunaan untuk Anda
Membawa 26 plugins WSL (`git docker docker-compose kubectl helm terraform aws gcloud azure ansible python pip node npm yarn golang rust sudo extract z history command-not-found vscode`), history 10000 + `SHARE_HISTORY`, alias `zshconfig/reload`, PATH `nvm/go/opencode` agar muscle-memory sama.

Tidak 100% copy-paste karena `JAVA_HOME` Ubuntu (`.../java-21-openjdk-amd64`) beda dengan Fedora (`.../java-21-openjdk`).

### Instalasi
```bash
sudo dnf install -y zsh git curl util-linux-user
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
chsh -s $(which zsh)
```

Lalu copy `~/.zshrc` dari WSL dengan 2 edit wajib:
```diff
- ZSH_THEME="pengshell"   # tetap, file sudah ada di themes/
- plugins=(git docker docker-compose kubectl helm terraform aws gcloud azure ansible python pip node npm yarn golang rust sudo extract z history command-not-found vscode zsh-autosuggestions zsh-syntax-highlighting)
- export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
+ export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
- export PATH="$PATH:/usr/local/go/bin"
+ # hapus baris /usr/local/go/bin jika go via dnf (sudah di /usr/bin), pertahankan $HOME/go/bin
  export PATH="$PATH:$HOME/go/bin"
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

### Verifikasi
```bash
echo $SHELL; echo $ZSH_THEME
omz plugin list | tr ' ' '\n' | grep -E "autosuggest|syntax|docker|golang"
# ketik `git sta` + TAB, ketik `podman ps` tanpa sudo (atau `docker ps` jika alias aktif), restart terminal cek history tetap ada
```

> Oh-my-posh di `AppData/.../oh-my-posh` Windows tidak dibawa — yang dibawa adalah Oh My Zsh WSL sesuai permintaan.

---

## Tahap 9 — VS Code + Extensions (Samakan 1.138)

### Apa itu?
VS Code via repo resmi Microsoft (DNF), bukan Flatpak, agar `code` CLI + Podman/Testcontainers integrasi mulus. Extensions disync via Settings Sync atau install manual dari daftar WSL.

### Kegunaan untuk Anda
Daftar extensions WSL Anda yang wajib dibawa: `Go, Java Pack (redhat.java, spring-boot, maven, gradle, debug, test), C# DevKit + pack, Jupyter pack, Prettier, GitLens, REST Client, LiveServer, Path Intellisense, Rainbow CSV, Import Cost, Indent Rainbow`.

### Instalasi
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf install -y code
code --version  # samakan 1.138.0

# Login Settings Sync di VS Code, atau manual:
code --install-extension golang.go
code --install-extension redhat.java
code --install-extension vmware.vscode-spring-boot
code --install-extension vscjava.vscode-maven
code --install-extension vscjava.vscode-gradle
code --install-extension ms-dotnettools.csdevkit
code --install-extension ms-toolsai.jupyter
code --install-extension esbenp.prettier-vscode
code --install-extension eamodio.gitlens
code --install-extension humao.rest-client
code --install-extension ritwickdey.liveserver
code --list-extensions | wc -l
```

### Verifikasi
Buka project Spring + Go + .NET Anda, pastikan Java LS + Gopls + C# DevKit tidak error, `Dev Containers: Reopen in Container` pakai Podman socket (`DOCKER_HOST` Tahap 6).

---

## Tahap 10 — Office (Pengganti LTSC 2024 + Acrobat + OneDrive)

### Apa itu?
MS Office LTSC 2024 + Acrobat Pro tidak ada versi Linux. Pengganti: OnlyOffice (kompatibilitas .docx/.xlsx terbaik), LibreOffice (bawaan, cadangan), font MS, `rclone/OneDriver` untuk OneDrive, Thunderbird untuk Outlook, Xournal++ untuk annotasi PDF.

### Kegunaan untuk Anda
Anda dari Office LTSC + Teams + Outlook + OneDrive 26 + Adobe Acrobat Pro 25 + 365 Copilot. 90% kerja ketik-baca-print aman, 10% (macro VBA, template pixel-perfect, sync otomatis, edit PDF berat, Copilot di desktop) tidak akan 1:1.

### Instalasi
```bash
# OnlyOffice (utama untuk .docx/.xlsx agar rapi dibuka di Word)
flatpak install -y flathub org.onlyoffice.desktopeditors

# Font Windows agar dokumen tidak berantakan
sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig
sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
fc-cache -f; fc-list | grep -i -E "calibri|cambria|arial|times" | head

# OneDrive (tidak ada client resmi, pilih satu)
sudo dnf install -y rclone
# rclone config  # ikuti wizard onedrive, lalu: rclone mount onedrive: ~/OneDrive --vfs-cache-mode writes &
# alternatif GUI: OneDriver dari COPR

# Email + PDF annotasi
sudo dnf install -y thunderbird
flatpak install -y flathub com.github.xournalpp.xournalpp
```

### Verifikasi
Buka 1 `.docx` + 1 `.xlsx` tersulit Anda di OnlyOffice, cek font + tabel + print 1 halaman ke PDF. Setup `rclone ls onedrive:` jalan. Catatan: folder `KMSpico/` di Windows tidak relevan — semua di sini gratis legal.

---

## Tahap 11 — DB & Util Dev (Pengganti TablePlus dkk)

### Apa itu?
Tool database + API + diagram Anda. Satu yang harus dibuang: TablePlus (tidak ada Linux).

### Kegunaan / Pemetaan
* `TablePlus 6.5 → BUANG`, pakai `Beekeeper 5.3 + DBeaver 25 + pgAdmin 9.4` yang sudah Anda punya (ketiganya ada Linux)
* `Apidog 2.8 + Postman 11.47 →` Apidog AppImage + Postman tar/Flatpak tidak resmi, atau pindah ke `Bruno` (Flatpak, Git-friendly)
* `draw.io 27 →` Flatpak `draw.io`
* `Figma Desktop →` browser + Figma Agent Linux
* `Tesseract 5.5 →` `dnf install tesseract-ocr + tesseract-ocr-osd -l ind+eng`
* `Notion 7.6 →` browser / Flatpak tidak resmi (tidak ada native Linux)
* `ChatGPT Classic →` browser

### Instalasi
```bash
flatpak install -y flathub io.beekeeperstudio.Studio org.dbeaver.DBeaverCommunity
sudo dnf install -y pgadmin4 2>/dev/null || flatpak install -y flathub org.pgadmin.pgadmin4 2>/dev/null || echo "pgAdmin via web/podman jika gagal"
flatpak install -y flathub com.jgraph.drawio.desktop
sudo dnf install -y tesseract tesseract-osd
flatpak install -y flathub com.usebottles.bottles 2>/dev/null || true  # opsional, bukan untuk Office
```

### Verifikasi
Connect Beekeeper/DBeaver ke `localhost:5432` (compose Tahap 6), buka 1 diagram draw.io, `tesseract --list-langs | grep ind`.

---

## Tahap 12 — Browser / Media / Util Lain

### Pemetaan Windows → Fedora
* `Chrome 152 + Firefox 156 + Edge →` Firefox bawaan + Chrome via RPM (`google-chrome-stable`), Edge tidak perlu (pakai Chrome)
* `OBS 32 →` Flatpak `com.obsproject.Studio`
* `MPC-HC 1.7 →` VLC/Celluloid (Tahap 3)
* `Spotify + Discord + WhatsApp →` Flatpak `Spotify/Discord`, WhatsApp via browser/Flatpak tidak resmi
* `7-Zip 24 →` `p7zip + File Roller bawaan`
* `IDM 6.43 →` Free Download Manager Flatpak / `aria2c`
* `Logi Options+ →` `Solaar` (terbatas, tidak semua preset jalan): `sudo dnf install -y solaar`
* `DroidCam 6.5 →` client Linux `droidcam` + `v4l2loopback`
* `Cloudflare WARP 26 →` repo Cloudflare Linux `warp-cli`
* `Google Drive 131 →` `Settings → Online Accounts → Google` (Nautilus ter-mount otomatis)
* `Rufus →` Fedora Media Writer / Popsicle (untuk bikin USB installer lain)
* `TradingView + Stockbit →` browser
* `Steam + AoE III/ETS2/Shank2 →` `flatpak install flathub com.valvesoftware.Steam` + aktifkan Proton; `SMASH LEGENDS/MTG Arena/Denuvo` kemungkinan gagal anti-cheat — cek `protondb.com` dulu

### Instalasi contoh
```bash
flatpak install -y flathub com.obsproject.Studio com.spotify.Client com.discordapp.Discord
sudo dnf install -y p7zip p7zip-plugins solaar aria2
flatpak install -y flathub com.valvesoftware.Steam
```

### Verifikasi
Test meeting browser (mic MCN-10 + C270 + share-screen Wayland), putar Spotify, login Discord, buka Steam 1 game ringan.

---

## Tahap 13 — Validasi Akhir + Tabel Gap Jujur

### Checklist 15 menit (jangan skip)
```bash
nmcli device status; glxinfo | grep renderer; wpctl status
podman compose -f ~/dev-db/docker-compose.yml ps
# pembanding Docker (jika pakai varian alternatif Tahap 6b): docker compose -f ~/dev-db/docker-compose.yml ps
code --list-extensions | grep -E "golang|redhat|dotnet|jupyter|gitlens"
fc-list | grep -ci "microsoft\|calibri"
```
Manual: suspend/wake, brightness, audio in/out, print 1 halaman, buka `.xlsx` kompleks, `git clone + podman compose up` 1 project.

### Tabel gap (harus diterima)
| Windows Anda | Fedora | Status |
|---|---|---|
| Office LTSC macro VBA, template pixel-perfect | OnlyOffice/LibreOffice | 90% OK, macro kompleks pecah |
| OneDrive sync otomatis | rclone/OneDriver/browser | Tidak 1:1 |
| Acrobat Pro edit berat | Evince/Xournal++ | Baca/annotasi OK, edit berat tidak |
| TablePlus | Beekeeper/DBeaver | Ganti, bukan install |
| Logi Options+ penuh | Solaar terbatas | Sebagian |
| Game Denuvo/SMASH/MTG Arena | Proton | Kemungkinan gagal |
| IDM, Samsung Flow, Phone Link | FDM/browser/KDE Connect | Ganti |

Backup otomatis dari hari pertama: `sudo dnf install -y timeshift` + Pika Backup untuk `~/`, jangan dimatikan SELinux/firewalld seperti kebiasaan di Windows.

