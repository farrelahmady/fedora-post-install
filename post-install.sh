#!/usr/bin/env bash
# Fedora Post-Install — Tahap 1-12 (Base + RPM Fusion + Codec + Driver + Dev + Chrome)
# Target utama: Ryzen 5 5500GT + Radeon Cezanne, Realtek 8168, Broadcom WiFi
# Cara pakai: ./post-install.sh  (jangan run sebagai root, pakai user sudo)
set -euo pipefail

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# --- 0. Preflight: jangan run sebagai root, pastikan sudo jalan ---
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Jangan jalankan script ini sebagai root. Pakai user biasa dengan sudo." >&2
  exit 1
fi
sudo -v
# keep-alive sudo selama script jalan
while true; do sudo -n true 2>/dev/null || true; sleep 60; done &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# --- Tahap 1 — Update Base + Firmware ---
log "Tahap 1: dnf upgrade base"
sudo dnf upgrade --refresh -y

log "Tahap 1: firmware via fwupd (best-effort, tidak menggagalkan script)"
if command -v fwupdmgr >/dev/null 2>&1; then
  sudo fwupdmgr refresh --force || warn "fwupdmgr refresh gagal (wajar jika tanpa LVFS/device didukung), lanjut."
  # get-updates hanya informatif
  sudo fwupdmgr get-updates || true
  sudo fwupdmgr update -y || warn "fwupdmgr update gagal/dibatalkan user, lanjut ke tahap berikutnya."
else
  warn "fwupdmgr tidak ditemukan, skip update firmware."
fi

# --- Tahap 2 — RPM Fusion (idempoten) ---
log "Tahap 2: RPM Fusion"
FEDORA_VER="$(rpm -E %fedora)"
if rpm -q rpmfusion-free-release >/dev/null 2>&1 && rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
  echo "RPM Fusion sudah terinstall, skip."
else
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
fi
sudo dnf upgrade --refresh -y

# --- Tahap 3 — Codec Multimedia (pengganti K-Lite) ---
log "Tahap 3: codec ffmpeg + gstreamer + lame"
# Fedora bawaan ada ffmpeg-free -> harus swap ke ffmpeg RPM Fusion, bukan install dobel
if rpm -q ffmpeg-free >/dev/null 2>&1; then
  sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
else
  sudo dnf install -y ffmpeg || sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
fi
# Quote wildcard agar di-expand oleh dnf, bukan oleh shell
sudo dnf install -y ffmpeg \
  "gstreamer1-plugins-bad-*" "gstreamer1-plugins-good-*" \
  "gstreamer1-plugins-base" "gstreamer1-plugins-ugly-*" \
  "gstreamer1-plugins-bad-freeworld*" \
  gstreamer1-plugin-openh264 gstreamer1-libav "lame*" \
  --exclude=gstreamer1-plugins-bad-free-devel

log "Tahap 3: VLC + Celluloid (pisah, hindari duplikat dnf+flatpak)"
# Pakai full Flathub, bukan filtered bawaan Fedora
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || warn "gagal menambah flathub remote."
# Celluloid cukup via dnf (tidak ada fallback flatpak agar tidak duplikat)
sudo dnf install -y celluloid || warn "celluloid via dnf gagal, skip (lanjut vlc)."
# VLC: dnf dulu, baru fallback flatpak kalau dnf gagal total
sudo dnf install -y vlc || flatpak install -y flathub org.videolan.VLC

# --- Tahap 4 — Driver ---
log "Tahap 4: pastikan tool deteksi ada"
sudo dnf install -y pciutils usbutils
log "Tahap 4: deteksi hardware"
lspci | grep -iE "vga|3d|display|network|audio|ethernet" || true
lsusb | grep -iE "logi|c270|wireless|broadcom" || true

# WiFi Broadcom: cek PCI maupun USB
if lspci -nn | grep -qi broadcom || lsusb | grep -qi broadcom; then
  log "Broadcom terdeteksi -> install broadcom-wl + akmod-wl"
  sudo dnf install -y akmod-wl broadcom-wl
  if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warn "Secure Boot AKTIF: modul akmod-wl butuh MOK enroll setelah reboot. Ikuti prompt biru MOK saat boot."
  fi
  echo "Catatan: akmod butuh 2-5 menit build setelah reboot. Cek dengan: modinfo wl"
else
  echo "Broadcom tidak terdeteksi, skip broadcom-wl."
fi

