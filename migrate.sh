#!/bin/bash
set -euo pipefail

echo "[!] Starting artix migration in 5 seconds"
sleep 5

# Backup configs
mv -vf /etc/pacman.conf /etc/pacman.conf.arch
mv -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-arch
sleep 1

# Download Artix configs
curl -L https://gitea.artixlinux.org/packages/pacman/raw/branch/master/pacman.conf -o /etc/pacman.conf
curl -L https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/mirrorlist -o /etc/pacman.d/mirrorlist
cp -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.artix
sleep 2

# Clean and refresh
pacman -Scc --noconfirm
pacman -Syy
sleep 2

# Keyring
sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
pacman -Sy --noconfirm artix-keyring
pacman-key --populate artix
pacman-key --lsign-key 95AEC5D0C1E294FC9F82B253573A673A53C01BC2
sed -i 's/^SigLevel = Never/#SigLevel = Never/' /etc/pacman.conf
echo "SigLevel = Required DatabaseOptional" >> /etc/pacman.conf
sleep 2

# List running services
systemctl list-units --state=running \
  | grep -v systemd | awk '{print $1}' | grep service > /root/daemon.list
sleep 2

# Pre-download essential packages
pacman -Sw --noconfirm base base-devel grub linux linux-headers mkinitcpio rsync lsb-release esysusers etmpfiles artix-branding-base openrc elogind-openrc openrc-system
sleep 2

# Remove systemd
pacman -Rdd --noconfirm systemd systemd-libs systemd-sysvcompat pacman-mirrorlist dbus
rm -f /etc/resolv.conf
cp -vf /etc/pacman.d/mirrorlist.artix /etc/pacman.d/mirrorlist
sleep 2

# Install Artix base
pacman -S --noconfirm base base-devel grub linux linux-headers mkinitcpio rsync lsb-release esysusers etmpfiles artix-branding-base openrc elogind-openrc openrc-system
sleep 2

# Reinstall GRUB
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
sleep 2

# Reinstall all packages
export LC_ALL=C
pacman -Sl system | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
pacman -Sl world  | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
pacman -Sl galaxy | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
sleep 2

# Add init scripts
pacman -S --needed --noconfirm acpid-init alsa-utils-init cronie-init cups-init fuse-init haveged-init hdparm-init openssh-init samba-init syslog-ng-openrc

# Enable services
for svc in acpid alsasound cronie cupsd xdm fuse haveged hdparm smb sshd syslog-ng udev; do
  rc-update add "$svc" default
done

# Networking
pacman -S --needed --noconfirm netifrc
echo 'nameserver 1.1.1.1' > /etc/resolv.conf
echo 'GRUB_CMDLINE_LINUX="net.ifnames=0"' >> /etc/default/grub
ln -sf /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 boot
rc-update add udev sysinit boot

# Remove systemd users
for usr in journal journal-gateway timesync network bus-proxy journal-remote journal-upload resolve coredump; do
  userdel "systemd-$usr" 2>/dev/null || true
done
rm -rf /etc/systemd /var/lib/systemd

# Cleanup
sed -i '/init=\/usr\/lib\/systemd\/systemd/d' /etc/default/grub
sed -i '/x-systemd/d' /etc/fstab

# Regenerate initramfs
mkinitcpio -P

# Install MATE + SDDM
pacman -S --noconfirm mate mate-extra gvfs gvfs-mtp gvfs-smb xdg-user-dirs xdg-utils sddm sddm-openrc
rc-update add xdm default

echo "[!] Migrataion done"
