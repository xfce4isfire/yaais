#!/bin/bash
set -euo pipefail
trap 'echo -e "\n\n[!] Received Ctrl + C, exiting."; umount -R /mnt 2>/dev/null; exit 1' INT

## set this stuff for later use
bold() { echo -e "\033[1m$1\033[0m"; }
warn() { echo -e "\033[1;31m$1\033[0m"; }
safe_read() {
    read -r -p "$(bold "$1") " "$2"
}

## intro
clear
bold "Custom arch install script"
echo
sleep 1

safe_read "Begin? [y/n]:" proceed
[[ "$proceed" != "y" ]] && echo "Exiting." && exit 0

## check network
bold "Checking internet connection"
ping -q -c 1 archlinux.org >/dev/null 2>&1 || {
    warn "No internet connection detected. Aborting."
    exit 1
}
echo "Internet is active."
sleep 1.5
clear

## get config
bold "Config setup"
sleep 1.5

# list block devices
bold "Available disks:"
lsblk -dpno NAME,SIZE | grep -v loop

safe_read "Enter disk to install to (e.g. /dev/sda):" DRIVE
[[ ! -b "$DRIVE" ]] && warn "Invalid block device." && exit 1

safe_read "Confirm the disk to wipe ($DRIVE). Type again to confirm:" confirm_drive
[[ "$confirm_drive" != "$DRIVE" ]] && warn "Disk mismatch." && exit 1

safe_read "Hostname for the system:" hostname
safe_read "New username to create:" newuser
safe_read "Passowrd for $newuser:" userpass
safe_read "Root password:" rootpass
safe_read "Extra packages to install (space-separated, or leave blank):" extra_pkgs
read -rp "Type 'YES' to continue: " final_confirm
[[ "$final_confirm" != "YES" ]] && echo "Aborting." && exit 1
sleep 1

## partitioning
bold "Wiping $DRIVE in 5 seconds! You have been warned."
sleep 5
echo "Grace period over."
sleep 1
echo "Beginning partitioning"
sleep 1
echo "Partitioning and wiping $DRIVE..."

wipefs -af "$DRIVE"
parted "$DRIVE" --script mklabel msdos
parted "$DRIVE" --script mkpart primary ext4 1MiB 100%

PART_ROOT="${DRIVE}1"

mkfs.ext4 -F "$PART_ROOT"

mount "$PART_ROOT" /mnt

## install the base packages

bold "Installing base system..."
sleep 2
pacstrap -K /mnt base linux linux-firmware sudo vim

genfstab -U /mnt >> /mnt/etc/fstab

## chroot part
bold "Entering chroot environment"
sleep 1.5
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
HOSTS

useradd -m -G wheel -s /bin/bash "$newuser"
echo -e "root:$rootpass" | chpasswd
echo -e "$newuser:$userpass" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

echo "Installing other neccesary packages"
sleep 1.5
pacman -Sy --noconfirm grub efibootmgr networkmanager


# optional packages
echo "Installing optional packages"
sleep 1.5
if [[ -n "$extra_pkgs" ]]; then
    pacman -Sy --noconfirm $extra_pkgs || echo "Some packages may have failed to install."
fi

# install grub
echo "Installing bootloader"
sleep 0.5
grub-install --target=i386-pc "$DRIVE"
grub-mkconfig -o /boot/grub/grub.cfg

echo "Chroot setup complete."
sleep 1
echo "Installation complete."

read -rp "Type 'YES' to begin artix migration: " confirm-migrate
[[ "$confirm-migrate" != "YES" ]] && echo "Aborting." && exit 1

sleep 2

echo "=== Artix Migration Starting ==="

# 1. Backup existing configs
mv -vf /etc/pacman.conf /etc/pacman.conf.arch
mv -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-arch

