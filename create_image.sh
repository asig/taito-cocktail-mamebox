#!/bin/bash

# ---------------------------------------------------------------------------
#
# Simple script that takes an Ubuntu image and creates an install image 
# suited for a MameBox, including:
#  - customized plymouth splash screens
#  - arcade joystick drivers
#  - autologin to the "mamego" arcade frontend.
#
# Copyright (c) 2014 Andreas Signer <asigner@gmail.com>
#
# --------------------------------------------------------

# TODO:
# - Install joystick driver
# - Install mame
# - set up openssh server

#
# Figure out what directory we're in
#
BINARY=$(readlink -f $0)
cd $(dirname ${BINARY})
BINARY_DIR=$(pwd)

USER=arcade
PASSWORD=arcade

#
# Source image to use
#
SRC_IMAGE="/tmp/ubuntu-14.04.1-server-i386.iso"

function log() {
  echo "$@"
}

function usage() {
	echo "Usage: $0 [--orientation=horizontal|vertical] [--ssid=<ssid> --ssid_password=<password>] --hostname=<hostname> --frontend-pack=<path/to/frontendpack.tar.bz2> " >&2
	exit 1
}

function parse_command_line() {
	ORIENTATION=vertical
	FRONTEND_PACK=
	HOSTNAME=nohost
  SSID=
  SSID_PASSWORD=

	for i in "$@"; do
		case $i in
      --orientation=*)
        ORIENTATION="${i#*=}"
        shift
        ;;
      --frontend-pack=*)
        FRONTEND_PACK="${i#*=}"
        shift
        ;;
      --hostname=*)
        HOSTNAME="${i#*=}"
        shift
        ;;
      --ssid=*)
        SSID="${i#*=}"
        shift
        ;;
      --ssid_password=*)
        SSID_PASSWORD="${i#*=}"
        shift
        ;;
      *)
        usage
        ;;
		esac
	done

    if [[ "${ORIENTATION}" != "horizontal" && "${ORIENTATION}" != "vertical" ]]; then
    	usage
    fi

    if [ -z "${FRONTEND_PACK}" ]; then
    	usage
    fi
}


#
# Handle command line args and check for root
#
parse_command_line $@
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

log "Creating MameBox install image based on " ${SRC_IMAGE}

#
# Download the image if necessary
#
if [ ! -f ${SRC_IMAGE} ]; then
  URL=http://releases.ubuntu.com/14.04.1/ubuntu-14.04.1-server-i386.iso
  log "Base image not available, downloading from ${URL}..."
	wget -q ${URL} -O ${SRC_IMAGE}
fi

BASEDIR=$(mktemp -d)
ISOSRC_DIR=${BASEDIR}/iso-original
ISO_DIR=${BASEDIR}/iso-modified
STAGING_DIR=${BASEDIR}/staging

log "Base dir is ${BASEDIR}"

# ------------------------------------------------------------------------

#
# Extract original iso
#
log "Extracting base image..."
mkdir -p ${ISOSRC_DIR}
mkdir -p ${ISO_DIR}
mount -o loop ${SRC_IMAGE} ${ISOSRC_DIR}
cp -rT ${ISOSRC_DIR} ${ISO_DIR}
umount ${ISOSRC_DIR}
rm -rf ${ISOSRC_DIR}

# ------------------------------------------------------------------------

