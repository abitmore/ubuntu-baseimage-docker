#!/bin/bash
set -e
source /bd_build/buildconfig
set -x

## Prevent initramfs updates from trying to run grub and lilo.
## https://journal.paul.querna.org/articles/2013/10/15/docker-ubuntu-on-rackspace/
## http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=594189
export INITRD=no
mkdir -p /etc/container_environment
echo -n no > /etc/container_environment/INITRD

## Enable Ubuntu Universe, Multiverse, and deb-src for main.
if grep -E '^ID=' /etc/os-release | grep -q ubuntu; then
  UBUNTU_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
  # Ubuntu 24.04+ uses DEB822 format (.sources files); older releases use sources.list
  if dpkg --compare-versions "$UBUNTU_VERSION" ge "24.04" 2>/dev/null && \
      compgen -G '/etc/apt/sources.list.d/*.sources' > /dev/null; then
    # DEB822 format: enable universe and multiverse components
    for f in /etc/apt/sources.list.d/*.sources; do
      sed -i 's/^Components: main$/Components: main restricted universe multiverse/' "$f"
      sed -i 's/^Components: main restricted$/Components: main restricted universe multiverse/' "$f"
    done
  else
    # Legacy sources.list format (Ubuntu < 24.04)
    sed -i 's/^#\s*\(deb.*main restricted\)$/\1/g' /etc/apt/sources.list
    sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list
    sed -i 's/^#\s*\(deb.*multiverse\)$/\1/g' /etc/apt/sources.list
  fi
fi

apt-get update

## Fix some issues with APT packages.
## See https://github.com/dotcloud/docker/issues/1024
dpkg-divert --local --rename --add /sbin/initctl
ln -sf /bin/true /sbin/initctl

## Replace the 'ischroot' tool to make it always return true.
## Prevent initscripts updates from breaking /dev/shm.
## https://journal.paul.querna.org/articles/2013/10/15/docker-ubuntu-on-rackspace/
## https://bugs.launchpad.net/launchpad/+bug/974584
dpkg-divert --local --rename --add /usr/bin/ischroot
ln -sf /bin/true /usr/bin/ischroot

# apt-utils fix for Ubuntu 16.04
$minimal_apt_get_install apt-utils

## Install HTTPS support for APT.
$minimal_apt_get_install apt-transport-https ca-certificates

## Install add-apt-repository
$minimal_apt_get_install software-properties-common

## Upgrade all packages.
apt-get dist-upgrade -y --no-install-recommends -o Dpkg::Options::="--force-confold"

## Ubuntu 26.04+ ships uutils-coreutils (Rust) and sudo-rs (Rust) by default.
## Optionally replace them with GNU Coreutils and traditional sudo when
## INSTALL_GNU_COREUTILS=1 is set at build time.
if grep -E '^ID=' /etc/os-release | grep -q ubuntu; then
  UBUNTU_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
  if dpkg --compare-versions "$UBUNTU_VERSION" ge "26.04" 2>/dev/null; then
    if [ "${INSTALL_GNU_COREUTILS:-0}" -eq 1 ]; then
      echo "*** Installing GNU Coreutils and traditional sudo to replace Rust variants..."
      # Install GNU Coreutils if available (package name may vary by Ubuntu release).
      # 'coreutils-gnu' is the expected package name for the GNU implementation
      # when uutils-coreutils is the default.
      if apt-cache show coreutils-gnu > /dev/null 2>&1; then
        $minimal_apt_get_install coreutils-gnu
      fi
      # Install traditional sudo if available (package name may vary).
      # 'sudo-traditional' or similar may be provided alongside 'sudo-rs'.
      if apt-cache show sudo-traditional > /dev/null 2>&1; then
        $minimal_apt_get_install sudo-traditional
      elif apt-cache show sudo-classic > /dev/null 2>&1; then
        $minimal_apt_get_install sudo-classic
      fi
    else
      echo "*** Ubuntu 26.04 detected: using default uutils-coreutils (Rust) and sudo-rs (Rust)."
      echo "*** Set INSTALL_GNU_COREUTILS=1 at build time to use GNU Coreutils and traditional sudo instead."
    fi
  fi
fi

## Fix locale.
case $(lsb_release -is) in
  Ubuntu)
    $minimal_apt_get_install language-pack-en
    ;;
  Debian)
    $minimal_apt_get_install locales locales-all
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    ;;
  *)
    ;;
esac
locale-gen en_US
update-locale LANG=en_US.UTF-8 LC_CTYPE=en_US.UTF-8
echo -n en_US.UTF-8 > /etc/container_environment/LANG
echo -n en_US.UTF-8 > /etc/container_environment/LC_CTYPE