# 2. Fetch Artix pacman.conf and mirrorlist
curl -L https://gitea.artixlinux.org/packages/pacman/raw/branch/master/pacman.conf -o /etc/pacman.conf
curl -L https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/mirrorlist -o /etc/pacman.d/mirrorlist
cp -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.artix

# 3. Clean cache and refresh
pacman -Scc --noconfirm
pacman -Syy

# 4. Temporarily lower signature checking
sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf

# 5. Install keyring and sign Artix keys
pacman -Sy --noconfirm artix-keyring
pacman-key --populate artix
pacman-key --lsign-key 95AEC5D0C1E294FC9F82B253573A673A53C01BC2

# 6. Restore signature checking
sed -i 's/^SigLevel = Never/#SigLevel = Never/' /etc/pacman.conf
echo "SigLevel = Required DatabaseOptional" >> /etc/pacman.conf

# 7. Save current running daemons for later use
systemctl list-units --state=running \
  | grep -v systemd | awk '{print $1}' \
  | grep service > /root/daemon.list

# 8. Pre-cache essential Artix packages
pacman -Sw --noconfirm \
  base base-devel grub linux linux-headers mkinitcpio \
  rsync lsb-release esysusers etmpfiles artix-branding-base \
  openrc elogind-openrc openrc-system

# 9. Remove systemd and companions
pacman -Rdd --noconfirm \
  systemd systemd-libs systemd-sysvcompat pacman-mirrorlist dbus
rm -fv /etc/resolv.conf
cp -vf /etc/pacman.d/mirrorlist.artix /etc/pacman.d/mirrorlist

# 10. Install Artix base & init system
pacman -S --noconfirm \
  base base-devel grub linux linux-headers mkinitcpio \
  rsync lsb-release esysusers etmpfiles artix-branding-base \
  openrc elogind-openrc openrc-system

# 11. Reinstall GRUB
grub-install --target=i386-pc "$DRIVE"
grub-mkconfig -o /boot/grub/grub.cfg

# 12. Reinstall all packages from Artix repos
export LC_ALL=C
pacman -Sl system | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
pacman -Sl world  | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
pacman -Sl galaxy | grep installed | cut -d" " -f2 | pacman -S --noconfirm -

# 13. Add init scripts for your services
pacman -S --needed --noconfirm \
  acpid-init alsa-utils-init cronie-init cups-init fuse-init \
  haveged-init hdparm-init openssh-init samba-init syslog-ng-init

# 14. Enable OpenRC services
for svc in acpid alsasound cronie cupsd xdm fuse haveged hdparm smb sshd syslog-ng udev; do
  rc-update add "$svc" default
done

# 15. Networking setup
pacman -S --needed --noconfirm netifrc
echo 'nameserver 1.1.1.1' > /etc/resolv.conf
echo 'GRUB_CMDLINE_LINUX="net.ifnames=0"' >> /etc/default/grub
ln -sf /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 boot
rc-update add udev sysinit boot

# 17. Clean out leftover systemd accounts
for usr in journal journal-gateway timesync network bus-proxy journal-remote journal-upload resolve coredump; do
  userdel "systemd-$usr" 2>/dev/null || true
done
rm -rf /etc/systemd /var/lib/systemd

# 18. Remove systemd-specific boot directives
sed -i '/init=\/usr\/lib\/systemd\/systemd/d' /etc/default/grub
sed -i '/x-systemd/d' /etc/fstab

# 19. Regenerate initramfs
mkinitcpio -P

echo "=== Artix migration complete! ==="
sleep 2
echo "=== Installing MATE desktop and SDDM ==="

# Install MATE desktop environment
pacman -S --noconfirm mate mate-extra gvfs gvfs-mtp gvfs-smb xdg-user-dirs xdg-utils

# Install SDDM and OpenRC init script
pacman -S --noconfirm sddm sddm-openrc

# Set xdm (sddm) to start on boot
rc-update add xdm default

echo "Done!"
EOF
echo "Rebooting..."
reboot


