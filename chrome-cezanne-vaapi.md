# Chrome di Fedora — Instalasi & Optimasi VA-API (AMD Cezanne Vega + Intel)

> Tervalidasi: Ryzen 5 5500GT + Radeon iGPU Cezanne `05:00.0 VGA Advanced Micro Devices, Inc. [AMD/ATI] Cezanne [Radeon Vega Series]` (rev c9), `/dev/dri/renderD128`, Chrome `153.0.8010.52`. Bagian Intel ditambah sebagai varian (belum divalidasi di mesin ini).
> Hasil akhir tervalidasi di sesi ini. Pola: **Apa itu → Kegunaan → Instalasi → Verifikasi**.

## 1. Instalasi Chrome (RPM resmi)

### Apa itu?
Chrome via repo RPM resmi Google, bukan Flatpak. Alasan: Flatpak portal sering bikin masalah mic, screen-share Wayland, dan `chrome://gpu` fallback ke software (SwANGLE).

### Instalasi
```bash
cat /etc/fedora-release
sudo dnf upgrade --refresh -y
sudo dnf install -y fedora-workstation-repositories

# Fedora 41+ (DNF5):
sudo dnf config-manager setopt google-chrome.enabled=1
# Kalau DNF4 lama:
# sudo dnf config-manager --set-enabled google-chrome

sudo dnf install -y google-chrome-stable
```

Fallback Spin tanpa `fedora-workstation-repositories`:
```bash
sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
sudo dnf install -y google-chrome-stable
```

### Verifikasi (hasil sesi ini — sudah benar)
```bash
google-chrome-stable --version
# Google Chrome 153.0.8010.52

dnf repolist | grep -i chrome
# google-chrome  google-chrome  -> repo aktif, update ikut dnf upgrade

ls /opt/google/chrome/WidevineCdm/
# LICENSE  manifest.json  _platform_specific  -> DRM Netflix/Spotify siap
```

Update rutin: `sudo dnf upgrade -y` (tidak perlu manual).

## 2. Codec + Driver VA-API (pilih sesuai GPU)

### Apa itu?
Fedora default sunat codec paten. Chrome butuh `ffmpeg` full dari RPM Fusion + driver VA-API agar H.264/HEVC/VP9 decode via GPU. Beda GPU beda paket — jangan install semua sekaligus.

### Base (semua GPU)
```bash
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf install -y libva libva-utils ffmpeg-libs
```

### 2a. AMD Cezanne Vega (mesin ini — tervalidasi)
sudo dnf install -y mesa-va-drivers-freeworld
# Kalau sudah ada mesa-va-drivers biasa:
# sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
```

### Verifikasi (hasil sesi ini — sudah benar)
```bash
vainfo | grep VAProfile
# libva info: VA-API version 1.23.0
# libva info: Trying to open /usr/lib64/dri-nonfree/radeonsi_drv_video.so
# libva info: Trying to open /usr/lib64/dri-freeworld/radeonsi_drv_video.so
# libva info: Found init function __vaDriverInit_1_23
# libva info: va_openDriver() returns 0
#   VAProfileH264ConstrainedBaseline : VAEntrypointVLD / EncSlice
#   VAProfileH264Main               : VAEntrypointVLD / EncSlice
#   VAProfileH264High               : VAEntrypointVLD / EncSlice
#   VAProfileHEVCMain / Main10      : VAEntrypointVLD / EncSlice
#   VAProfileVP9Profile0 / Profile2 : VAEntrypointVLD
#   VAProfileNone                   : VAEntrypointVideoProc
```

Artinya: driver freeworld ke-load (`returns 0`), H.264/HEVC/VP9 siap. Tidak ada `VAProfileAV1` = normal untuk Vega (batas hardware, bukan bug).

### 2b. Intel iGPU (varian — UHD / Iris / Arc)

Pilih **satu** driver sesuai umur GPU. Jangan install keduanya + jangan install paket AMD di atas.

```bash
# Intel gen 8+ / UHD 6xx ke atas / Iris Xe / Arc (umum di laptop 2018+):
sudo dnf install -y intel-media-driver
# Kalau sebelumnya sudah ada driver bawaan Fedora:
# sudo dnf swap -y libva-intel-media-driver intel-media-driver --allowerasing

