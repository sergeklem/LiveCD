#!/bin/bash
################################################################################
#
# Description
#
################################################################################

### Constants ##################################################################
THIS_SCRIPT_NAME="$(basename $0)"
ARCH="amd64"
RELEASE="precise"
HOST="arm13"
USER="user"
PASSWORD="user"
WORKDIR="/home/user/work/"
DIR_BUILD="/home/user/work/"
CUSTOMIMAGE="LiveCD_12.04-amd64.iso"


### Implementation #############################################################
function main {
  validateUser
  updateOS
  disablePeriodicUpdates
  installSoftwarePackages
  createLiveCD
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
  #apt-get update >/dev/null 2>&1 && apt-get dist-upgrade --yes >/dev/null 2>&1
  apt-get --yes update >/dev/null 2>&1
}

function disablePeriodicUpdates {
  log_msg "Disabling periodic operating system updates..."
  apt-get remove --yes update-manager-core >/dev/null 2>&1
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
  apt-get install --yes wget curl htop mc nano >/dev/null 2>&1
}

function setupDebootstrap {
  log_msg "Installing Debootstrap..."
  apt-get install --yes debootstrap >/dev/null 2>&1
}

function setupPackagesLiveSystem {
  log_msg "Install packages needed for Live System..."
  apt-get install --yes syslinux squashfs-tools genisoimage                    \
      initramfs-tools >/dev/null 2>&1
}

function removeKernel {
  ls /boot/vmlinuz-3.5.**-**-generic > list.txt
  sum=$(cat list.txt | grep '[^ ]' | wc -l)
  if [ $sum -gt 1 ]; then
    dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r |                           \
        sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | \
        xargs sudo apt-get -y purge
  fi
  rm list.txt
}


#-------------------------------------------------------------------------------
function createLiveCD {
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
  cd ${WORKDIR}
  if [ -d "${WORKDIR}/image" ]; then
  rm -rf "${WORKDIR}image/*"
  fi
  log_msg "Creating folder tree"
  mkdir -p "${WORKDIR}image/{casper,preseed,install,isolinux,.disk}"
  mkdir -p "${WORKDIR}chroot/{boot,etc,etc/apt}"
  log_msg "Creating a new initial ramdisk for the live system"
  mkinitramfs -o "/boot/initrd.img-`uname -r`" "`uname -r`"
  log_msg "Copying your kernel and initrd for the livecd"
  cp "/boot/vmlinuz-`uname -r`" "${WORKDIR}chroot/boot/vmlinuz-`uname -r`"
  cp "/boot/initrd.img-`uname -r`" "${WORKDIR}chroot/boot/initrd.img-`uname -r`"
  cp "${WORKDIR}chroot/boot/vmlinuz-`uname -r`" "${WORKDIR}image/casper/vmlinuz"
  cp "${WORKDIR}chroot/boot/initrd.img-`uname -r`"                             \
      "${WORKDIR}image/casper/initrd.lz"
  if [ ! -f "${WORKDIR}image/casper/vmlinuz" ]; then
    log_msg "Missing valid kernel. Exiting"
    exit 1
  fi
  if [ ! -f "${WORKDIR}image/casper/initrd.lz" ]; then
    log_msg "Missing valid initial ramdisk. Exiting"
    exit 1
  fi
  cp "/boot/memtest86+.bin" "${WORKDIR}image/install/memtest"
}

