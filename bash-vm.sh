#!/usr/bin/env bash
set -euo pipefail

### Konfigurasi dasar
BASE_DIR="/var/lib/local-vms"

# Cek user root
if [ "$(id -u)" -ne 0 ]; then
  echo "Harus dijalankan sebagai root. Contoh:"
  echo "  sudo bash $0"
  exit 1
fi

# Cek dependency minimal
NEEDED_CMDS=(qemu-system-x86_64 qemu-img wget)
MISSING=()

for cmd in "${NEEDED_CMDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING+=("$cmd")
  fi
done

if [ "${#MISSING[@]}" -ne 0 ]; then
  echo "Perintah berikut belum terinstall: ${MISSING[*]}"
  echo
  if command -v nix-env >/dev/null 2>&1; then
    echo "Kamu sepertinya di NixOS. Contoh install:"
    echo "  nix-env -iA nixpkgs.qemu nixpkgs.wget"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "Di Debian/Ubuntu, contoh:"
    echo "  apt-get update && apt-get install -y qemu-system-x86 qemu-utils wget"
  fi
  exit 1
fi

echo "=== Pilih OS untuk VM ==="
echo "1) Ubuntu Server 22.04.5 LTS (Jammy)"
echo "2) Debian 11.8 Bullseye (netinst)"
read -rp "Pilih OS (1/2): " OS_CHOICE

case "$OS_CHOICE" in
  1)
    OS_NAME="ubuntu-22.04.5-live-server-amd64"
    ISO_URL="https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
    ;;
  2)
    OS_NAME="debian-11.8.0-amd64-netinst"
    ISO_URL="https://cdimage.debian.org/cdimage/archive/11.8.0/amd64/iso-cd/debian-11.8.0-amd64-netinst.iso"
    ;;
  *)
    echo "Pilihan tidak valid."
    exit 1
    ;;
esac

read -rp "Nama VM (label untuk QEMU) [vm-${OS_NAME}]: " VM_NAME
VM_NAME="${VM_NAME:-vm-${OS_NAME}}"

read -rp "Hostname yang diinginkan di dalam OS (boleh dikosongkan) []: " GUEST_HOSTNAME

read -rp "Direktori dasar untuk VM [${BASE_DIR}]: " BASE_DIR_INPUT
BASE_DIR="${BASE_DIR_INPUT:-$BASE_DIR}"

read -rp "Ukuran disk VM (GB) [20]: " DISK_SIZE
DISK_SIZE="${DISK_SIZE:-20}"

read -rp "RAM untuk VM (MB) [2048]: " RAM_MB
RAM_MB="${RAM_MB:-2048}"

read -rp "Jumlah vCPU/core [2]: " VCPUS
VCPUS="${VCPUS:-2}"

echo
echo "=== Konfigurasi KVM ==="
if [ -e /dev/kvm ] && [ -r /dev/kvm ]; then
  echo "/dev/kvm terdeteksi."
  read -rp "Aktifkan akselerasi KVM? (Y/n) [Y]: " KVM_CHOICE
  KVM_CHOICE="${KVM_CHOICE:-Y}"
  if [[ "$KVM_CHOICE" =~ ^[Yy]$ ]]; then
    QEMU_ACCEL="-enable-kvm -cpu host"
    KVM_STATUS="AKTIF"
  else
    QEMU_ACCEL="-cpu qemu64"
    KVM_STATUS="Non-KVM (software)"
  fi
else
  echo "/dev/kvm TIDAK tersedia, KVM tidak bisa dipakai (akan pakai software emulation)."
  QEMU_ACCEL="-cpu qemu64"
  KVM_STATUS="Non-KVM (software, /dev/kvm tidak ada)"
fi

VM_DIR="${BASE_DIR}/${VM_NAME}"
ISO_FILE="${VM_DIR}/${OS_NAME}.iso"
DISK_FILE="${VM_DIR}/${VM_NAME}.qcow2"

echo
echo "=== Ringkasan konfigurasi VM ==="
echo "Nama VM (QEMU) : $VM_NAME"
echo "Hostname OS    : ${GUEST_HOSTNAME:-<isi sendiri di installer / nanti>}"
echo "Direktori      : $VM_DIR"
echo "Disk           : ${DISK_SIZE}G (${DISK_FILE})"
echo "RAM            : ${RAM_MB} MB"
echo "vCPU           : ${VCPUS}"
echo "KVM            : $KVM_STATUS"
echo "ISO            : ${ISO_URL}"
echo

mkdir -p "$VM_DIR"

# Simpan hostname yang diinginkan sebagai catatan
echo "$GUEST_HOSTNAME" > "${VM_DIR}/desired-hostname.txt"

# Download ISO kalau belum ada
if [ -f "$ISO_FILE" ]; then
  echo "ISO sudah ada: $ISO_FILE (skip download)"
else
  echo "Download ISO ke $ISO_FILE ..."
  wget -c "$ISO_URL" -O "$ISO_FILE"
fi

# Buat disk VM
if [ -f "$DISK_FILE" ]; then
  echo "Disk VM sudah ada: $DISK_FILE (tidak akan di-overwrite)"
else
  echo "Membuat disk qcow2 ukuran ${DISK_SIZE}G ..."
  qemu-img create -f qcow2 "$DISK_FILE" "${DISK_SIZE}G"
fi

echo
echo "=== Men-generate script start VM (boot dari disk) ==="
START_SCRIPT="${VM_DIR}/start-${VM_NAME}.sh"

cat > "$START_SCRIPT" << EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$VM_DIR"

exec qemu-system-x86_64 \\
  $QEMU_ACCEL \\
  -name "$VM_NAME" \\
  -m "$RAM_MB" \\
  -smp "$VCPUS" \\
  -drive file="$DISK_FILE",if=virtio,format=qcow2 \\
  -boot order=c \\
  -display curses \\
  -nic user,model=virtio-net-pci
EOF

chmod +x "$START_SCRIPT"

echo "Script start VM dibuat: $START_SCRIPT"
echo "Nanti setelah instalasi selesai & ISO tidak dibutuhkan, jalankan:"
echo "  sudo $START_SCRIPT"
echo

echo "=== Menjalankan VM untuk instalasi (boot dari ISO) ==="
echo "Untuk keluar dari QEMU (display curses):"
echo "  Tekan:  Ctrl + A  lalu X"
echo
echo "CATATAN: Saat installer Ubuntu/Debian menanyakan hostname,"
echo "         kamu bisa isi: ${GUEST_HOSTNAME:-(sesuai keinginanmu)}"
echo

cd "$VM_DIR"

# Jalankan VM untuk proses instalasi (boot dari CD dulu)
# shellcheck disable=SC2086
exec qemu-system-x86_64 \
  $QEMU_ACCEL \
  -name "$VM_NAME" \
  -m "$RAM_MB" \
  -smp "$VCPUS" \
  -drive file="$DISK_FILE",if=virtio,format=qcow2 \
  -cdrom "$ISO_FILE" \
  -boot order=d \
  -display curses \
  -nic user,model=virtio-net-pci