# Firmware umum: verifikasi, bukan instalasi buta (sudah bawaan kernel)
log "Tahap 4: pastikan linux-firmware ada"
if ! rpm -q linux-firmware >/dev/null 2>&1; then
  sudo dnf install -y linux-firmware
else
  echo "linux-firmware sudah terinstall."
fi

# --- CPU microcode ---
if lscpu | grep -qi "AuthenticAMD"; then
  echo "CPU AMD terdeteksi."
  if ! rpm -q amd-ucode-firmware >/dev/null 2>&1; then
    sudo dnf install -y amd-ucode-firmware || warn "amd-ucode-firmware gagal, biasanya sudah tercakup linux-firmware."
  fi
elif lscpu | grep -qi "GenuineIntel"; then
  echo "CPU Intel terdeteksi."
  if ! rpm -q microcode_ctl >/dev/null 2>&1; then
    sudo dnf install -y microcode_ctl || warn "microcode_ctl gagal, biasanya sudah bawaan."
  fi
fi

# --- GPU ---
GPU_INFO="$(lspci | grep -iE 'vga|3d|display' || true)"
echo "$GPU_INFO"
if echo "$GPU_INFO" | grep -qi nvidia; then
  echo "GPU Nvidia terdeteksi."
  echo "Pilih SATU (default: akmod-nvidia proprietary, butuh RPM Fusion nonfree + reboot + MOK jika Secure Boot):"
  echo "  sudo dnf install -y akmod-nvidia"
  echo "Jika ingin tetap nouveau open-source, tidak perlu install apa-apa."
  warn "Script TIDAK auto-install driver Nvidia agar user memilih sadar. Unkomen manual bila sudah yakin."
elif echo "$GPU_INFO" | grep -qi amd; then
  echo "GPU AMD -> driver in-kernel (amdgpu + Mesa), pastikan Vulkan tersedia."
  sudo dnf install -y mesa-vulkan-drivers xorg-x11-drv-amdgpu
elif echo "$GPU_INFO" | grep -qi intel; then
  echo "GPU Intel -> driver in-kernel, pastikan Vulkan + media driver tersedia."
  sudo dnf install -y mesa-vulkan-drivers intel-media-driver
else
  warn "GPU tidak terdeteksi dari lspci, skip install driver GPU."
fi

# --- Tahap 5 — Flathub / Flatpak (Tempat Install App User) ---
log "Tahap 5: Flathub + gnome-software"
if command -v flatpak >/dev/null 2>&1; then
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || warn "gagal menambah flathub remote."
  flatpak update -y || warn "flatpak update gagal, lanjut."
else
  warn "flatpak tidak ditemukan, skip setup flathub."
fi
sudo dnf install -y gnome-software gnome-tweaks extension-manager || warn "gnome-software/tweaks gagal, lanjut."

# --- Tahap 6 — Podman (Native Fedora, Rootless) ---
log "Tahap 6: podman rootless + docker compat"
# Podman sudah bawaan Fedora, pastikan lengkap + kompatibilitas Docker CLI
sudo dnf install -y podman podman-compose podman-docker buildah container-selinux || warn "install podman gagal sebagian, lanjut."
sudo dnf remove -y docker-ce docker-ce-cli 2>/dev/null || true

# Socket user untuk Testcontainers / Dev Containers / API kompatibel Docker
if systemctl --user enable --now podman.socket 2>/dev/null; then
  echo "podman.socket user aktif."
else
  warn "systemctl --user podman.socket gagal (wajar di chroot/ssh tanpa lingering), lanjut."
fi
loginctl enable-linger "${USER}" 2>/dev/null || warn "loginctl linger gagal, lanjut."
if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]]; then
  echo "$XDG_RUNTIME_DIR/podman/podman.sock"
  ls -l "$XDG_RUNTIME_DIR/podman/podman.sock" || true
else
  echo "Catatan: socket $XDG_RUNTIME_DIR/podman/podman.sock belum ada (normal sebelum login grafis). Cek setelah reboot: ls -l \$XDG_RUNTIME_DIR/podman/podman.sock"
  echo "Untuk Testcontainers/Dev Containers: export DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/podman/podman.sock"
fi

# --- Tahap 7 — Zsh 1:1 dari WSL (Oh My Zsh + pengshell + mise) ---
log "Tahap 7: zsh + oh-my-zsh + mise"
sudo dnf install -y zsh git curl util-linux-user || warn "install zsh gagal sebagian."
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || warn "oh-my-zsh gagal, lanjut."
else
  echo "oh-my-zsh sudah terinstall, skip."
