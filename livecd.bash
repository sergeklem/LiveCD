#!/bin/bash
#####################################################################
#
# Description
#
#####################################################################

### Constants #######################################################
THIS_SCRIPT_NAME=$(basename $0)
ARCH='amd64'
RELEASE=precise
## установка hostname
HOST='arm13'
## добавление пользователя
USER='user'
CRYPTPASS='$6$/C5kV2J.$9bjWQOTcmgRMt2YVk3w.hLg6wufE4yBI/ab4FmalCinbMSbTBzmNIbzA9gn9b38'
WORKDIR='/home/user/work'


### Implementation ##################################################
function main {
    validateUser
    updateOS
    disablePeriodicUpdates
    installSoftwarePackages
    liveCD
    backupScript
    exit 0
}

function validateUser {
    if [ "$(id -u)" != "0" ]; then
	echo "${THIS_SCRIPT_NAME}: This script must be run as root." 1>&2
	exit 1
    fi
}
function updateOS {
    log_msg "Updating the operating system..."
    #apt-get update &> /dev/null && apt-get dist-upgrade --yes &> /dev/null
    apt-get --yes update &> /dev/null
}

function disablePeriodicUpdates {
    log_msg "Disabling periodic operating system updates..."
    apt-get remove --yes update-manager-core &> /dev/null
    local file="/etc/apt/apt.conf.d/10periodic"
    sed -ri "s/(APT::Periodic::Update-Package-Lists\ *\")1\";/\10\";/" "${file}"
}

#--------------------------------------------------------------------
function installSoftwarePackages {
    log_msg "Install software packages"
    setupUsefulUtils
    setupDebootstrap
    setupPackagesLiveSystem
}

function setupUsefulUtils {
    log_msg "Installing utils like wget, nano, etc..."
    apt-get install --yes wget curl htop mc nano &> /dev/null
}

function setupDebootstrap {
    log_msg "Installing Debootstrap..."
    apt-get install --yes debootstrap &> /dev/null
}

function setupPackagesLiveSystem {
    log_msg "Install packages needed for Live System..."
    apt-get install --yes syslinux squashfs-tools genisoimage initramfs-tools &> /dev/null
}
    
function removeKernel {
    ls /boot/vmlinuz-3.5.**-**-generic > list.txt
    sum=$(cat list.txt | grep '[^ ]' | wc -l)
    if [ $sum -gt 1 ]; then
	dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs sudo apt-get -y purge
    fi
    rm list.txt
}


#--------------------------------------------------------------------
function liveCD {
    createCdDirectory 
    makeChRoot
    createPreseed
    bootScreen
    createManifest
    compressChRoot
    createDiskdefines
    recognitionLiveUbuntu
    calculateMD5
    createISO
}

