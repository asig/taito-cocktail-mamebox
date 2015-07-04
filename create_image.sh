#!/bin/bash

# ---------------------------------------------------------------------------
#
# Simple script that takes an Ubuntu image and creates an install image 
# suited for a MameBox, including:
#  - customized plymouth splash screens
#  - arcade joystick drivers
#  - autologin to the "mamego" arcade frontend.
#
# Copyright (c) 2015 Andreas Signer <asigner@gmail.com>
#
# --------------------------------------------------------

# TODO:
# - Install joystick driver (flag protected)

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
	echo "Usage: $0 [--rotation=0|90|180|270] [--wlan_ssid=<ssid> --wlan_password=<password>] [--hostname=<hostname>] [--mame=<path/to/mame>] --frontend-pack=<path/to/frontendpack.tar.bz2> [--data-pack=<path/to/data-pack.tar.bz2>]" >&2
	exit 1
}

function parse_command_line() {
  ROTATION=0
  FRONTEND_PACK=
  DATA_PACK=
  HOSTNAME=nohost
  WLAN_SSID=
  WLAN_PASSWORD=
  MAME=

  for i in "$@"; do
    case $i in
      --rotation=*)
        ROTATION="${i#*=}"
        shift
        ;;
      --frontend-pack=*)
        FRONTEND_PACK="${i#*=}"
        shift
        ;;
      --data-pack=*)
        DATA_PACK="${i#*=}"
        shift
        ;;
      --hostname=*)
        HOSTNAME="${i#*=}"
        shift
        ;;
      --wlan_ssid=*)
        WLAN_SSID="${i#*=}"
        shift
        ;;
      --wlan_password=*)
        WLAN_PASSWORD="${i#*=}"
        shift
        ;;
      --mame=*)
        MAME="${i#*=}"
        shift
        ;;
      *)
        usage
        ;;
		esac
	done

    if [[ "${ROTATION}" != "0" && "${ROTATION}" != "90" && "${ROTATION}" != "180" && "${ROTATION}" != "270" ]]; then
    	usage
    fi

    if [ -z "${FRONTEND_PACK}" ]; then
    	usage
    fi
    if [ ! -f ${FRONTEND_PACK} ]; then
      log "${FRONTEND_PACK} is not a valid file"
      usage
    fi

    if [ ! -z ${DATA_PACK} -a ! -f ${DATA_PACK} ]; then
      log "${DATA_PACK} is not a valid file"
      usage
    fi

    if [ ! -z "${MAME}" ]; then
      if [ ! -f ${MAME} ]; then
        log "${MAME} is not a valid file"
        usage
      fi
    fi

}


#
# Handle command line args and check for root
#
parse_command_line $@
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1
fi

log "Creating MameBox install image based on " ${SRC_IMAGE}

#
# Download the image if necessary
#
if [ ! -f ${SRC_IMAGE} ]; then
  URL=http://old-releases.ubuntu.com/releases/14.04.1/ubuntu-14.04.1-server-i386.iso
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
cp ${BINARY_DIR}/resources/plymouth/mamebox-logo/mamebox-logo* ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/
cp ${BINARY_DIR}/resources/plymouth/mamebox-logo/logo-${ROTATION}.png ${STAGING_DIR}/lib/plymouth/themes/mamebox-logo/logo.png

# Creating mamego Desktop Session
mkdir -p ${STAGING_DIR}/usr/share/xsessions
cat <<EOF > ${STAGING_DIR}/usr/share/xsessions/arcade.desktop
[Desktop Entry]
Name=Arcade
Exec=/home/${USER}/mamego/run.sh
Icon=
Type=Application
EOF

# Configuring auto login
mkdir -p ${STAGING_DIR}/etc/lightdm/
cat <<EOF > ${STAGING_DIR}/etc/lightdm/lightdm.conf
[SeatDefaults]
autologin-user=${USER}
autologin-session=lightdm-autologin # This seems to be important, but I couldn't find documentation...
user-session=arcade
display-setup-script=/home/${USER}/screen-init.sh # It seems that some systems forget that we need 800x600, so we add our own script to ensure this.
EOF

# Display setup script
mkdir -p ${STAGING_DIR}/home/${USER}
cat <<EOF > ${STAGING_DIR}/home/${USER}/screen-init.sh
xrandr --output VGA1 --mode 800x600 2> /var/log/screen-init.ERR
EOF
chmod a+rx ${STAGING_DIR}/home/${USER}/screen-init.sh

# VERSION file 
mkdir -p ${STAGING_DIR}/home/${USER}
cat <<EOF > ${STAGING_DIR}/home/${USER}/VERSION
MameBox Ubuntu, based on $(basename ${SRC_IMAGE}).
Install image created on $(date).
EOF

