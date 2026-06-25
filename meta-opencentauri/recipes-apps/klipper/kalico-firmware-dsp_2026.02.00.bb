inherit update-rc.d

HOMEPAGE = "https://kalico.gg/"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=1ebbd3e34237af26da5dc08a4e440464"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = "git://github.com/OpenCentauri/kalico.git;protocol=https;branch=rpmsg-with-new-hx71x \
    file://config.mainboard \
    file://klipper-firmware-dsp-init-d \
"
SRCREV = "afe7178d0859f3cbc80e591473f86ee64183122b"

PR = "r5"

S = "${WORKDIR}/git"

SUMMARY = "Kalico DSP firmware for HiFi4 mainboard MCU"
DESCRIPTION = "Klipper MCU firmware compiled for the AllWinner R528-S3 HiFi4 DSP"

DEPENDS = " \
    python3-native \
    gcc-xtensa-hifi4-elf-native \
"

RPROVIDES:${PN} += "klipper-firmware-dsp"

EXTRA_OEMAKE += " KCONFIG_CONFIG=../config.mainboard"

INITSCRIPT_NAME = "klipper-firmware-dsp"
INITSCRIPT_PARAMS = "defaults 94 4"

INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_SYSROOT_STRIP = "1"

INSANE_SKIP:${PN} = "arch"

do_install() {
    install -d ${D}/lib/firmware
    cp -r ${S}/out/klipper.elf ${D}/lib/firmware/rproc-1700000.dsp-fw

    # Install SysVinit script
    install -d ${D}${sysconfdir}/init.d
    cp ${WORKDIR}/klipper-firmware-dsp-init-d ${D}${sysconfdir}/init.d/klipper-firmware-dsp
    chmod 0755 ${D}${sysconfdir}/init.d/klipper-firmware-dsp
}

FILES:${PN} = " \
    /lib/firmware/rproc-1700000.dsp-fw \
    ${sysconfdir}/init.d/klipper-firmware-dsp \
"