function createCdDirectory {
    log_msg "Create the Cd Image Directory and Populate it"
    cd $WORKDIR
    if [ -d "$WORKDIR/image" ]; then
    rm -rf $WORKDIR/image/*
    fi
    log_msg "Creating folder tree"
    mkdir -p $WORKDIR/image/{casper,preseed,install,isolinux,.disk}
    mkdir -p $WORKDIR/chroot/{boot,etc,etc/apt}
    log_msg "Creating a new initial ramdisk for the live system"
    mkinitramfs -o /boot/initrd.img-`uname -r` `uname -r`
    log_msg "Copying your kernel and initrd for the livecd"
    cp /boot/vmlinuz-`uname -r` $WORKDIR/chroot/boot/vmlinuz-`uname -r`
    cp /boot/initrd.img-`uname -r` $WORKDIR/chroot/boot/initrd.img-`uname -r`
    cp $WORKDIR/chroot/boot/vmlinuz-`uname -r` $WORKDIR/image/casper/vmlinuz
    cp $WORKDIR/chroot/boot/initrd.img-`uname -r` $WORKDIR/image/casper/initrd.lz
    if [ ! -f $WORKDIR/image/casper/vmlinuz ]; then
	log_msg "Missing valid kernel. Exiting"
	exit 1
    fi
    if [ ! -f $WORKDIR/image/casper/initrd.lz ]; then
	log_msg "Missing valid initial ramdisk. Exiting"
	exit 1
    fi
    cp /boot/memtest86+.bin $WORKDIR/image/install/memtest
}

function makeChRoot {
    log_msg "Make the ChRoot Environment"
    cd $WORKDIR
    debootstrap --arch=$ARCH $RELEASE chroot
    #debootstrap --arch=amd64 precise chroot
    cp /etc/hosts chroot/etc/hosts
    cp /etc/resolv.conf chroot/etc/resolv.conf
    cp /etc/apt/sources.list chroot/etc/apt/sources.list
    log_msg "Create customization script and run it in chroot"
    #mount --bind /dev chroot/dev
    chroot chroot << EOFHERE

mount none -t proc /proc
mount none -t sysfs /sys
mount none -t devpts /dev/pts
export HOME=/root
export LC_ALL=C
#sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 12345678  #Substitute "12345678" with the PPA's OpenPGP ID.
#apt-get install --yes dbus
#dbus-uuidgen > /var/lib/dbus/machine-id
#dpkg-divert --local --rename --add /sbin/initctl
#ln -s /bin/true /sbin/initctl
apt-get --yes update &> /dev/null
apt-get --yes upgrade &> /dev/null

# install packages
apt-get install --yes ubuntu-standard casper lupin-casper &> /dev/null
apt-get install --yes discover laptop-detect os-prober &> /dev/null
apt-get install --yes xorg &> /dev/null
apt-get install --yes wget &> /dev/null
apt-get install --yes debian-installer-* kexec-tools
#apt-get install ubiquity-frontend-gtk
apt-get install --yes mc &> /dev/null
#wget https://www.dropbox.com/s/8hkywcyowir2jrh/arm__ubuntu_12.04.bash &> /dev/null
#bash ./arm__ubuntu_12.04.bash
#del arm__ubuntu_12.04.bash

# clean
echo "Cleanup the ChRoot Environment"

#rm /var/lib/dbus/machine-id
#rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl
apt-get clean
rm -rf /tmp/*
rm /etc/resolv.conf

# umount proc, sysfs, devpts
umount -lf /proc
umount -lf /sys
umount -lf /dev/pts

EOFHERE
#umount chroot/dev
}

function createPreseed {
    log_msg " Create Preseed Instruction"
    cat > $WORKDIR/image/preseed/oem.seed <<EOF2
# Locales
d-i debian-installer/locale string ru_RU.UTF-8

# Keyboard
d-i	localechooser/shortlist	select	RU
d-i console-setup/ask_detect boolean false
d-i console-setup/layoutcode string ru
d-i	console-setup/variant	select	Россия
d-i	console-setup/toggle	select	Alt+Shift

# Network
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string ubuntu
d-i netcfg/dhcp_failed note
d-i netcfg/dhcp_options select Do not configure the network at this time

# Clock
d-i clock-setup/utc boolean true
d-i time/zone string Europe/Moscow
d-i clock-setup/ntp boolean true

# Users
d-i passwd/root-login boolean true
d-i passwd/make-user boolean true
d-i passwd/root-password-crypted password $CRYPTPASS
d-i passwd/user-fullname string Ubuntu user
d-i passwd/username string $USER
d-i passwd/user-password-crypted password $CRYPTPASS
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false

# Partitioning
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
partman-auto partman-auto/init_automatically_partition select Guided - use entire disk
partman-auto partman-auto/automatically_partition select
d-i partman-auto/purge_lvm_from_device boolean true
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# GRUB
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true

# APT
d-i apt-setup/restricted boolean true
d-i apt-setup/universe boolean true
d-i apt-setup/multiverse boolean true
d-i apt-setup/non-free boolean true
d-i mirror/ftp/proxy string
d-i mirror/http/proxy string

# At last
d-i finish-install/reboot_in_progress note
EOF2
}



function bootScreen {
    log_msg "Boot Screen for the LiveCD"
    cd $WORKDIR/image/isolinux
    wget https://www.dropbox.com/s/5mkvy1s11x7qm88/vesamenu.c32 &> /dev/null
    cp /usr/lib/syslinux/isolinux.bin $WORKDIR/image/isolinux
    if [ ! -f $WORKDIR/image/isolinux/isolinux.bin ]; then
	log_msg "Missing valid isolinux.bin. Exiting"
	exit 1
    fi
    log_msg " Create Boot-loader Configuration"
    #Описание находится /usr/share/doc/syslinux/syslinux.txt.lz
    cat > $WORKDIR/image/isolinux/isolinux.cfg <<EOF3
default vesamenu.c32
prompt 0
timeout 100

menu title Custom Live CD
menu color title 1;37;44 #c0ffffff #00000000 std
label install
	menu label ^Install
	kernel /casper/vmlinuz
	append vga=788 initrd=/casper/initrd.lz -- quiet 
label live
  menu label ^Boot the Live System
  kernel /casper/vmlinuz
  append  file=/cdrom/preseed/custom.seed boot=casper initrd=/casper/initrd.lz quiet splash --
LABEL oem
  menu label ^Start or install Ubuntu
  kernel /casper/vmlinuz
  append  file=/cdrom/preseed/oem.seed boot=casper debian-installer/locale=ru_RU.UTF-8 console-setup/layoutcode=ru localechooser/translation/warn-light=true localechooser/translation/warn-severe=true console-setup/toggle=Alt+Shift initrd=/casper/initrd.lz quiet --
LABEL check
  menu label ^Check CD for defects
  kernel /casper/vmlinuz
  append  boot=casper integrity-check initrd=/casper/initrd.lz quiet splash --
LABEL memtest
  menu label ^Memory test
  kernel /install/memtest86+.bin
  append -
LABEL hd
  menu label ^Boot from first hard disk
  localboot 0x80
  append -

#prompt flag_val
# 
# If flag_val is 0, display the "boot:" prompt 
# only if the Shift or Alt key is pressed,
# or Caps Lock or Scroll lock is set (this is the default).
# If  flag_val is 1, always display the "boot:" prompt.
#  http://linux.die.net/man/1/syslinux   syslinux manpage 
EOF3
}

function createManifest {
    log_msg "Creating filesystem.manifest and filesystem.manifest-desktop"
    cd $WORKDIR
    chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' | tee image/casper/filesystem.manifest &> /dev/null
    cp -v image/casper/filesystem.manifest image/casper/filesystem.manifest-desktop
    REMOVE='ubiquity ubiquity-frontend-gtk ubiquity-frontend-kde casper lupin-casper live-initramfs user-setup discover1 xresprobe os-prober libdebian-installer4'
    for i in $REMOVE 
    do
	sed -i "/${i}/d" image/casper/filesystem.manifest-desktop
    done
}

function compressChRoot {
    if [ ! -d $WORKDIR/image/casper/filesystem.squashfs ]; then
	rm -rf $WORKDIR/image/casper/filesystem.squashfs
    fi
    log_msg "Compress the chroot"
    mksquashfs chroot image/casper/filesystem.squashfs 
    printf $(du -sx --block-size=1 chroot | cut -f1) > image/casper/filesystem.size
}

function createDiskdefines {
    log_msg "Create diskdefines"
    cat > $WORKDIR/image/README.diskdefines <<EOF4
#define DISKNAME  Ubuntu Remix
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  $ARCH
#define ARCH$ARCH  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF4
}

function recognitionLiveUbuntu {
    cd "${WORKDIR}"
    touch image/ubuntu
    cd image/.disk
    touch base_installable
    echo "full_cd/single" > cd_type
    echo "Ubuntu Remix" > info
    echo "http//your-release-notes-url.com" > release_notes_url
}

function calculateMD5 {
    cd $WORKDIR
    log_msg "Calculate MD5"
    (cd image && find . -type f -print0 | xargs -0 md5sum | grep -v "\./md5sum.txt" > md5sum.txt)
}

function createISO {
    log_msg "Create ISO Image for a LiveCD"
    cd $WORKDIR/image
    mkisofs -r -V "$IMAGE_NAME" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ../ubuntu-remix.iso .
    cd ..
}

function log_msg() {
    mdate="$(date +%d-%m-%Y\ %H:%M:%S) "
    if [ ! -d $WORKDIR ]; then
	mkdir $WORKDIR
    fi
    echo "$1"
    echo "$mdate$1" >> $WORKDIR/LiveCD.log
}

function backupScript {
    mkdir -p /home/user/scripts
    if [ ! -d /home/user/scripts/$(date +%d%m%Y) ]; then
	mkdir -p /home/user/scripts/$(date +%d%m%Y)
    fi
    cp /home/user/run.bash /home/user/scripts/$(date +%d%m%Y)/"$(date +%H:%M-%d%m%Y)"-livecd.bash
}

# Script's entry point: #############################################
main "$@"