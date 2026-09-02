FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    wget \
    axel \
    debootstrap \
    dosfstools \
    file \
    gdisk \
    grub-common \
    grub-pc-bin \
    grub-efi-amd64-bin \
    initramfs-tools \
    kmod \
    mtools \
    python3 \
    rsync \
    squashfs-tools \
    systemd-sysv \
    xorriso \
    xz-utils \
    zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY config/ /work/config/
COPY scripts/ /work/scripts/
COPY overlay/ /work/overlay/

RUN chmod +x /work/scripts/*.sh

ENTRYPOINT ["/work/scripts/build.sh"]
