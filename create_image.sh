#!/bin/bash

#
# Source image to use
#
SRC_IMAGE="/tmp/ubuntu-14.04.1-server-i386.iso"

function usage() {
	echo "Usage: $0 [horizontal|vertical]" >&2
	exit 1
}

function parse_command_line() {
	ORIENTATION=vertical
	if [[ $# > 1 ]]; then
		usage
    elif [[ $# > 0 ]]; then
    	ORIENTATION=$1
    fi
    if [[ "${ORIENTATION}" != "horizontal" && "${ORIENTATION}" != "vertical" ]]; then
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

#
# Download the image if necessary
#
if [ ! -f ${SRC_IMAGE} ]; then
	wget http://releases.ubuntu.com/14.04.1/ubuntu-14.04.1-server-i386.iso -O ${SRC_IMAGE}
fi

#
# Extract original iso
#
rm -rf /tmp/iso-original /tmp/iso-modified 2> /dev/null
mkdir /tmp/iso-original
mkdir /tmp/iso-modified
mount -o loop ${SRC_IMAGE} /tmp/iso-original
cp -rT /tmp/iso-original/ /tmp/iso-modified/
umount /tmp/iso-original
rm -rf /tmp/iso-original

#
# Modify image to our liking
#
cd /tmp/iso-modified

# Prevent the language selection menu from appearing
echo en > isolinux/lang 

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
user arcade --fullname "Arcade Box" --password arcade

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
ubuntu-desktop

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
rm -rf /tmp/iso-modified
