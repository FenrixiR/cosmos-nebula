DESCRIPTION = "OpenCentauri Base Image"
LICENSE = "GPL-3.0-only"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    packagegroup-base-wifi \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

IMAGE_LINGUAS = " "

inherit core-image

IMAGE_FEATURES += "ssh-server-dropbear"

CORE_IMAGE_EXTRA_INSTALL += "\
    nebula-config \
    usbutils \
    libgpiod \
    libgpiod-tools \
    kernel-modules \
    rtw88 \
    aic8800 \
    kalico-firmware-dsp \
    tcp-serial-bridge \
    guppyscreen \
    mcu-flasher \
    flashtool \
    toolhead-bootloader-stock \
    toolhead-bootloader-upgrade \
    bed-bootloader-stock \
    bed-bootloader-upgrade \
    bed-bootloader-rp2040 \
    htop \
    i2c-tools \
    nano \
    devmem2 \
    swupdate \
    u-boot-fw-utils \
    zram \
    usb-automount \
    dev-by-id \
    psplash \
    opencentauri-bootlogos \
    swu-flasher \
    update-scripts \
    iproute2 \
    chrony \
"

INITRAMFS_IMAGE = "core-image-tiny-initramfs"
INITRAMFS_FSTYPES = "cpio.gz"
INITRAMFS_IMAGE_BUNDLE = "1"
