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
    case "${INSTALL_GNU_COREUTILS:-0}" in
      0|1)
        INSTALL_GNU_COREUTILS_NORMALIZED="${INSTALL_GNU_COREUTILS:-0}"
        ;;
      *)
        echo "*** Invalid value for INSTALL_GNU_COREUTILS: '${INSTALL_GNU_COREUTILS}'" >&2
        echo "*** Expected 0 or 1." >&2
        exit 1
        ;;
    esac
    if [ "$INSTALL_GNU_COREUTILS_NORMALIZED" = "1" ]; then
      echo "*** Installing GNU Coreutils and traditional sudo to replace Rust variants..."
      GNU_COREUTILS_INSTALLED=0
      TRADITIONAL_SUDO_INSTALLED=0
      # Install GNU Coreutils if available (package name may vary by Ubuntu release).
      # 'coreutils-gnu' is the expected package name for the GNU implementation
      # when uutils-coreutils is the default.
      if apt-cache show coreutils-gnu > /dev/null 2>&1; then
        $minimal_apt_get_install coreutils-gnu
        GNU_COREUTILS_INSTALLED=1
      fi
      # Install traditional sudo if available (package name may vary).
      # 'sudo-traditional' or similar may be provided alongside 'sudo-rs'.
      if apt-cache show sudo-traditional > /dev/null 2>&1; then
        $minimal_apt_get_install sudo-traditional
        TRADITIONAL_SUDO_INSTALLED=1
      elif apt-cache show sudo-classic > /dev/null 2>&1; then
        $minimal_apt_get_install sudo-classic
        TRADITIONAL_SUDO_INSTALLED=1
      fi
      if [ "$GNU_COREUTILS_INSTALLED" -ne 1 ] || [ "$TRADITIONAL_SUDO_INSTALLED" -ne 1 ]; then
        echo "*** ERROR: INSTALL_GNU_COREUTILS=1 was requested, but the requested replacements could not be fully installed." >&2
        if [ "$GNU_COREUTILS_INSTALLED" -ne 1 ]; then
          echo "*** ERROR: No GNU coreutils replacement package was found (tried: coreutils-gnu)." >&2
        fi
        if [ "$TRADITIONAL_SUDO_INSTALLED" -ne 1 ]; then
          echo "*** ERROR: No traditional sudo replacement package was found (tried: sudo-traditional, sudo-classic)." >&2
        fi
        exit 1
      fi
      # Verify that GNU coreutils are now the active implementation on PATH.
      # Some packages may install binaries under a non-default path and rely on
      # update-alternatives; if so the replacement has not taken effect.
      if ! ls --version 2>&1 | grep -qi 'gnu coreutils'; then
        echo "*** ERROR: coreutils-gnu was installed but GNU coreutils are not active on PATH." >&2
        echo "*** 'ls --version' does not report 'GNU coreutils'." >&2
        echo "*** The package may place binaries outside the default PATH or require" >&2
        echo "*** manual update-alternatives configuration. Check Ubuntu 26.04 packaging." >&2
        exit 1
      fi
      LS_VER=$(ls --version | head -1)
      echo "*** GNU Coreutils are active ($LS_VER)."
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