# blacklist mei_me, just in we're running on the Optiplex 755 cocktail table.
# See also https://bbs.archlinux.org/viewtopic.php?id=168403
mkdir -p ${STAGING_DIR}/etc/modprobe.d/
cat <<EOF > ${STAGING_DIR}/etc/modprobe.d/blacklist-mei.conf
blacklist mei_me
EOF

# Configure GRUB to not wait for OS selection, and add the "quiet" and "splash" command line args, and set the resolution to 800x600
mkdir -p ${STAGING_DIR}/etc/default
cat <<EOF > ${STAGING_DIR}/etc/default/grub
GRUB_DEFAULT=0
GRUB_HIDDEN_TIMEOUT=0
GRUB_HIDDEN_TIMEOUT_QUIET=true
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash vga=0x315"
GRUB_CMDLINE_LINUX=""
GRUB_GFXMODE=800x600
EOF

# User settings
# Choosing default session. Really necessary?
mkdir -p ${STAGING_DIR}/home/${USER}
cat <<EOF > ${STAGING_DIR}/home/${USER}/.dmrc
[Desktop]
Session=arcade
EOF
# Create arcade's authorized_keys
mkdir -p ${STAGING_DIR}/home/${USER}/.ssh
cat <<EOF > ${STAGING_DIR}/home/${USER}/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAEAQDa1broGfjiZBAOU3pFsyEbCn1//S5axUc8a0veQPX38CglqNn2PZrYg4/f/ub3EHgc0Vdi8kb4mxJEpfhBtzYsckzqK0PMAwkYZVrFVpu3JpETGcCJT5rIU9eiwDgs1zrb6C1lk1xSrtW1lfdlIiz9jeZ7gj0DiaFX+rvNNB7NB0s+PapUWN4xTP5FQI2lm4nA3tI8D2M6FETlEtnwJatzG4eqEyIojaaEoAFFOOZ4ydN4w75bXcximxZZ4P1F0o4tQhiba9xLb021JgLxZ6E4ZIP3SGuZ7FlKGB6koN8IJThV/O8q07q4Gg1ueA/pCEO3DPynclFsVs0hM6rZQ/s29mhD8wv0+kpP744LkIoZGech1pYq2x2CNZp51f95HRA3HtIIDSdADHQ9q8DCFZXgg7x318PW3eHBtrzxCKXlJApYPvrGwgHQKgOx1Qg1MWV25mx0/JoeEtGfvKDWnDGo2afc3VoeXxpZ5lJIR61/fOxxptOUzxe8Vqr1gDQfbUqWo+OvT1Rocr27/HZ1Lk4C5UjgFYVl2Qb2Kk8CxUFwmCNkPn4qhMNWA3OL2tH5vJAx+mFxfCEfeyFLtas74jCEa+B03Zt/Ar65tCrnTiEWEuokpj4uGYNU+5MfnWiPV8oYdYvUd74Hl0UJvV1yXRohXqehR1znbwTe7p9H0JrRj0ws8le2sXSBHuNoUIlYltO8/F4G0GObnwt7n6kmvMWAsTRERae2Z19xpUNoIksOMkWXAV2twHv6C2CtLhkkpX/tmRAeHrUjoA5QYE9G0vJx8/3+zs4LTBN+JNyANucrlFpsPnRC55KGaJvsbpnCJ9oly0YRaF7/nDR4924MEFwfjo5AHY+pO+xoZguw/Vo7fK1cRJdup7tufwutrvT4oJIKLDxjH9Wuceg5UYkL2VrfnbGAklxQIwGLudMDUovi1fHBRb4Y46hBaEk43N/qqZrvtQWJpyXorz3LtYErXaPqquvS3+Ml+mRV9etIdXY4U6F9C6dq43o57GJU5wANFLg05eVSP/qrQsI6tXm95hAOlpwAc5jW77CF5cVWLA3jklQIROZ5D/NyZnTOwte99qBQ0tCTK9JapSzwia/S85kitX7JlCv7XvntxZ6G81mZatg/cQjS09N3+5hTmLIKC3IFnZBtUgTPPZyk+td/esU3rA5H7GD0nznkVFU8PcjsozEvjlJjair9yzDvVdFPKVFEqiOd9nVqCkpQxuozyQXxp3Rjz3feTMyuvEZCbBjgZkovaL6Oj2GV4zF3X7Ob3pXX+nV5WXy7lf+Pn2GD17dw3hV2by4+pNIFWLTgfsHobveKYBjPSokK9HIOb98Y8oukeONpoDcrVSHWpgD9tzMN asigner@bilbo
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAEAQDKrRBlNVyjCaUQwaDvZYgNkFPxgrt4YSsGcr95OGarAB9wd5VfE2lqtcYdCbZQDVyKiihlQrTvQVh9zOau8r3+guTf+TDzMEFS0D+npnxrROI1MdUloOUuroAvSwlMXqmrjhmuO4y/uc6U0LB6/sw4LtTiSbUfknwW875RkoomBTj9WTQRR5XgoboYGIBbsqNgVNFXNaQNq0lTxBRwaIGg/TikAkutz0npifLqXoSM0s6AW+TSyFsIXKV74KkT65cCfirNeIKDX58GmqLAoCelAn2WdHVHjkucLgQ+KtxtyADvnOESIDWLMIugRLNkBMUlhRymkzTDSZGklZhRz9PhgDAFvtKm8rIweaC9E08S4ZXQ4KF5wdI1OC8T//ksD6ZUWW1yPc1jISJ8xrdgo54SVXzYNrM+47sipm7dZ2JyJE+2hpp2iQQD2rxTCFDi984cuDPNT/XAN47pUA2eZAX5GixrumRABIaBdd+NdRymOz8ZheJje5IoIxynR4uxZBRHlpkrXoG5RoCUSWgdi2OmRfOCEskOK0ZE958d5hTX+IxsNc9IwQLOYnCFOtOMpVyr/xwiAsd4GE909fBe2w8E0JZBeF3opBDknbBxphpcNOh0lkPAOmftnm99YWhFGWs4af7DMOFr3Kj+06e9Q8S3JotGyc2aJ/VTo6gFCf5PSB4xOYeneAx9b7jgVXZZpifRISQqFcS188wugT4llqwemKQ/2LImJg6E5nuHAwWZCG0rSVRUJ4uFUXck6ol9Wogv12hcU3YWra5Z+GnjFPWO7iqiw6vmpK5skJm+kbPdqh64F5yx9p+hu4MkKDFnQ6y9OF5nYnSB2/LpLNLbn5Ro5I4SxLXaxN72afUJxmobC6SN9Y0SXnH3+MIO4TacUKqZj72r0+4eHfQPuKHU11fI7uxp52zhX0ku01jYT++cHgodCyuxiYJp07YV2DmeuroUQTJwpUs2dCF7ud2QhpeT4cfXBQOzfKbLbD34sKENnf6KXoO8Q2Sia7mnCDq2K0hwJJqmjmigj+QxvkFptWJ1G0uF5npmn5yZzgyLfJcgd5pxO14Sqlwra0TgR4lWJSgrnaPcQi4Ypuzke+vTNB0uSpMHOIVK2sx9wu6HVufkUpJj7EMcUX0+fV0kzL6bv/3xyPdIW4Ux+GpEo1yQsHx6qJRjpjcwRKkz/Fs6xGj1CSsV5ZO5TC0qHRYFaR+PBOj2COYCIsYSWOpQ5/4MX6Tt/2+uMWykzARb+L/uNHdrg692CJ/WN1vYFa18xrLSeSyOcMeiRJDZEAMooedEYLg9rWBE/uzHjEKBshv0nwyU0c+2BxITXp8UvmYCquHCIbrpXqq7YAQqw3c7/f/eKiGR asigner@ubuntu-vm
EOF