# Intel lama (gen 7 ke bawah, butuh driver legacy i965):
# sudo dnf install -y libva-intel-driver
```

Verifikasi:
```bash
vainfo | grep VAProfile
# Harus returns 0 dan muncul H264Main/High, HEVCMain/Main10, VP9Profile0/2.
# Intel gen 12+ (Alder Lake ke atas) umumnya juga muncul AV1Profile0 — beda dari Vega.

# Kalau vainfo error padahal GPU baru, paksa driver iHD:
LIBVA_DRIVER_NAME=iHD vainfo | head -20
```

Catatan Intel vs Vega:
- Intel baru **bisa AV1 hardware** → tidak wajib `enhanced-h264ify` seperti di Vega. Biarkan AV1 jalan untuk kualitas/watt terbaik.
- Tool ukur: `sudo dnf install -y intel-gpu-tools`, lalu `sudo intel_gpu_top` (kolom Video aktif saat 1080p).
- Laptop hybrid Intel+NVIDIA: decode tetap lewat Intel (`/dev/dri/renderD128`) kecuali butuh NVDEC — jangan campur flag `VaapiOnNvidiaGPUs` kalau decode mau di Intel.

## 3. Flag Chrome permanen (override lokal)

### Kenapa `~/.local` bukan `/usr/share`?
`/usr/share/applications/google-chrome.desktop` milik paket RPM — tiap `dnf upgrade` ditulis ulang, flag hilang. Edit di situ juga merusak `rpm -V`, butuh sudo, dan memaksa semua user 1 flag sama. Override `~/.local/share/applications/` menang via spek XDG, awet update, per-user.

### Instalasi (Intel/AMD — flag sama)
```bash
cp /usr/share/applications/google-chrome.desktop ~/.local/share/applications/
```

Edit `~/.local/share/applications/google-chrome.desktop`, semua baris `Exec=` jadi:
```
Exec=/usr/bin/google-chrome-stable --ozone-platform=wayland --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL %U
```
Lalu `killall chrome` / logout agar reload. Chrome 138+ sudah Wayland default; nama flag baru `AcceleratedVideoDecodeLinuxGL` (pengganti `VaapiVideoDecodeLinuxGL` sejak Chromium 131).

Troubleshoot Fedora 44 (`chrome://gpu` bohong `Hardware accelerated` tapi libva tidak init): tambah `--render-node-override=/dev/dri/renderD128` atau `--hardware-video-decode-path=/dev/dri/renderD128`.

### Setting Chrome
- `chrome://settings/system`: Hardware acceleration = ON, Continue running background apps = OFF
- `chrome://settings/performance`: Memory saver = Maximum, Energy saver = ON saat baterai
- `chrome://flags/#enable-accelerated-video-decode` = Enabled
- Khusus AMD Vega (tanpa AV1 HW): extension `enhanced-h264ify` → block AV1, agar YouTube pakai H.264/VP9 yang bisa GPU-decode. Intel gen 12+ tidak perlu.

## 4. Validasi decode (hasil sesi ini)

```bash
LIBVA_MESSAGING_LEVEL=2 google-chrome --user-data-dir=/tmp/chrometest 2>&1 | grep -i libva
# ... va_openDriver() returns 0  -> Chrome bisa init driver Vega (OK)
```

Test negatif yang terbukti benar: video `The Ocean 4K` YouTube (`https://www.youtube.com/watch?v=YFmV_MRSD7M`) di `chrome://media-internals`:
```
kVideoDecoderName: Dav1dVideoDecoder
kIsPlatformVideoDecoder: false
codec: av1, 854x480
```
Ini **bukan gagal setting** — video AV1 di GPU tanpa decoder AV1 memang fallback ke CPU Dav1d, YouTube sampai turunkan ke 480p. Test yang valid harus H.264/VP9 (setelah h264ify): harusnya `VaapiVideoDecoder`, `kIsPlatformVideoDecoder: true`, `radeontop` aktif, CPU di `btop` turun drastis.

Checklist hijau = optimal:
1. `chrome://gpu` → Video Decode: Hardware accelerated
2. `chrome://media-internals` (video H.264/VP9) → VaapiVideoDecoder
3. `radeontop` / `intel_gpu_top` gerak saat 1080p
