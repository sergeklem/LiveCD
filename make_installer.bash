#!/bin/bash
################################################################################
#
# Description
#
################################################################################

### Constants ##################################################################
THIS_SCRIPT_NAME=$(basename $0 .bash)

STATION_NAME="mitino"
TARGET_HOST_ROLE="shn0"
                # dscp0
                # dscp1
                # shn0

DIR_BUILD="/home/user/iso/"
HOME="/home/user/"
IMAGE="ubuntu-12.04.2-server-amd64.iso"
#DIR_MOUNT_UBUNTU_ISO="/mnt/default_ubuntu_iso/"
DIR_MOUNT_UBUNTU_ISO="/mnt/"
BOOT_WALLPAPER="https://www.dropbox.com/s/ykudjl4ozuungie/wallpaper.png"
# mdate="${date +%Y%m%d}"
# CUSTOMIMAGE="arm-bmcm-${mdate}_amd64.iso"
CUSTOMIMAGE="ARM_12.04-amd64.iso"
USER="user"
PASSWORD="user"
TARGET_PACKAGES="xorg nodm chromium-browser wget htop mc nano openssh-server   \
                 sshpass git curl bzip2 build-essential zlib1g-dev libtool     \
                 build-essential zlib1g-dev libtool automake autoconf expect   \
                 autotools-dev python-pexpect python-software-properties       \
                 python cups foo2zjs nodejs debconf-utils maven whois perl"
                 # oracle-java7-installer oracle-java7-set-default"

### Implementation #############################################################
function main {
  unpacingImage
  createLocRep
  createBootMenu
  makeDialogPackage
  createPreseed
  createPostinstall
  copyDebPackages
  packingImage
}

if [ ! -f "${HOME}${IMAGE}" ]; then
  log_msg "Image ${IMAGE} not found. Exiting"
  exit 1
fi

function unpacingImage {
  # Unpacking image in directory
  rm -rf "${DIR_BUILD}"
  mkdir -p "${DIR_BUILD}"
  mkdir -p "${DIR_MOUNT_UBUNTU_ISO}"
  log_msg "** Mounting image..."
  mount -o loop "${IMAGE}" "${DIR_MOUNT_UBUNTU_ISO}"
  log_msg "** Syncing..."
  rsync -av /mnt/ "${DIR_BUILD}" >/dev/null 2>&1
  chmod -R u+w "${DIR_BUILD}"
}

function createLocRep {
  mkdir -p "${HOME}packages/debs"
  local arch="amd64"
  local release="precise"
  local fileDebUrls="/tmp/required_deb_urls.txt"
  apt-get install --yes debootstrap >/dev/null 2>&1
  debootstrap --arch="${arch}" "${release}" "${HOME}packages" >/dev/null 2>&1
  cp /etc/hosts "${HOME}packages/etc/hosts"
  cp /etc/resolv.conf "${HOME}packages/etc/resolv.conf"
  cp /etc/apt/sources.list "${HOME}packages/etc/apt/sources.list"
  cat > "${HOME}packages/tmp/create_deb_list.bash" <<"EOFcreateLocRep"
#!/bin/bash

function main {
  mountSystemDirectories

  addThirdPartyRepositories

  fetchRequiredDebPackageUrls "${@}"

  unmountSystemDirectories
}

function mountSystemDirectories {
  mount none -t proc /proc 
  mount none -t sysfs /sys
  mount none -t devpts /dev/pts
  export HOME=/root
  export LC_ALL=C
}

function addThirdPartyRepositories {
  apt-get update >/dev/null 2>&1
  apt-get install --yes python-software-properties >/dev/null 2>&1
  add-apt-repository --yes ppa:chris-lea/node.js >/dev/null 2>&1
  add-apt-repository --yes ppa:webupd8team/java >/dev/null 2>&1
  apt-get update >/dev/null 2>&1
  apt-get remove --yes --purge python-software-properties >/dev/null 2>&1
}

function fetchRequiredDebPackageUrls {
  local fileUrls="${1}"
  shift
  local targetPackages="${@}"

  echo "fileUrls=\"${fileUrls}\""
  echo "targetPackages=\"${targetPackages}\""

  rm -f "${fileUrls}"

  echo "Fetching *.deb packages URLs to file: \"${fileUrls}\""
  IFS=' ' read -a packages <<< "${targetPackages}"
  for p in "${packages[@]}"; do
    apt-get --print-uris --yes install "${p}" \
        | grep ^\' | cut -d\' -f2 >> "${fileUrls}"
  done
}

function unmountSystemDirectories {
  umount -lf /proc
  umount -lf /sys
  umount -lf /dev/pts
}

main "$@"

EOFcreateLocRep
  chmod +x "${HOME}packages/tmp/create_deb_list.bash"
  chroot "${HOME}packages" \
      bash "/tmp/create_deb_list.bash" "${fileDebUrls}" "${TARGET_PACKAGES}"

  log_msg "Download *.deb packages"
  (cd "${HOME}packages/debs" && wget --input-file                              \
      "${HOME}packages${fileDebUrls}" >/dev/null 2>&1)
  local dir_kernel="${HOME}packages/kernel/"
  local version="3.2.27.130816-bmcm-rt40"
  local headers="linux-headers-${version}_0_amd64.deb"
  local image="linux-image-${version}_0_amd64.deb"
  local url="https://dl.dropboxusercontent.com/u/42220829/pp/"
  mkdir -p "${dir_kernel}"
  log_msg "Download kernel"
  wget --quiet "${url}${headers}" -O "${dir_kernel}${headers}">/dev/null 2>&1
  wget --quiet "${url}${image}" -O "${dir_kernel}${image}">/dev/null 2>&1
  rm -rf "${HOME}packages/debs/cups"*
  rm -rf "${HOME}packages/debs/avahi-daemon"*
  log_msg "Clean duplicate packages"
  rm -rf "${HOME}packages/debs/"*".deb."*
}

