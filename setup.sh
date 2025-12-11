#!/usr/bin/env bash
set -euo pipefail

# Hostname baru bisa lewat argumen, contoh:
#   ./setup-branding.sh vps-kerenku
# atau nanti akan ditanya kalau tidak diisi.
HOSTNAME_NEW="\${1:-}"

if [ -z "\$HOSTNAME_NEW" ]; then
  read -rp "Masukkan hostname baru (contoh: vps-kerenku): " HOSTNAME_NEW
fi

if [ -z "\$HOSTNAME_NEW" ]; then
  echo "Hostname tidak boleh kosong."
  exit 1
fi

echo "Menyet hostname ke: \$HOSTNAME_NEW"

if command -v hostnamectl >/dev/null 2>&1; then
  sudo hostnamectl set-hostname "\$HOSTNAME_NEW"
else
  echo "hostnamectl tidak ditemukan, mencoba metode lama..."
  echo "\$HOSTNAME_NEW" | sudo tee /etc/hostname >/dev/null
fi

# Install neofetch kalau belum ada
if ! command -v neofetch >/dev/null 2>&1; then
  echo "Menginstall neofetch..."
  if command -v apt >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y neofetch
  else
    echo "Tidak menemukan apt. Pastikan ini Ubuntu/Debian."
    exit 1
  fi
fi

NEOFETCH_CONF_DIR="\$HOME/.config/neofetch"
mkdir -p "\$NEOFETCH_CONF_DIR"

cat > "\$NEOFETCH_CONF_DIR/config.conf" << 'EOF'
print_info() {
    # Title custom (branding utama)
    info title "AunuHost Tech Device. OazonV2"
    info underline

    info "Host" host
    info "OS" distro
    info "Kernel" kernel
    info "Uptime" uptime
    info "Packages" packages
    info "Shell" shell
    info "Resolution" resolution
    info "DE" de
    info "WM" wm
    info "WM Theme" wm_theme
    info "Theme" theme
    info "Icons" icons
    info "Terminal" term
    info "CPU" cpu
    info "GPU" gpu
    info "Memory" memory
}
EOF

echo
echo "=== Selesai ==="
echo "- Hostname sistem sekarang: \$HOSTNAME_NEW"
echo "- Neofetch sudah dikustom: title = 'AunuHost Tech Device. OazonV2'"
echo
echo "Coba jalankan: neofetch"