# Frontend pack and mame
mkdir -p ${STAGING_DIR}/home/${USER}/mamego
log "Unpacking frontend pack..."
tar xf ${BINARY_DIR}/${FRONTEND_PACK} -C ${STAGING_DIR}/home/${USER}/mamego

if [ -f ${BINARY_DIR}/${DATA_PACK} ]; then
  log "Unpacking data pack..."
  tar xf ${BINARY_DIR}/${DATA_PACK} -C ${STAGING_DIR}
fi

if [ ! -z "${MAME}" ]; then
  log "Copying mame..."
  cp ${MAME} ${STAGING_DIR}/home/${USER}/mamego
fi

# ------------------------------------------------------------------------

#
# Modify image to our liking
#
log "Setting up install scripts..."

# Pack staging directory to data.tar.bz2
mkdir -p ${ISO_DIR}/mamebox
tar cfj ${ISO_DIR}/mamebox/data.tar.bz2 -C ${STAGING_DIR} .

echo en > ${ISO_DIR}/isolinux/lang  # Prevent the language selection menu from appearing

#
# Set up a kickstart config.
#
cat <<EOF > ${ISO_DIR}/ks.cfg

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

# The installer will warn about weak passwords. If you are sure you know
# what you're doing and want to override it, uncomment this.
preseed user-setup/allow-password-weak boolean true