#
# Set up a staging dir containing all the additional stuff we need.
#
log "Setting up staging directory..."
mkdir -p ${STAGING_DIR}
# Plymouth
mkdir -p ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo
cp ${BINARY_DIR}/resources/plymouth/mamebox-logo/* ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo
if [[ "${ORIENTATION}" == "horizontal" ]]; then
	mv ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/logo-horizontal.png ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/logo.png
	rm ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/logo-vertical.png
else
	rm ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/logo-horizontal.png
	mv ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/logo-vertical.png ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/logo.png
fi
# Desktop Session
mkdir -p ${STAGING_DIR}/usr/share/xsessions
cat <<EOF > ${STAGING_DIR}/usr/share/xsessions/arcade.desktop
[Desktop Entry]
Name=Arcade
Exec=/home/${USER}/mamego/run.sh
Icon=
Type=Application
EOF

mkdir -p ${STAGING_DIR}/home/${USER}
cat <<EOF > ${STAGING_DIR}/home/${USER}/.dmrc
[Desktop]
Session=arcade
EOF

mkdir -p ${STAGING_DIR}/etc/lightdm/
cat <<EOF > ${STAGING_DIR}/etc/lightdm/lightdm.conf
[SeatDefaults]
autologin-user=${USER}
autologin-session=lightdm-autologin # This seems to be important, but I couldn't find documentation...
user-session=arcade
EOF

# ------------------------------------------------------------------------

#
# Modify image to our liking
#
log "Setting up install scripts..."
cd ${ISO_DIR}

mkdir -p mamebox
tar cfj mamebox/data.tar.bz2 -C ${STAGING_DIR} .
cp ${BINARY_DIR}/${FRONTEND_PACK} mamebox/frontend.tar.bz2

echo en > isolinux/lang  # Prevent the language selection menu from appearing

#
# Set up a kickstart config.
#
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
user ${USER} --fullname "Arcade Box" --password ${PASSWORD}

# Reboot after installation
reboot

# Use text mode install
text

# Install OS instead of upgrade
install

# Installation media. Use both CD-ROM and Net
cdrom
url --url http://archive.ubuntu.com/ubuntu

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
network --bootproto=dhcp --device=eth0 --hostname ${HOSTNAME}

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
@core
ubuntu-desktop
libsdl-image1.2
libsdl-mixer1.2
libsdl-ttf2.0
openssh-server

%post
# copy additional config and frontend
cd /
tar xfj /media/cdrom/mamebox/data.tar.bz2
mkdir -p /home/${USER}/mamego
tar xfj /media/cdrom/mamebox/frontend.tar.bz2 -C /home/${USER}/mamego

# make our plymouth theme default
cd /lib/plymouth/themes
rm default.grub default.plymouth 
ln -s /lib/plymouth/themes/mamebox-logo/mamebox-logo.plymouth default.plymouth
ln -s /lib/plymouth/themes/mamebox-logo/mamebox-logo.grub default.grub

# Setup wlan0 if there is owner
if [ ! -z "${SSID}"]; then
  cat <<EOF2 >> /etc/network/interfaces
auto wlan0
iface wlan0 inet dhcp
    wpa-ssid ${SSID}
    wpa-psk ${SSID_PASSWORD}
EOF2
fi

# Make sure arcade's files belong to himself
chown -R ${USER}:${USER} /home/${USER}

# Clean up
apt-get -qq -y autoremove
apt-get clean
rm -f /var/cache/apt/*cache.bin
rm -f /var/lib/apt/lists/*
EOF

#
# Add a preseed file, to suppress other questions
#
cat <<EOF > ks.preseed
d-i partman/confirm_write_new_label boolean true 
d-i partman/choose_partition  select Finish partitioning and write changes to disk 
d-i partman/confirm boolean true

# The installer will warn about weak passwords. If you are sure you know
# what you're doing and want to override it, uncomment this.
d-i user-setup/allow-password-weak boolean true

### Apt setup
# You can choose to install restricted and universe software, or to install
# software from the backports repository.
d-i apt-setup/restricted boolean true
d-i apt-setup/universe boolean true
#d-i apt-setup/backports boolean true
# Uncomment this if you don't want to use a network mirror.
#d-i apt-setup/use_mirror boolean false
# Select which update services to use; define the mirrors to be used.
# Values shown below are the normal defaults.
#d-i apt-setup/services-select multiselect security
#d-i apt-setup/security_host string security.ubuntu.com
#d-i apt-setup/security_path string /ubuntu
EOF

#
# Don't wait (or more correct, wait 1/10th of a second) for the user to select "Install server"
#
sed -i 's/^timeout 0$/timeout 1/g' isolinux/isolinux.cfg

#
# Finally, overwrite the install menu
#
cat <<EOF > isolinux/txt.cfg
default install
label install
  menu label ^Install Ubuntu Server
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz ks=cdrom:/ks.cfg preseed/file=/cdrom/ks.preseed --
EOF

# ------------------------------------------------------------------------

#
# Create new image from modified files
#
log "Creating install image..."
TARGET_ISO=/tmp/${HOSTNAME}-arcade-ubuntu-14-04-i386.iso
cd ..
mkisofs -quiet -D -r -V "ARCADE_UBUNTU" -cache-inodes -J -l \
  -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o ${TARGET_ISO} ${ISO_DIR}

log "MameBox image created at: ${TARGET_ISO}"

#
# Cleanup
#
rm -rf ${BASEDIR}
