#!/bin/bash

echo "[!] Starting artix migration in 5 seconds"
sleep 5

mv -vf /etc/pacman.conf /etc/pacman.conf.arch
mv -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-arch
sleep 1

curl -L https://gitea.artixlinux.org/packages/pacman/raw/branch/master/pacman.conf -o /etc/pacman.conf
curl -L https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/mirrorlist -o /etc/pacman.d/mirrorlist
cp -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.artix
sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
pacman -S dhcpcd dhcpcd-openrc
sleep 2

rm -rf /var/cache/pacman
pacman -Syy
sleep 2

pacman -Sw --noconfirm \
  base base-devel grub linux linux-headers mkinitcpio \
  rsync lsb-release esysusers etmpfiles artix-branding-base \
  openrc elogind-openrc openrc-system \
  netifrc \
  acpid-openrc alsa-utils-openrc cronie-openrc cups-openrc fuse-openrc \
  haveged-openrc hdparm-openrc openssh-openrc samba-openrc syslog-ng-openrc \
  gvfs gvfs-mtp gvfs-smb xdg-user-dirs xdg-utils \
 dhcpcd networkmanager-openrc dhcpcd-openrc udev dbus
sleep 2
echo "[!!!] Removing systemd in 10 seconds! You have been warned!"
sleep 10

# scary....
pacman -Rdd --noconfirm systemd systemd-libs systemd-sysvcompat pacman-mirrorlist dbus
rm -f /etc/resolv.conf
cp -vf /etc/pacman.d/mirrorlist.artix /etc/pacman.d/mirrorlist
pacman -S --noconfirm dhcpcd dhcpcd-openrc
sleep 2

# attempt to start network and install base pkgs
echo 'nameserver 1.1.1.1' > /etc/resolv.conf
echo "Attempting to start internet"
dhcpcd -i enp0s1 # hardcoded lol
sleep 10
pacman -S --noconfirm base base-devel grub linux linux-headers mkinitcpio rsync lsb-release esysusers etmpfiles artix-branding-base openrc elogind-openrc openrc-system dhcpcd networkmanager dhcpcd-openrc
sleep 2

grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
sleep 2

# replace arch pkgs with artix ones
export LC_ALL=C
pacman -Sl system | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
pacman -Sl world  | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
pacman -Sl galaxy | grep installed | cut -d" " -f2 | pacman -S --noconfirm -
sleep 2

pacman -S --needed --noconfirm acpid-openrc alsa-utils-openrc cronie-openrc cups-openrc networkmanager networkmanager-openrc fuse-openrc haveged-openrc hdparm-openrc openssh-openrc samba-openrc syslog-ng-openrc

for svc in acpid alsasound cronie cupsd sddm fuse haveged hdparm smb sshd syslog-ng udev NetworkManager; do
  rc-update add "$svc" default
done

pacman -S --needed --noconfirm netifrc
echo 'GRUB_CMDLINE_LINUX="net.ifnames=0"' >> /etc/default/grub
ln -sf /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 boot
rc-update add udev sysinit boot

for usr in journal journal-gateway timesync network bus-proxy journal-remote journal-upload resolve coredump; do
  userdel "systemd-$usr" 2>/dev/null || true
done
rm -rf /etc/systemd /var/lib/systemd

sed -i '/init=\/usr\/lib\/systemd\/systemd/d' /etc/default/grub
sed -i '/x-systemd/d' /etc/fstab

mkinitcpio -P

echo "[!] Migrataion done"
echo "Also consider installing a desktop/DM"
sleep 2
