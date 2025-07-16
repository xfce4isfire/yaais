#!/bin/bash
set -euo pipefail

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
sleep 1
clear

## get config
bold "Config setup"

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
safe_read "Desktop Environment (gnome, plasma, xfce, none):" desktop_env
safe_read "Extra packages to install (space-separated, or leave blank):" extra_pkgs

## partitioning
bold "Wiping $DRIVE in 5 seconds! You have been warned."
sleep 5
echo "Grace period over."
sleep 0.5
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

pacman -Sy --noconfirm grub efibootmgr networkmanager

# install chosen DE
case "$desktop_env" in
    gnome)
        pacman -Sy --noconfirm gnome gdm
        systemctl enable gdm
        ;;
    plasma)
        pacman -Sy --noconfirm plasma sddm
        systemctl enable sddm
        ;;
    xfce)
        pacman -Sy --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
        systemctl enable lightdm
        ;;
    none|"")
        echo "Skipping DE installation."
        ;;
    *)
        echo "Invalid DE selection. Skipping..."
        ;;
esac

# optional packages
if [[ -n "$extra_pkgs" ]]; then
    pacman -Sy --noconfirm $extra_pkgs || echo "Some packages may have failed to install."
fi

# install grub
grub-install --target=i386-pc "$DRIVE"
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager

echo "Chroot setup complete."
EOF

echo "You may now reboot into your new system."