function createBootMenu {
  log_msg "Create Boot menu and choice language"
  echo "ru" >> "${DIR_BUILD}isolinux/lang"
  cat > "${DIR_BUILD}isolinux/txt.cfg" <<EOF1
default auto
label auto
  menu label ^Auto install
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/auto.seed vga=788 language=ru country=RU locale=ru_RU.UTF-8 console-setup/ask_detect=false keyboard-configuration/layout=ru keyboard-configuration/variant=ru keyboard-configuration/toggle=Alt+Shift initrd=/install/initrd.gz quiet --
label memtest
  menu label Test ^memory
  kernel /install/mt86plus
label hd
  menu label ^Boot from first hard disk
  localboot 0x80
EOF1
  cat > "${DIR_BUILD}isolinux/isolinux.cfg" <<EOF2
# D-I config version 2.0
include menu.cfg
default vesamenu.c32
prompt 0
timeout 20
ui gfxboot bootlogo
EOF2
}

# function gitClone {
#   apt-get install --yes git >/dev/null 2>&1
#   local git_user="$1"
#   local git_password="$2"
#   local git_url="mir.afsoft.org/opt/git/mm/mir.git"
#   mkdir -p "${HOME}mir.git"
#   git clone "ssh://${git_user}@${git_url}" "${HOME}mir.git"
# }

function makeDialogPackage {
  # wget https://www.dropbox.com/s/fq3zsl9v7n6gvdl/sw_dev__ubuntu_12.04_setup_all_software_from_repos.bash && \
  # chmod +x sw_dev__ubuntu_12.04_setup_all_software_from_repos.bash && bash ./sw_dev__ubuntu_12.04_setup_all_software_from_repos.bash
  local dirInstall="${HOME}packages/bmcm/"
  local dirGit="${HOME}mir.git/"

  mkdir -p "${dirInstall}"
  make --directory="${dirGit}downloads/packages/"

  local dirFs="${dirGit}src/logic/system/fs/"
  make --directory="${dirFs}" dialog_package && \
      mv "${dirFs}dialog_package.tar" "${dirInstall}"
  make --directory="${dirFs}" configs && \
      mv "${dirFs}layout.tgz" "${dirInstall}"

  local dirCfg="${dirGit}cfg/"
  make --directory="${dirCfg}" "${STATION_NAME}" && \
      mv "${dirCfg}build/station_config.tgz" "${dirInstall}"
}

