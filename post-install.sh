#!/usr/bin/env bash
# Fedora Post-Install — Tahap 1-4 (Base + RPM Fusion + Codec + Driver)
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

# Tahap 5 — Flathub / Flatpak (Tempat Install App User)
latpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak update -y
sudo dnf install -y gnome-software gnome-tweaks extension-manager

Tahap 6 — Podman (Native Fedora, Rootless)
# Podman sudah bawaan Fedora, pastikan lengkap + kompatibilitas Docker CLI
sudo dnf install -y podman podman-compose podman-docker buildah container-selinux
sudo dnf remove -y docker-ce docker-ce-cli 2>/dev/null || true

# Socket user untuk Testcontainers / Dev Containers / API kompatibel Docker
systemctl --user enable --now podman.socket
loginctl enable-linger $USER
echo $XDG_RUNTIME_DIR/podman/podman.sock
ls -l $XDG_RUNTIME_DIR/podman/podman.sock

# Tahap 7 — Toolchain Coding (Samakan dengan WSL)
sudo dnf install -y git gh gcc make vim direnv \
  python3 python3-pip \
  java-25-openjdk java-25-openjdk-devel maven gradle \
  golang gopls \
  curl wget unzip p7zip
url -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install lts
nvm alias default lts
npm i -g yarn
npm i -g pnpm
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/fedora/$(rpm -E %fedora)/packages-microsoft-prod.rpm
sudo dnf install -y dotnet-sdk-10.0

# Tahap 8 — Zsh 1:1 dari WSL (Oh My Zsh + pengshell)
sudo dnf install -y zsh git curl util-linux-user
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
chsh -s $(which zsh)

# Tahap 9 — VS Code + Extensions (Samakan 1.138)
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf install -y code

# Tahap 10 — Office 
# OnlyOffice (utama untuk .docx/.xlsx agar rapi dibuka di Word)
flatpak install -y flathub org.onlyoffice.desktopeditors
# Font Windows agar dokumen tidak berantakan
sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig
sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
fc-cache -f; fc-list | grep -i -E "calibri|cambria|arial|times" | head

# Tahap 11 — DB & Util Dev
flatpak install -y flathub org.dbeaver.DBeaverCommunity

# --- Verifikasi cepat ---
log "Verifikasi cepat"
ffmpeg -version 2>/dev/null | head -n 1 || warn "ffmpeg belum terinstall benar."
dnf repolist 2>/dev/null | grep -i rpmfusion || warn "RPM Fusion tidak muncul di repolist."

log "Selesai Tahap 1-4 tanpa reboot otomatis."
echo "Reboot DISARANKAN (terutama setelah akmod-wl / firmware), tapi tidak dipaksa."
read -r -p "Reboot sekarang? [y/N] " jawab
if [[ "${jawab,,}" == "y" || "${jawab,,}" == "yes" ]]; then
  sudo reboot
else
  echo "OK, reboot manual nanti dengan: sudo reboot"
fi
