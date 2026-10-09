#!/bin/bash
# Crea 3 ISOs en dist/: SpOS2-N.iso, SpOS2-Programmer.iso, SpOS2-Premium.iso
# Antes:    ./build_pyinstaller.sh --sin-iso        (crea los binarios de dist/)
# Una vez:  sudo apt install debootstrap squashfs-tools xorriso mtools grub-pc-bin grub-efi-amd64-bin
# Uso:      ./build_iso.sh            (pide sudo, necesita internet y ~12 GB libres en /var/tmp)
# Teclado de la ISO: KEYMAP=es ./build_iso.sh   (por defecto latam)
set -e
umask 022
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
[ "$EUID" -eq 0 ] || exec sudo -E bash "$HERE/$(basename "$0")" "$@"

LIST="${*:-SpOS2-N SpOS2-Programmer SpOS2-Premium}"
KEYMAP="${KEYMAP:-latam}"
MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu}"   # ej: MIRROR=http://ar.archive.ubuntu.com/ubuntu
. /etc/os-release
CODE="${UBUNTU_CODENAME:?Este script necesita Ubuntu o Linux Mint}"
for N in $LIST; do [ -x "dist/$N/$N" ] || { echo "Falta dist/$N. Ejecuta antes: ./build_pyinstaller.sh --sin-iso"; exit 1; }; done

W="${W:-/var/tmp/spos2-iso}"; R=$W/rootfs
CACHE="$W-cache"        # descargas reutilizables: la 2.a ejecucion es mucho mas rapida
desmontar() { umount -lf "$R/var/cache/apt/archives" "$R/dev/pts" "$R/dev" "$R/proc" "$R/sys" 2>/dev/null || true; }
fin() {
  rc=$?; desmontar
  if [ $rc -ne 0 ] && [ -f "$R/debootstrap/debootstrap.log" ]; then
    cp "$R/debootstrap/debootstrap.log" /tmp/spos2-debootstrap.log
    echo "--- fallo: razon en /tmp/spos2-debootstrap.log ---"
    grep -iE "error|fail|cannot|denied|not found|no space" /tmp/spos2-debootstrap.log | tail -15
  fi
  if ! grep -q " $R" /proc/mounts; then rm -rf "$W" 2>/dev/null || { sleep 3; rm -rf "$W" 2>/dev/null || true; }; fi
}
trap fin EXIT
# limpiar restos de una ejecucion anterior (sin tocar nada si quedan montajes)
desmontar
grep -q " $R" /proc/mounts && { echo "Quedan montajes en $R; reinicia el PC y vuelve a intentar"; exit 1; }
rm -rf "$W"; mkdir -p "$W" "$CACHE/debootstrap" "$CACHE/apt"
findmnt -no OPTIONS -T "$W" | grep -qE 'noexec|nodev' && { echo "$W esta en un disco montado noexec/nodev. Usa otro: W=/root/spos2-iso ./build_iso.sh"; exit 1; }
[ "$(df -BG --output=avail "$W" | tail -1 | tr -dc 0-9)" -ge 10 ] || { echo "Poco espacio en $W (se necesitan ~10 GB)."; echo "En una sesion live de Mint el espacio es la RAM: monta un disco ext4 grande y usa  W=/media/mint/TU_DISCO/spos2-iso ./build_iso.sh"; exit 1; }