function createPreseed {
  log_msg "Create preseed file"
  apt-get install --yes syslinux-common >/dev/null 2>&1
  local cryptpassword=`md5pass ${PASSWORD}`
  cat > "${DIR_BUILD}preseed/auto.seed" <<EOFcreatePreseed
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
#d-i passwd/root-login boolean true
d-i passwd/make-user boolean true
#d-i passwd/root-password-crypted password ${cryptpassword}
d-i passwd/user-fullname string ${USER}
d-i passwd/username string ${USER}
d-i passwd/user-password-crypted password ${cryptpassword}
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

# BASE INSTALLER
# Устанавливаемый пакет (мета) с образом ядра; можно указать «none»,
# если ядро устанавливать не нужно.
d-i base-installer/kernel/image string none

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

d-i preseed/late_command string mkdir /target/install/;                        \
    cp -R /cdrom/packages/* /target/install/;                                  \
    chroot /target chmod +x /install/postinstall.bash;                         \
    chroot /target bash /install/postinstall.bash
EOFcreatePreseed
}

function createPostinstall {
  log_msg "Create postinstall script"
  cat > "${HOME}packages/postinstall.bash" <<EOFcreatePostinstall
#!/bin/bash

# Для APT. Эти переменные наследуются от инсталлятора и мешают нормальной работе.
unset DEBCONF_REDIR
unset DEBCONF_FRONTEND
unset DEBIAN_HAS_FRONTEND
unset DEBIAN_FRONTEND


#install *.deb packages
dpkg -i --force-depends /install/debs/*.deb


#install custom kernel
rm -f /usr/src/linux >/dev/null
cd /install/kernel/
dpkg -i linux-headers-3.2.27.130816-bmcm-rt40_0_amd64.deb linux-image-3.2.27.130816-bmcm-rt40_0_amd64.deb
ln -s /usr/src/linux-headers-3.2.27.130816-bmcm-rt40 /usr/src/linux

#install bmcm software
mkdir "/opt"
mv "/install/bmcm/layout.tgz" "/opt/"
tar -xzf "/install/bmcm/station_config.tgz" --directory "/opt/mir.cfg/"
mv "/install/bmcm/dialog_package.tar" "/opt/" && \
    cd "/opt/" && tar xf "./dialog_package.tar"
# rm -f "/opt/dialog_package.tar"
/opt/mir.app/bin/dialog_finalize_install.sh "${TARGET_HOST_ROLE}"

#change boot screen
mkdir -p /lib/plymouth/themes/bmcm
cd /install/wallpaper.png /lib/plymouth/themes/bmcm
  cat > /lib/plymouth/themes/bmcm/bmcm.plymouth <<EOF1
[Plymouth Theme]
Name=bmcm
Description=Wallpaper only
ModuleName=script

[script]
ImageDir=/lib/plymouth/themes/bmcm
ScriptFile=/lib/plymouth/themes/simple/bmcm.script
EOF1

cat > /lib/plymouth/themes/bmcm/bmcm.script <<EOF2
wallpaper_image = Image(«wallpaper.png»);
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
resized_wallpaper_image = wallpaper_image.Scale(screen_width,screen_height);
wallpaper_sprite = Sprite(resized_wallpaper_image);
wallpaper_sprite.SetZ(-100);
EOF2

update-alternatives --install /lib/plymouth/themes/default.plymouth default.plymouth /lib/plymouth/themes/bmcm/bmcm.plymouth 10
update-alternatives --config default.plymouth
update-initramfs -u
EOFcreatePostinstall
}

function changeBootScreen {
  log_msg "Change the boot screen"
  wget "${BOOT_WALLPAPER}" -O "${HOME}iso/packages">/dev/null 2>&1
}

function copyDebPackages {
  log_msg "Copy *.deb packages in the image directory"
  mkdir -p "${HOME}iso/packages/debs"
  mkdir -p "${HOME}iso/packages/kernel"
  mkdir -p "${HOME}iso/packages/bmcm"
  cp -rf "${HOME}packages/debs/"* "${HOME}iso/packages/debs"
  cp -rf "${HOME}packages/kernel/"* "${HOME}iso/packages/kernel"
  cp -rf "${HOME}packages/postinstall.bash" "${HOME}iso/packages/postinstall.bash"
  cp -rf "${HOME}packages/bmcm/"* "${HOME}iso/packages/bmcm"
}

function packingImage {
  log_msg ">>> Calculating MD5 sums..."
  rm -rf "${DIR_BUILD}md5sum.txt"
  (cd "${DIR_BUILD}" && find . -type f -print0 | xargs -0 md5sum |             \
      grep -v "boot.cat" | grep -v "md5sum.txt" > md5sum.txt)
  log_msg ">>> Building iso image..."
  apt-get install --yes genisoimage >/dev/null 2>&1
  mkisofs -r -V "BMCM ARM"                                                     \
          -cache-inodes                                                        \
          -J -l -b "isolinux/isolinux.bin"                                     \
          -c "isolinux/boot.cat" -no-emul-boot                                 \
          -boot-load-size 4 -boot-info-table                                   \
          -o "${CUSTOMIMAGE}" "${DIR_BUILD}" >/dev/null 2>&1
  umount "${DIR_MOUNT_UBUNTU_ISO}"
}

# mkisofs -r -V "BMCM ARM" -cache-inodes -J -l -b "isolinux/isolinux.bin" -c "isolinux/boot.cat" -no-emul-boot -boot-load-size 4 -boot-info-table -o "ARM.iso" "/home/user/iso/"

function log_msg() {
  mdate="$(date +%d-%m-%Y\ %H:%M:%S) "
  if [ ! -d "${DIR_BUILD}" ]; then
    mkdir -p "${DIR_BUILD}"
  fi
  echo "$1"
  echo "$mdate$1" >> "${DIR_BUILD}${THIS_SCRIPT_NAME}.log"
}

# Script's entry point: ########################################################
main "$@"