# Reboot after installation
#reboot

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

# Disk partitioning information
# This assumes at least a 30G disk and will fail
# if the disk is too small.
part / --fstype ext4 --size 24576 --asprimary 
part swap --size 3192 --grow --maxsize 4096 --asprimary 

# Additional partman config
preseed partman/confirm_write_new_label boolean true 
preseed partman/choose_partition  select Finish partitioning and write changes to disk 
preseed partman/confirm boolean true
# Prevent partman from asking whether mounted partitions should be unmounted. See also
# http://matelakat.blogspot.ch/2014/05/ubuntu-installer-unmount-partitions.html
preseed preseed/early_command string umount /media || true 

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

### Apt setup
# You can choose to install restricted and universe software, or to install
# software from the backports repository.
preseed apt-setup/restricted boolean true
preseed apt-setup/universe boolean true
#preseed apt-setup/backports boolean true
# Uncomment this if you don't want to use a network mirror.
#preseed apt-setup/use_mirror boolean false
# Select which update services to use; define the mirrors to be used.
# Values shown below are the normal defaults.
#preseed apt-setup/services-select multiselect security
#preseed apt-setup/security_host string security.ubuntu.com
#preseed apt-setup/security_path string /ubuntu


# Additional packages to install
%packages
@core
ubuntu-desktop
openssh-server
# unity-lens-applications is a recommendation that we actually want
unity-lens-applications
# for mame <= 0.152
libsdl-image1.2
libsdl-mixer1.2
libsdl-ttf2.0
# for newer mame
libsdl2-2.0.0
libsdl2-ttf-2.0.0

%post
# copy additional config and frontend
cd /
tar xfj /media/cdrom/mamebox/data.tar.bz2

# Update grub because we (might have) messed with its config
/usr/sbin/update-grub

# make our plymouth theme default
cd /lib/plymouth/themes
rm default.grub default.plymouth 
ln -s /lib/plymouth/themes/mamebox-logo/mamebox-logo.plymouth default.plymouth
ln -s /lib/plymouth/themes/mamebox-logo/mamebox-logo.grub default.grub

# Overwrite existing network config to make sure eth0 is allow-hotplug
# Write it to a separate file (due to https://bugs.launchpad.net/ubuntu/+source/netcfg/+bug/1361902)
# and copy it to /etc/network/interfaces during first startup
cat <<EOF2 > /etc/network/interfaces.TO_BE_INSTALLED
auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet dhcp
EOF2

# Setup wlan0 if there is one
if [ ! -z "${WLAN_SSID}" ]; then
  cat <<EOF2 >> /etc/network/interfaces.TO_BE_INSTALLED

allow-hotplug wlan0
iface wlan0 inet dhcp
    wpa-ssid ${WLAN_SSID}
    wpa-psk ${WLAN_PASSWORD}
EOF2
fi

# Setup script that runs on first boot, copies over new network config,
# and deletes itself afterwards
cat <<EOF2 > /etc/rc2.d/S00fix_network
#!/bin/bash
mv /etc/network/interfaces.TO_BE_INSTALLED /etc/network/interfaces
rm /etc/rc2.d/S00fix_network
EOF2
chmod a+x /etc/rc2.d/S00fix_network

# Make sure arcade's files belong to himself
chown -R ${USER}:${USER} /home/${USER}
chown -R ${USER}:${USER} /mame-data

# Clean up
apt-get -qq -y autoremove
apt-get clean
rm -f /var/cache/apt/*cache.bin
rm -f /var/lib/apt/lists/*
EOF

#
# Don't wait (or more correct, wait 1/10th of a second) for the user to select "Install server"
#
sed -i 's/^timeout 0$/timeout 1/g' ${ISO_DIR}/isolinux/isolinux.cfg

#
# Finally, overwrite the install menu
#
cat <<EOF > ${ISO_DIR}/isolinux/txt.cfg
default install
label install
  menu label ^Install Ubuntu Server
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz ks=cdrom:/ks.cfg --
EOF

# ------------------------------------------------------------------------

#
# Create new image from modified files
#
log "Creating install image..."
TARGET_ISO=/tmp/${HOSTNAME}-arcade-ubuntu-14-04-i386.iso
pushd ${ISO_DIR}/..
mkisofs -quiet -D -r -V "ARCADE_UBUNTU" -cache-inodes -J -l \
  -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o ${TARGET_ISO} ${ISO_DIR}
popd

log "MameBox image created at: ${TARGET_ISO}"

#
# Cleanup
#
rm -rf ${BASEDIR}