function makeChRoot {
  log_msg "Make the ChRoot Environment"
  debootstrap --arch="${ARCH}" "${RELEASE}" "${WORKDIR}chroot"
  #debootstrap --arch=amd64 precise chroot
  cp /etc/hosts "${WORKDIR}chroot/etc/hosts"
  cp /etc/resolv.conf "${WORKDIR}chroot/etc/resolv.conf"
  cp /etc/apt/sources.list "${WORKDIR}chroot/etc/apt/sources.list"
  log_msg "Create customization script and run it in chroot"
  #mount --bind /dev chroot/dev
  cat > "${WORKDIR}chroot/tmp/customize.bash" <<EOFmakeChRoot
#!/bin/bash
mount none -t proc /proc
mount none -t sysfs /sys
mount none -t devpts /dev/pts
export HOME=/root
export LC_ALL=C
apt-get --yes update >/dev/null 2>&1
apt-get --yes upgrade >/dev/null 2>&1

echo  "# install packages"
apt-get install --yes ubuntu-standard casper lupin-casper >/dev/null 2>&1
. /etc/bash_completion
apt-get install --yes discover laptop-detect os-prober >/dev/null 2>&1
apt-get install --yes xorg >/dev/null 2>&1
apt-get install --yes wget >/dev/null 2>&1
apt-get install --yes update-notifier
apt-get install --yes debian-installer-*
#log_msg "Making sure popularity contest is not installed"
#apt-get -y -q remove popularity-contest >/dev/null 2>&1
#apt-get install ubiquity-frontend-gtk
apt-get install --yes mc >/dev/null 2>&1
sudo apt-get install language-pack-ru-base language-pack-ru
#wget https://www.dropbox.com/s/8hkywcyowir2jrh/arm__ubuntu_12.04.bash >/dev/null 2>&1
#bash ./arm__ubuntu_12.04.bash
#del arm__ubuntu_12.04.bash

# clean
echo "Cleanup the ChRoot Environment"

rm /var/lib/dbus/machine-id
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl
apt-get clean
rm -rf /tmp/*
rm /etc/resolv.conf

# umount proc, sysfs, devpts
umount -lf /proc
umount -lf /sys
umount -lf /dev/pts

exit
EOFmakeChRoot

chmod +x "${WORKDIR}chroot/tmp/customize.bash"
chroot "${WORKDIR}chroot" bash "/tmp/customize.bash"
#umount chroot/dev
}

function createPreseed {
  log_msg " Create Preseed Instruction"
  apt-get install --yes whois >/dev/null 2>&1
  local cryptpassword="$(mkpasswd "${PASSWORD}")"
  cat > "${WORKDIR}image/preseed/oem.seed" <<EOFcreatePreseed
d-i debian-installer/locale string ru_RU.UTF-8
# Keyboard
d-i debian-installer/language string ru
d-i debian-installer/country string RU
d-i localechooser/shortlist select RU
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/layoutcode string ru
d-i keyboard-configuration/variant select Русская
d-i keyboard-configuration/toggle select Alt+Shift

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
d-i passwd/root-password-crypted password "${cryptpassword}"
d-i passwd/user-fullname string "${USER}"
d-i passwd/username string "${USER}"
d-i passwd/user-password-crypted password "${cryptpassword}"
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false

# Partitioning
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
d-i partman-auto/expert_recipe string                                          \
     boot-root ::                                                              \
             512 50000 512 ext4                                                \
                     $primary{ } $bootable{ }                                  \
                     method{ format } format{ }                                \
                     use_filesystem{ } filesystem{ ext4 }                      \
                     mountpoint{ /boot }                                       \
             .                                                                 \
             7000 10000 90000 ext4                                             \
                     method{ format } format{ }                                \
                     use_filesystem{ } filesystem{ ext4 }                      \
                     mountpoint{ / }                                           \
             .                                                                 \
             5000 10000 10000 ext4                                             \
                     method{ format } format{ }                                \
                     use_filesystem{ } filesystem{ ext4 }                      \
                     mountpoint{ /var }                                        \
             .                                                                 \
             500 10000 1000000000 ext4                                         \
                     method{ format } format{ }                                \
                     use_filesystem{ } filesystem{ ext4 }                      \
                     mountpoint{ /srv }                                        \
             .                                                                 \
             64 51200 300% linux-swap                                          \
                     method{ swap } format{ }                                  \
             .
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

pkgsel pkgsel/update-policy select none

# At last
d-i finish-install/reboot_in_progress note

tasksel tasksel/first multiselect ubuntu-server
EOFcreatePreseed
}



function bootScreen {
  log_msg "Boot Screen for the LiveCD"
  cd "${WORKDIR}image/isolinux"
  local dir_bootScreen="${WORKDIR}image/isolinux/"
  wget "https://www.dropbox.com/s/5mkvy1s11x7qm88/vesamenu.c32" -O             \
      "${dir_bootScreen}/vesamenu.c32" >/dev/null 2>&1
  cp "/usr/lib/syslinux/isolinux.bin" "${dir_bootScreen}"
  if [ ! -f "${dir_bootScreen}isolinux.bin" ]; then
    log_msg "Missing valid isolinux.bin. Exiting"
    exit 1
  fi
  log_msg " Create Boot-loader Configuration"
  #Описание находится /usr/share/doc/syslinux/syslinux.txt.lz
  cat > "${dir_bootScreen}isolinux.cfg" <<EOF3
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
  local dir_manifest="${WORKDIR}image/casper/"
  chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' |         \
      tee "${dir_manifest}filesystem.manifest" >/dev/null 2>&1
  cp -v "${dir_manifest}filesystem.manifest"                                   \
      "${dir_manifest}filesystem.manifest-desktop"
  REMOVE="ubiquity ubiquity-frontend-gtk ubiquity-frontend-kde casper          \
          lupin-casper live-initramfs user-setup discover1 xresprobe os-prober \
          libdebian-installer4"
  for i in "${REMOVE}"; do
    sed -i "/${i}/d" "${dir_manifest}filesystem.manifest-desktop"
  done
}

function compressChRoot {
  local dir_compressChroot="${WORKDIR}image/casper/"
  if [ ! -d "${dir_compressChroot}filesystem.squashfs" ]; then
    rm -rf "${dir_compressChroot}filesystem.squashfs"
  fi
  log_msg "Compress the chroot"
  mksquashfs chroot "${dir_compressChroot}filesystem.squashfs"
  printf $(du -sx --block-size=1 chroot | cut -f1) >                           \
      "${dir_compressChroot}filesystem.size"
}

function createDiskdefines {
  log_msg "Create diskdefines"
  cat > "${WORKDIR}image/README.diskdefines" <<EOFcreateDiskdefines
#define DISKNAME  Ubuntu Remix
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  "${ARCH}"
#define ARCH"${ARCH}"  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOFcreateDiskdefines
}

function recognitionLiveUbuntu {
  touch "${WORKDIR}image/ubuntu"
  touch "${WORKDIR}.disk/base_installable"
  echo "full_cd/single" > "${WORKDIR}.disk/cd_type"
  echo "Ubuntu Remix" > "${WORKDIR}.disk/info"
  echo "http//your-release-notes-url.com" > "${WORKDIR}.disk/release_notes_url"
}

function calculateMD5 {
  log_msg "Calculate MD5"
  (cd "${WORKDIR}image" && find . -type f -print0 | xargs -0 md5sum |          \
      grep -v "\./md5sum.txt" > md5sum.txt)
}

function createISO {
  log_msg "Create ISO Image for a LiveCD"
  local dir_createIso="${WORKDIR}image/"
  mkisofs -r -V "$IMAGE_NAME" 
          -cache-inodes                                                        \
          -J -l -b "${dir_createIso}isolinux/isolinux.bin"                     \
          -c "${dir_createIso}isolinux/boot.cat" -no-emul-boot                 \
          -boot-load-size 4 -boot-info-table                                   \
          -o "${CUSTOMIMAGE}" "${DIR_BUILD}" >/dev/null 2>&1
}

function log_msg() {
    local mdate="$(date +%d-%m-%Y\ %H:%M:%S) "
    if [ ! -d "${WORKDIR}" ]; then
      mkdir "${WORKDIR}"
    fi
    echo "$1"
    echo "$mdate$1" >> "${WORKDIR}LiveCD.log"
}

function backupScript {
    mkdir -p /home/user/scripts
    if [ ! -d /home/user/scripts/$(date +%d%m%Y) ]; then
      mkdir -p /home/user/scripts/$(date +%d%m%Y)
    fi
    cp /home/user/run.bash /home/user/scripts/$(date +%d%m%Y)/                 \
        "$(date +%H:%M-%d%m%Y)"-livecd.bash
}

# Script's entry point: #############################################
main "$@"