fi
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [[ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" || warn "clone autosuggestions gagal."
else
  echo "zsh-autosuggestions sudah ada, skip."
fi
if [[ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" || warn "clone syntax-highlighting gagal."
else
  echo "zsh-syntax-highlighting sudah ada, skip."
fi
# mise (pengganti nvm/sdkman/dnf bahasa; bahasa di-install belakangan via `mise use -g`)
if ! command -v mise >/dev/null 2>&1; then
  curl -fsSL https://mise.run/zsh | sh || warn "install mise gagal, lanjut."
else
  echo "mise sudah terinstall, skip."
fi
if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
  chsh -s "$(command -v zsh)" || warn "chsh ke zsh gagal, jalankan manual: chsh -s \$(which zsh). Lanjut."
else
  echo "Shell default sudah zsh."
fi
echo "Catatan: copy ~/.zshrc dari WSL, pastikan ada aktivasi mise (eval \"\$(mise activate zsh)\"). Bahasa (node/python/java/go/dotnet) BELUM di-install di sini — pakai mise belakangan."

# --- Tahap 8 — Base Tools Dev (tanpa bahasa, bahasa via mise belakangan) ---
log "Tahap 8: git/gh/gcc + tools dasar"
sudo dnf install -y git gh gcc make vim direnv \
  curl wget unzip p7zip p7zip-plugins || warn "sebagian base tools gagal, cek manual."

# --- Tahap 9 — VS Code ---
log "Tahap 9: VS Code repo Microsoft"
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc || warn "import key vscode gagal, lanjut."
if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
  sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo' || warn "tulis vscode.repo gagal."
else
  echo "vscode.repo sudah ada, skip."
fi
if ! rpm -q code >/dev/null 2>&1; then
  sudo dnf install -y code || warn "install code gagal, lanjut."
else
  echo "VS Code sudah terinstall."
fi

# --- Tahap 10 — Office (OnlyOffice + Font MS) ---
log "Tahap 10: OnlyOffice + font Windows"
# OnlyOffice (utama untuk .docx/.xlsx agar rapi dibuka di Word)
flatpak install -y flathub org.onlyoffice.desktopeditors || warn "OnlyOffice gagal, lanjut."
# Font Windows agar dokumen tidak berantakan (idempoten)
sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig || warn "dep font gagal."
if ! rpm -q msttcore-fonts-installer >/dev/null 2>&1 && ! fc-list 2>/dev/null | grep -qi "Calibri"; then
  sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm || warn "msttcore fonts gagal, lanjut."
else
  echo "Font MS sudah terinstall, skip."
fi
fc-cache -f || true
fc-list 2>/dev/null | grep -i -E "calibri|cambria|arial|times" | head || true

# --- Tahap 11 — DB & Util Dev (DBeaver saja) ---
log "Tahap 11: DBeaver"
flatpak install -y flathub org.dbeaver.DBeaverCommunity || warn "dbeaver gagal, lanjut."

# --- Tahap 12 — Chrome RPM + VA-API Cezanne (lihat chrome-cezanne-vaapi.md) ---
log "Tahap 12: google-chrome-stable (RPM, bukan flatpak)"
# Alasan RPM: flatpak portal sering bikin mic/screen-share Wayland + chrome://gpu fallback SwANGLE.
if ! command -v google-chrome-stable >/dev/null 2>&1; then
  sudo dnf install -y fedora-workstation-repositories || warn "fedora-workstation-repositories tidak ada (wajar di Spin), pakai fallback repo manual."
  # DNF5 (F41+): setopt; DNF4 lama: --set-enabled; Spin: tulis repo manual
  if sudo dnf config-manager setopt google-chrome.enabled=1 2>/dev/null; then
    echo "Repo google-chrome diaktifkan via config-manager setopt."
  elif sudo dnf config-manager --set-enabled google-chrome 2>/dev/null; then
    echo "Repo google-chrome diaktifkan via --set-enabled."
  else
    echo "Buat repo google-chrome manual."
    sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null <<'EOF' || warn "tulis google-chrome.repo gagal."
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
  fi
  sudo dnf install -y google-chrome-stable || warn "install chrome gagal, lanjut."
else
  echo "google-chrome-stable sudah terinstall, skip."
fi

log "Tahap 12: driver VA-API untuk Chrome (pilih sesuai GPU, jangan semua)"
sudo dnf install -y libva libva-utils ffmpeg-libs || warn "libva base gagal, lanjut."
# GPU_INFO sudah dideteksi di Tahap 4; deteksi ulang bila kosong (script di-source parsial)
if [[ -z "${GPU_INFO:-}" ]]; then
  GPU_INFO="$(lspci | grep -iE 'vga|3d|display' || true)"
fi
if echo "$GPU_INFO" | grep -qi amd; then
  log "Tahap 12: AMD Cezanne Vega -> mesa-va-drivers-freeworld"
  if rpm -q mesa-va-drivers >/dev/null 2>&1 && ! rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
    sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing || sudo dnf install -y mesa-va-drivers-freeworld || warn "mesa-va freeworld gagal."
  else
    sudo dnf install -y mesa-va-drivers-freeworld || warn "mesa-va freeworld gagal."
  fi
elif echo "$GPU_INFO" | grep -qi intel; then
  log "Tahap 12: Intel iGPU -> intel-media-driver (gen 8+/Xe/Arc)"
  sudo dnf install -y intel-media-driver || warn "intel-media-driver gagal, lanjut."
  echo "Intel lama (gen 7 ke bawah) butuh legacy: sudo dnf install -y libva-intel-driver"
else
  echo "GPU non-AMD/Intel untuk VA-API, skip driver khusus (base libva saja)."
fi

# Flag Chrome permanen via override ~/.local (awet dnf upgrade, per-user)
# Jangan edit /usr/share/applications/google-chrome.desktop (milik RPM, tertimpa tiap upgrade).
if [[ -f /usr/share/applications/google-chrome.desktop ]]; then
  mkdir -p "$HOME/.local/share/applications"
  if [[ ! -f "$HOME/.local/share/applications/google-chrome.desktop" ]]; then
    cp /usr/share/applications/google-chrome.desktop "$HOME/.local/share/applications/" || warn "copy desktop override gagal."
  fi
  # Samakan semua baris Exec= ke Wayland + zero-copy decode (nama baru Chromium 131+: AcceleratedVideoDecodeLinuxGL)
  if grep -q "AcceleratedVideoDecodeLinuxGL" "$HOME/.local/share/applications/google-chrome.desktop" 2>/dev/null; then
    echo "Flag VA-API Chrome sudah ada, skip."
  else
    sed -i -E 's|^Exec=/usr/bin/google-chrome-stable.*|Exec=/usr/bin/google-chrome-stable --ozone-platform=wayland --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL %U|' "$HOME/.local/share/applications/google-chrome.desktop" || warn "patch Exec= chrome gagal, edit manual."
    echo "Flag Chrome ditulis. Reload dengan: killall chrome; lalu buka chrome://gpu untuk cek."
  fi
  echo "Troubleshoot F44 (chrome://gpu bohong accelerated tapi libva tak init): tambah --render-node-override=/dev/dri/renderD128"
  echo "Vega tanpa AV1 HW: pasang extension enhanced-h264ify agar YouTube pakai H.264/VP9."
else
  echo "google-chrome.desktop belum ada (chrome belum terinstall), skip flag override."
fi

# --- Verifikasi cepat ---
log "Verifikasi cepat"
ffmpeg -version 2>/dev/null | head -n 1 || warn "ffmpeg belum terinstall benar."
dnf repolist 2>/dev/null | grep -i rpmfusion || warn "RPM Fusion tidak muncul di repolist."
command -v google-chrome-stable >/dev/null 2>&1 && google-chrome-stable --version || warn "chrome belum terinstall."
dnf repolist 2>/dev/null | grep -i chrome || warn "repo chrome tidak muncul di repolist."
command -v vainfo >/dev/null 2>&1 && vainfo 2>/dev/null | grep -E "VAProfile|va_openDriver" | head -n 20 || echo "vainfo skip/belum ada driver VA-API (cek manual: vainfo | grep VAProfile)."
command -v code >/dev/null 2>&1 && code --version | head -n 1 || warn "code belum terinstall."
command -v podman >/dev/null 2>&1 && podman --version || warn "podman belum terinstall."

log "Selesai Tahap 1-12 tanpa reboot otomatis."
echo "Reboot DISARANKAN (terutama setelah akmod-wl / firmware), tapi tidak dipaksa."
read -r -p "Reboot sekarang? [y/N] " jawab
if [[ "${jawab,,}" == "y" || "${jawab,,}" == "yes" ]]; then
  sudo reboot
else
  echo "OK, reboot manual nanti dengan: sudo reboot"
fi