# ---- 1) sistema base (una sola vez para las tres ISOs)
debootstrap --cache-dir="$CACHE/debootstrap" --variant=minbase --arch=amd64 --components=main,universe "$CODE" "$R" "$MIRROR"
echo "deb $MIRROR $CODE main universe" > "$R/etc/apt/sources.list"
echo "nameserver 1.1.1.1" > "$R/etc/resolv.conf"
echo spos2 > "$R/etc/hostname"
mount --bind "$CACHE/apt" "$R/var/cache/apt/archives"; mount --bind /dev "$R/dev"; mount -t devpts devpts "$R/dev/pts"; mount -t proc proc "$R/proc"; mount -t sysfs sysfs "$R/sys"
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod +x "$R/usr/sbin/policy-rc.d"
mkdir -p "$R/etc/dpkg/dpkg.cfg.d"
printf 'path-exclude=/usr/share/doc/*\npath-exclude=/usr/share/man/*\npath-exclude=/usr/share/locale/*\n' > "$R/etc/dpkg/dpkg.cfg.d/minimo"
# firmware que un PC de escritorio no necesita (servidores, ARM, GPU nvidia): no se instala
for d in netronome mellanox qcom liquidio qed bnx2x cxgb3 cxgb4 dpaa2 ti-connectivity mrvl nvidia; do
  echo "path-exclude=/lib/firmware/$d/*" >> "$R/etc/dpkg/dpkg.cfg.d/minimo"
  echo "path-exclude=/usr/lib/firmware/$d/*" >> "$R/etc/dpkg/dpkg.cfg.d/minimo"
done

IN="chroot $R /usr/bin/env DEBIAN_FRONTEND=noninteractive"
$IN apt-get update
$IN apt-get install -y --no-install-recommends linux-image-generic linux-firmware casper initramfs-tools \
    systemd-sysv dbus udev xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-fbdev xinit \
    x11-xserver-utils network-manager wpasupplicant alsa-utils fontconfig fonts-dejavu-core

# ---- 2) arranque directo: autologin como root en tty1 -> X -> SpOS2 (al cerrarlo, apaga)
mkdir -p "$R/etc/systemd/system/getty@tty1.service.d"
cat > "$R/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOT'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOT
cat > "$R/root/.bash_profile" <<'EOT'
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
  startx -- -quiet >/dev/null 2>&1
  [ "$(cat /tmp/spos2.rc 2>/dev/null)" = 0 ] && systemctl poweroff
fi
EOT
cat > "$R/root/.xinitrc" <<EOT
setxkbmap $KEYMAP 2>/dev/null
amixer -q sset Master unmute 85% 2>/dev/null
/opt/spos2/app --fullscreen
echo \$? > /tmp/spos2.rc
EOT
$IN systemctl enable NetworkManager
$IN update-initramfs -u -k all
rm -rf "$R"/var/lib/apt/lists/* "$R"/usr/share/doc "$R"/usr/share/man "$R/usr/sbin/policy-rc.d"
umount -lf "$R/dev/pts" "$R/dev" "$R/proc" "$R/sys"

# ---- 3) una ISO por edicion: se agrega su binario y se empaqueta
for N in $LIST; do
  echo ">> $N.iso"
  rm -rf "$R/opt/spos2"; mkdir -p "$R/opt/spos2"
  cp -a "dist/$N" "$R/opt/spos2/$N"; ln -s "/opt/spos2/$N/$N" "$R/opt/spos2/app"
  I=$W/iso; rm -rf "$I"; mkdir -p "$I/boot/grub" "$I/casper"
  cp "$(ls "$R"/boot/vmlinuz-* | sort -V | tail -1)" "$I/boot/vmlinuz"
  cp "$(ls "$R"/boot/initrd.img-* | sort -V | tail -1)" "$I/boot/initrd"
  mksquashfs "$R" "$I/casper/filesystem.squashfs" -comp zstd -Xcompression-level 3 -noappend -no-progress -e boot
  cat > "$I/boot/grub/grub.cfg" <<EOT
set timeout=2
menuentry "SpOS2 ${N#SpOS2-}" {
    linux /boot/vmlinuz boot=casper quiet loglevel=3 ---
    initrd /boot/initrd
}
menuentry "SpOS2 ${N#SpOS2-} (video basico)" {
    linux /boot/vmlinuz boot=casper nomodeset ---
    initrd /boot/initrd
}
EOT
  grub-mkrescue -o "dist/$N.iso" "$I" -- -volid "$(echo "${N^^}" | tr - _)" >/dev/null 2>&1
  chown "${SUDO_USER:-root}" "dist/$N.iso"
done
echo "Listo. Probar con: ./ejecutar.sh premium --iso"
