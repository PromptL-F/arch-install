#!/bin/bash

# ============================================================
# Arch Linux Auto Installer - UEFI + ext4 + GRUB + Swap 4GB
# Disco fijo: /dev/sda
# Hostname: sasex | User: ludwin
# WiFi: ZTE_5GEngel
# ============================================================

set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "\( {BLUE}[INFO] \){NC} $1"; }
ok()    { echo -e "\( {GREEN}[OK] \){NC} $1"; }
warn()  { echo -e "\( {YELLOW}[WARN] \){NC} $1"; }
error() { echo -e "\( {RED}[ERROR] \){NC} $1"; exit 1; }

clear
echo -e "${GREEN}"
echo "=============================================="
echo "   Arch Linux Installer - sasex"
echo "   Disco: /dev/sda | UEFI + ext4 + Swap 4GB"
echo "=============================================="
echo -e "${NC}"

# --------------------------------------------------
# 1. Conexión a WiFi
# --------------------------------------------------
SSID="ZTE_5GEngel"
WIFI_PASS="Engelvi@24"

info "Conectando a la red WiFi: $SSID"

systemctl start iwd 2>/dev/null || true
sleep 2

WIFI_IFACE=$(iwctl device list | awk '/station/ {print $1; exit}')

if [[ -z "$WIFI_IFACE" ]]; then
    error "No se detectó ninguna interfaz WiFi."
fi

info "Interfaz detectada: $WIFI_IFACE"

iwctl --passphrase "$WIFI_PASS" station "$WIFI_IFACE" connect "$SSID" || {
    error "No se pudo conectar a la red $SSID."
}

sleep 3

if ! ping -c 2 archlinux.org &>/dev/null; then
    error "Conectado a WiFi pero sin acceso a internet."
fi

ok "Conectado correctamente a $SSID"

# --------------------------------------------------
# 2. Sincronizar reloj
# --------------------------------------------------
info "Sincronizando reloj..."
timedatectl set-ntp true
ok "Reloj sincronizado"

# --------------------------------------------------
# 3. Confirmación de seguridad
# --------------------------------------------------
DISK="/dev/sda"
EFI_PART="/dev/sda1"
SWAP_PART="/dev/sda2"
ROOT_PART="/dev/sda3"

echo
warn "¡¡¡ ATENCIÓN !!!"
echo -e "Se va a \( {RED}BORRAR TODO \){NC} el contenido de: ${YELLOW}\( DISK \){NC}"
echo
lsblk "$DISK"
echo
read -rp "Escribe exactamente 'SI BORRAR' para continuar: " CONFIRM

if [[ "$CONFIRM" != "SI BORRAR" ]]; then
    error "Instalación cancelada por seguridad."
fi

echo
warn "Última oportunidad. Empezando en 10 segundos..."
for i in {10..1}; do
    echo -ne "$i... "
    sleep 1
done
echo
ok "Continuando con la instalación..."

# --------------------------------------------------
# 4. Particionado
# --------------------------------------------------
info "Limpiando y creando tabla de particiones GPT en $DISK..."

wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -o "$DISK"

# EFI 1 GiB
sgdisk -n 1:0:+1G -t 1:EF00 -c 1:"EFI" "$DISK"

# Swap 4 GiB
sgdisk -n 2:0:+4G -t 2:8200 -c 2:"SWAP" "$DISK"

# Root (resto del disco)
sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOT" "$DISK"

partprobe "$DISK"
sleep 2

ok "Particiones creadas:"
lsblk "$DISK"

# --------------------------------------------------
# 5. Formateo
# --------------------------------------------------
info "Formateando particiones..."

mkfs.fat -F32 -n EFI "$EFI_PART"
mkswap -L SWAP "$SWAP_PART"
mkfs.ext4 -L ROOT -F "$ROOT_PART"

ok "Formateo completado"

# --------------------------------------------------
# 6. Montaje
# --------------------------------------------------
info "Montando sistemas de archivos..."

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
swapon "$SWAP_PART"

ok "Montaje correcto (incluyendo swap)"

# --------------------------------------------------
# 7. Instalación base + NetworkManager + Bluetooth
# --------------------------------------------------
info "Instalando sistema base + NetworkManager + Bluetooth..."

pacstrap -K /mnt base linux linux-firmware \
    networkmanager \
    bluez bluez-utils \
    grub efibootmgr \
    sudo nano vim \
    base-devel git \
    intel-ucode

ok "Sistema base instalado"

# --------------------------------------------------
# 8. fstab
# --------------------------------------------------
info "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab generado"

# --------------------------------------------------
# 9. Configuración del sistema
# --------------------------------------------------
info "Configurando el sistema..."

arch-chroot /mnt /bin/bash <<EOF
set -e

# Zona horaria
ln -sf /usr/share/zoneinfo/America/Santo_Domingo /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Teclado
echo "KEYMAP=us" > /etc/vconsole.conf

# Hostname
echo "sasex" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   sasex.localdomain sasex
HOSTS

# Contraseñas
echo "root:2007" | chpasswd
useradd -m -G wheel -s /bin/bash ludwin
echo "ludwin:1945" | chpasswd

# Sudo
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Servicios
systemctl enable NetworkManager
systemctl enable bluetooth

# GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg

echo "Configuración interna completada."
EOF

ok "Configuración del sistema terminada"

# --------------------------------------------------
# 10. Final
# --------------------------------------------------
echo
echo -e "${GREEN}=============================================="
echo "   ¡INSTALACIÓN COMPLETADA CON ÉXITO!"
echo "==============================================${NC}"
echo
echo "Hostname:     sasex"
echo "Usuario:      ludwin"
echo "Contraseña:   1945"
echo "Root pass:    2007"
echo
echo "Particiones:"
echo "  • /dev/sda1 → EFI   (1 GB)"
echo "  • /dev/sda2 → Swap  (4 GB)"
echo "  • /dev/sda3 → Root  (resto)"
echo
echo "Herramientas instaladas:"
echo "  • nmcli + bluetoothctl"
echo
echo -e "\( {YELLOW}IMPORTANTE: \){NC}"
echo "1. Cambia las contraseñas después del primer inicio."
echo "2. Para conectar la WiFi la primera vez:"
echo "   nmcli device wifi connect \"ZTE_5GEngel\" password \"Engelvi@24\""
echo
read -rp "¿Quieres reiniciar ahora? (s/N): " REBOOT

if [[ "\( REBOOT" =\~ ^[sS] \) ]]; then
    umount -R /mnt
    reboot
else
    echo "Puedes reiniciar manualmente con: reboot"
fi
