#!/bin/bash


BUILD=/home/user/iso
HOME=/home/user
IMAGE=ubuntu-12.04.2-server-amd64.iso
CUSTOMIMAGE=ARM_12.04-amd64.iso
USER='user'
PASS='user'
CRYPTPASS='$1$fbh0yv5L$qlugJUXOjNhiakQUYiJ7x0'

function main {
	unpacing
	bootMenu
	createLocRep
	createPreseed
	createPostinstall
	changeBootScreen
	copyRep
	packingImage
}

if [ ! -f $HOME/$IMAGE ]; then
    echo "Error"
	exit 1
fi

function unpacing {
	# Распаковываем образ в директорию
	rm -rf $BUILD/
	mkdir $BUILD/
	echo "** Mounting image..."
	sudo mount -o loop $IMAGE /mnt/
	echo "** Syncing..."
	rsync -av /mnt/ $BUILD/ >/dev/null 2>&1
	chmod -R u+w $BUILD/
}

function bootMenu {
	echo "ru" >> $BUILD/isolinux/lang
	cat > $BUILD/isolinux/txt.cfg <<EOF1
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

function createLocRep {
	if [ `ls $HOME/packages/debs | wc -l` -eq 0 ]; then
		echo "Create a directory with *. deb packages"
		mkdir -p $HOME/packages/debs
		cd $HOME/packages/debs
		apt-get install --yes python-software-properties >/dev/null 2>&1
		add-apt-repository --yes ppa:chris-lea/node.js >/dev/null 2>&1
		add-apt-repository --yes ppa:webupd8team/java >/dev/null 2>&1
		apt-get update >/dev/null 2>&1
		echo "Download *.deb packages"
		aptitude download	xorg nodm chromium-browser wget htop mc nano        \
							openssh-server sshpass git curl bzip2               \
							build-essential zlib1g-dev libtool automake         \
							autoconf autotools-dev expect python-pexpect        \
							python-software-properties python cups foo2zjs      \
							nodejs debconf-utils maven whois m4 perl            \
							oracle-java7-installer oracle-java7-set-default >/dev/null 2>&1
		echo "Download kernel"
		wget https://dl.dropboxusercontent.com/u/42220829/pp/linux-headers-3.2.27.130816-bmcm-rt40_0_amd64.deb >/dev/null 2>&1
		wget https://dl.dropboxusercontent.com/u/42220829/pp/linux-image-3.2.27.130816-bmcm-rt40_0_amd64.deb >/dev/null 2>&1
	fi
}

function createPreseed {
	apt-get install --yes whois >/dev/null 2>&1
echo 'd-i debian-installer/locale string ru_RU.UTF-8
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
d-i passwd/root-password-crypted password $6$/C5kV2J.$9bjWQOTcmgRMt2YVk3w.hLg6wufE4yBI/ab4FmalCinbMSbTBzmNIbzA9gn9b38
d-i passwd/user-fullname string user
d-i passwd/username string $USER
d-i passwd/user-password-crypted password $6$/C5kV2J.$9bjWQOTcmgRMt2YVk3w.hLg6wufE4yBI/ab4FmalCinbMSbTBzmNIbzA9gn9b38
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false

# Partitioning
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
d-i partman-auto/expert_recipe string                        \
     boot-root ::                                            \
             512 50000 512 ext4                              \
                     $primary{ } $bootable{ }                \
                     method{ format } format{ }              \
                     use_filesystem{ } filesystem{ ext4 }    \
                     mountpoint{ /boot }                     \
             .                                               \
             7000 10000 90000 ext4                           \
                     method{ format } format{ }              \
                     use_filesystem{ } filesystem{ ext4 }    \
                     mountpoint{ / }                         \
             .                                               \
             5000 10000 10000 ext4                           \
                     method{ format } format{ }              \
                     use_filesystem{ } filesystem{ ext4 }    \
                     mountpoint{ /var }                      \
             .                                               \
             500 10000 1000000000 ext4                       \
                     method{ format } format{ }              \
                     use_filesystem{ } filesystem{ ext4 }    \
                     mountpoint{ /srv }                      \
             .                                               \
             64 51200 300% linux-swap                        \
                     method{ swap } format{ }                \
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

d-i preseed/late_command string	mkdir /target/install/;                           \
								cp -R /cdrom/packages/* /target/install/;         \
								chroot /target chmod +x /install/postinstall.bash;  \
								chroot /target bash /install/postinstall.bash
' >> $BUILD/preseed/auto.seed
}

function createPostinstall {
	echo '#!/bin/bash

# Для APT. Эти переменные наследуются от инсталлятора и мешают нормальной работе.
unset DEBCONF_REDIR
unset DEBCONF_FRONTEND
unset DEBIAN_HAS_FRONTEND
unset DEBIAN_FRONTEND

INSATALLDIR="/install/debs/"

function main {
	installSoftwarePackages
	installCustomKernel
	installSoftwareFromSource
	enableMulticastTrafficOnUbuntuServer
	setVagrantProvisionCompleteFlag
}


function disablePeriodicUpdates {
  echo "Disabling periodic operating system updates..."
  apt-get remove --yes update-manager-core >/dev/null 2>&1

  local file="/etc/apt/apt.conf.d/10periodic"
  sed -ri "s/(APT::Periodic::Update-Package-Lists\ *\")1\";/\10\";/" "${file}"
}

function installSoftwarePackages {
	echo "Install software packages"
	setupGUI

	setupUsefulUtils
	setupBuildEssential
	setupExpect
	setupPython

	setupPrinting
	setupChromium
}

function setupGUI {
	echo "  Installing GUI..."
	cd $INSATALLDIR
	dpkg -i xorg_*.deb nodm_*.deb
}

function setupUsefulUtils {
	echo "  Installing utils like wget, nano, etc..."
	cd $INSATALLDIR
	dpkg -i wget_*.deb curl_*.deb htop_*.deb mc_*.deb nano_*.deb
}

function setupBuildEssential {
	echo "  Installing build-essential..."
	cd $INSATALLDIR
	dpkg -i openssh-server_*.deb sshpass_*.deb
	dpkg -i git_*.deb wget_*.deb bzip2_*.deb
	dpkg -i build-essential_*.deb zlib1g-dev_*.deb
	dpkg -i libtool_*.deb m4_*.deb perl_*.deb autoconf_*.deb automake_*.deb autotools-dev_*.deb
}

function setupExpect {
	echo "  Installing expect..."
	cd $INSATALLDIR
	dpkg -i expect_*.deb
}

function setupPython {
	echo "  Installing python..."
	cd $INSATALLDIR
	dpkg -i python-software-properties_*.deb python_*.deb
	dpkg -i  python-pexpect_*.deb
}

function setupPrinting {
	echo "  Installing printing support..."
	cd $INSATALLDIR
	dpkg -i cups_*.deb
	echo "  Installing specific printer drivers..."
	dpkg -i foo2zjs_*.deb
}

function setupChromium {
	echo "  Installing chromium..."
	cd $INSATALLDIR
	dpkg -i chromium-browser_*.deb >/dev/null 2>&1; apt-get --fix-broken --yes install >/dev/null 2>&1
}

function installCustomKernel {
	echo "Install custom kernel"
	rm -f "/usr/src/linux" >/dev/null 2>&1
	dpkg -i "linux-headers-*.deb" "linux-image-*.deb" >/dev/null 2>&1 && \
	ln -s "/usr/src/linux-headers-${version}" "/usr/src/linux" >/dev/null 2>&1
}

function installSoftwareFromSource {
	echo "Install software from tarballs"
	setupNodeJs
	setupJava
}

function setupNodeJs {
	echo "  Installing nodejs..."
	dpkg -i nodejs_*.deb >/dev/null 2>&1
}

function setupJava {
	echo "  Installing java..."
	# State that we accepted the license.
	#dpkg -i oracle-java7-installer_*.deb
	#dpkg -i oracle-java7-set_*.deb
	dpkg -i maven_*.deb
}

function updateConfigFileEntry {
	local fileName="$1"
	local entry="$2" # "variableName=newValue"
	local variable="$(trim "${entry%%=*}")"
	local newValue="$(trim "${entry#*=}")"
	# TODO: Prevent updating commented entries!
	sed -ri "s/(${variable}\ *=\ *).*/\1${newValue}/" "${fileName}"
	if ! grep -q "${variable}\ *=\ *${newValue}" "${fileName}"; then
		echo -e "\n${variable}=${newValue}\n" >> "${fileName}"
	fi
}

function enableMulticastTrafficOnUbuntuServer {
	local file="/etc/sysctl.conf"
	echo "  Enabling multicast traffic on Ubuntu Server..."
	updateConfigFileEntry "${file}" "net.ipv4.conf.default.rp_filter=0"
	updateConfigFileEntry "${file}" "net.ipv4.conf.default.force_igmp_version=2"
	updateConfigFileEntry "${file}" "net.ipv4.conf.all.rp_filter=0"
	updateConfigFileEntry "${file}" "net.ipv4.conf.all.force_igmp_version=2"
}

# Устанавливаем немного дополнительных пакетов

# dpkg -i debconf-utils_*.deb
# dpkg -i whois_*.deb
#dpkg -i --yes oracle-java7-installer_*.deb oracle-java7-set_*.deb

main "$@"

# Копируем заренее подготовленную начальную конфигурацию пользователя ubuntu
# cp -R /install/home/* /home/ubuntu/
# cp -R /install/home/.config /home/ubuntu/
# cp -R /install/home/.local /home/ubuntu/
# cp -R /install/home/.gconf /home/ubuntu/
# chown -R ubuntu:ubuntu /home/ubuntu
# chmod -R u+w /home/ubuntu
' >> $HOME/packages/postinstall.bash
}

function changeBootScreen {
echo "Change the boot screen"
cd $HOME/iso/isolinux
rm -rf splash.png
wget https://www.dropbox.com/s/j77lfdjmkkvaa1w/splash.png >/dev/null 2>&1
}

function copyRep {
cd
mkdir $HOME/iso/packages
cp -r packages/* iso/packages
}

function packingImage {
	# Запаковываем содержимое iso/ в образ ubuntu-custom.iso
	echo ">>> Calculating MD5 sums..."
	rm $BUILD/md5sum.txt
	(cd $BUILD/ && find . -type f -print0 | xargs -0 md5sum | grep -v "boot.cat" | grep -v "md5sum.txt" > md5sum.txt)
	echo ">>> Building iso image..."
	apt-get install --yes genisoimage >/dev/null 2>&1
	mkisofs -r -V "Ubuntu OEM install" \
            -cache-inodes \
            -J -l -b isolinux/isolinux.bin \
            -c isolinux/boot.cat -no-emul-boot \
            -boot-load-size 4 -boot-info-table \
            -o $CUSTOMIMAGE $BUILD/ >/dev/null 2>&1
}

main "$@"
