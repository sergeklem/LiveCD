#!/bin/bash
################################################################################
#
# Description
#
################################################################################

### Constants ##################################################################
DIR_BUILD="/home/user/iso/"
HOME="/home/user/"
IMAGE="ubuntu-12.04.2-server-amd64.iso"
# mdate="${date +%Y%m%d}"
# CUSTOMIMAGE="arm-bmcm-nightly-${mdate}_amd64.iso"
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
  createPreseed
  createPostinstall
  changeBootScreen
  copyDebPackages
  packingImage
}

if [ ! -f "${HOME}${IMAGE}" ]; then
  log_msg "Error"
  exit 1
fi

function unpacingImage {
  # Распаковываем образ в директорию
  rm -rf "${DIR_BUILD}"
  mkdir -p "${DIR_BUILD}"
  log_msg "** Mounting image..."
  sudo mount -o loop "${IMAGE}" /mnt/
  log_msg "** Syncing..."
  rsync -av /mnt/ "${DIR_BUILD}" >/dev/null 2>&1
  chmod -R u+w "${DIR_BUILD}"
}

function createLocRep {
  if [ `ls ${HOME}packages/debs | wc -l` -gt 0 ]; then
   return 0
  fi
  log_msg "Create a directory with *. deb packages"
  mkdir -p "${HOME}packages/debs/"
  apt-get install --yes python-software-properties >/dev/null 2>&1
  add-apt-repository --yes ppa:chris-lea/node.js >/dev/null 2>&1
  add-apt-repository --yes ppa:webupd8team/java >/dev/null 2>&1
  apt-get update >/dev/null 2>&1
  log_msg "Download *.deb packages"
  local fileTmpUrls="/tmp/downloads.txt"
  rm -f "${fileTmpUrls}"
  local packages=
  IFS=' ' read -a packages <<< "${TARGET_PACKAGES}"
  for p in "${packages[@]}"; do
    apt-get --print-uris --yes install "${p}" \
        | grep ^\' | cut -d\' -f2 >> "${fileTmpUrls}"
  done
  (cd "${HOME}packages/debs" && wget --input-file "${fileTmpUrls}"             \
      >/dev/null 2>&1)
  log_msg "Download kernel"
  local dir_kernel="${HOME}packages/kernel/"
  local version="3.2.27.130816-bmcm-rt40"
  local headers="linux-headers-${version}_0_amd64.deb"
  local image="linux-image-${version}_0_amd64.deb"
  local url="https://dl.dropboxusercontent.com/u/42220829/pp/"
  mkdir -p "${dir_kernel}"
  wget --quiet "${url}${headers}" -O "${dir_kernel}${headers}">/dev/null 2>&1
  wget --quiet "${url}${image}" -O "${dir_kernel}${image}">/dev/null 2>&1
  rm -rf "${HOME}packages/debs/cups"*
  rm -rf "${HOME}packages/debs/avahi-daemon"*
  rm -rf "${HOME}packages/debs/"*".deb."*
}

function createBootMenu {
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
}

function gitClone {
  local git_user="$1"
  local git_password="$2"
  local git_url="mir.afsoft.org/opt/git/mm/mir.git"
  mkdir -p "${HOME}mir.git"
  git clone "ssh://${git_user}@${git_url}" "${HOME}mir.git"
}

function makeDialogPackage {
  apt-get install --yes make gcc
  local srcDir="$(date +%Y-%m-%d)"
  local urlMirGit="ssh://"${git_user}"@"${git_url}""
  local stationName="mitino"
  #               dscp0
  #               dscp1
  local hostRole="shn0"
  local dir_git="${HOME}mir.git/"
  # cd
  # rm -Rf ./"${srcDir}"
  # mkdir -p ./"${srcDir}"/mir.git
  # cd ./"${srcDir}"
  # git clone "${urlMirGit}" ./mir.git/
  # scp "${urlMirGit}" /downloads/packages/* ./mir.git/downloads/packages/
  cd "${dir_git}src/logic/system/fs/"
  make dialog_package
  mv ./dialog_package.tar /opt/
  make configs
  mv ./layout.tgz /opt/
  rm -Rf /opt/mir.app.old
  mkdir -p /opt/mir.app
  mv /opt/mir.app /opt/mir.app.old
  cd /opt/
  tar xf ./dialog_package.tar
  rm -f /opt/dialog_package.tar
  cd ~/"${srcDir}"/mir.git/cfg/
  make "${stationName}"
  make install
  cd rm -Rf ./"${srcDir}"
  sudo -k /opt/mir.app/bin/dialog_finalize_install.sh "${hostRole}"
}

function createPreseed {
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
echo "1234567890"
dpkg -i linux-headers-3.2.27.130816-bmcm-rt40_0_amd64.deb linux-image-3.2.27.130816-bmcm-rt40_0_amd64.deb
ln -s /usr/src/linux-headers-3.2.27.130816-bmcm-rt40 /usr/src/linux

#install bmcm software


# Копируем заренее подготовленную начальную конфигурацию пользователя ubuntu
# cp -R /install/home/* /home/ubuntu/
# cp -R /install/home/.config /home/ubuntu/
# cp -R /install/home/.local /home/ubuntu/
# cp -R /install/home/.gconf /home/ubuntu/
# chown -R ubuntu:ubuntu /home/ubuntu
# chmod -R u+w /home/ubuntu
EOFcreatePostinstall
}

function changeBootScreen {
  log_msg "Change the boot screen"
  local dir_boot_screen="${HOME}iso/isolinux/"
  rm -rf "${dir_boot_screen}splash.png"
  wget https://www.dropbox.com/s/j77lfdjmkkvaa1w/splash.png -O \
    "${dir_boot_screen}splash.png">/dev/null 2>&1
}

function copyDebPackages {
  mkdir -p "${HOME}iso/packages"
  cp -rf "${HOME}packages/"* "${HOME}iso/packages/"
}

function packingImage {
  # Запаковываем содержимое iso/ в образ ubuntu-custom.iso
  log_msg ">>> Calculating MD5 sums..."
  rm -rf "${DIR_BUILD}md5sum.txt"
  (cd "${DIR_BUILD}" && find . -type f -print0 | xargs -0 md5sum |             \
      grep -v "boot.cat" | grep -v "md5sum.txt" > md5sum.txt)
  log_msg ">>> Building iso image..."
  apt-get install --yes genisoimage >/dev/null 2>&1
  mkisofs -r -V "Ubuntu OEM install"                                           \
          -cache-inodes                                                        \
          -J -l -b "isolinux/isolinux.bin"                                     \
          -c "isolinux/boot.cat" -no-emul-boot                                 \
          -boot-load-size 4 -boot-info-table                                   \
          -o "${CUSTOMIMAGE}" "${DIR_BUILD}" >/dev/null 2>&1
}

function log_msg() {
  mdate="$(date +%d-%m-%Y\ %H:%M:%S) "
  if [ ! -d "${DIR_BUILD}" ]; then
    mkdir -p "${DIR_BUILD}"
  fi
  echo "$1"
  echo "$mdate$1" >> "${DIR_BUILD}make_installer.log"
}

# Script's entry point: ########################################################
main "$@"