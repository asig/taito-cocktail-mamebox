#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

SRC_IMAGE="/tmp/ubuntu-14.04.1-server-i386.iso"

if [ ! -f ${SRC_IMAGE} ]; then
	wget http://releases.ubuntu.com/14.04.1/ubuntu-14.04.1-server-i386.iso -O ${SRC_IMAGE}
fi

#
# Extract original iso
#
mkdir /tmp/iso-original
mkdir /tmp/iso-modified
sudo mount -o loop ${SRC_IMAGE} /tmp/iso-original
cp -rT /tmp/iso-original/ /tmp/iso-modified/

#
# Modify image to our liking
#
cd /tmp/iso-modified

# Prevent the language selection menu from appearing
echo en > isolinux/lang 

# Set up a kickstart config.
cat <<EOF > ks.cfg
# Load our own preseed
preseed preseed/file=/cdrom/ks.seed

# System language
lang en_US

# Language modules to install
langsupport en_US

# System keyboard
keyboard us

# System mouse
mouse

# System timezone
timezone Europe/Zurich

# Root password
rootpw --disabled

# Initial user (will have sudo so no need for root)
user arcade --fullname "Arcade Box" --password arcade

# Reboot after installation
reboot

# Use text mode install
text

# Install OS instead of upgrade
install

# Installation media
cdrom

# Ignore errors about unmounting current drive (happens if reinstalling)
# BUG: this just seems to default the selection to yes?
# Both without owner:
#preseed partman/unmount_active boolean true
# And with owner:
#preseed --owner partman-base partman/unmount_active boolean true
# When I run the debconf-get-selections --installer it shows the owner as unknown

# System bootloader configuration
bootloader --location=mbr

# Clear the Master Boot Record
zerombr yes

# Partition clearing information
clearpart --all --initlabel

#Disk partitioning information
part / --fstype ext4 --size 8192 --asprimary 
part /mame-data --fstype ext4 --size 20480 --asprimary 
part swap --size 3192 --grow --maxsize 4096 --asprimary 

# Don't install recommended items by default
preseed base-installer/install-recommends boolean false

# System authorization infomation
# The enablemd5 has to be there although it will still use salted sha256
auth  --useshadow  --enablemd5

# Network information
network --bootproto=dhcp --device=eth0

# Firewall configuration
firewall --disabled --trust=eth0 --ssh

# Policy for applying updates. May be "none" (no automatic updates),
# "unattended-upgrades" (install security updates automatically), or
# "landscape" (manage system with Landscape).
preseed pkgsel/update-policy select none

#X Window System configuration information
xconfig --depth=32 --resolution=800x600 --defaultdesktop=GNOME --startxonboot

# Additional packages to install
%packages
openssh-server

%post
#
# TODO: Install mamego
#

# Clean up
apt-get -qq -y autoremove
apt-get clean
rm -f /var/cache/apt/*cache.bin
rm -f /var/lib/apt/lists/*
EOF

# Add a preseed file, to suppress other questions
cat <<EOF > ks.preseed
d-i partman/confirm_write_new_label boolean true 
d-i partman/choose_partition  select Finish partitioning and write changes to disk 
d-i partman/confirm boolean true
EOF

# Finally, overwrite the install menu
cat <<EOF > isolinux/txt.cfg
default install
label install
  menu label ^Install Ubuntu Server
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz ks=cdrom:/ks.cfg --
EOF

#
# Create new image from modified files
#

cd ..
mkisofs -D -r -V "ARCADE_UBUNTU" -cache-inodes -J -l \
  -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o arcade-ubuntu-14-04-i386.iso /tmp/iso-modified

#
# Cleanup
#
#rm -rf /tmp/iso-original /tmp/iso-modified
