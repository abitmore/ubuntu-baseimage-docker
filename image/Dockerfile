ARG BASE_IMAGE=ubuntu:24.04
FROM $BASE_IMAGE

ARG QEMU_ARCH
#ADD x86_64_qemu-${QEMU_ARCH}-static.tar.gz /usr/bin

# Ubuntu 26.04+ ships uutils-coreutils (Rust) and sudo-rs (Rust) by default.
# Set INSTALL_GNU_COREUTILS=1 to replace them with GNU Coreutils and
# traditional sudo. Has no effect on Ubuntu releases prior to 26.04.
ARG INSTALL_GNU_COREUTILS=0

COPY . /bd_build

RUN INSTALL_GNU_COREUTILS=$INSTALL_GNU_COREUTILS /bd_build/prepare.sh && \
	/bd_build/system_services.sh && \
	/bd_build/utilities.sh && \
	/bd_build/cleanup.sh

ENV DEBIAN_FRONTEND="teletype" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8"

CMD ["/sbin/my_init"]
