require katapult_${PV}.inc

SUMMARY = "Katapult bootloader for RP2040 bed MCU (UART, 16KiB offset)"
DESCRIPTION = "Builds the Katapult UF2 for the custom RP2040-Zero bed MCU. \
Used for initial provisioning via BOOTSEL: hold BOOTSEL on the RP2040-Zero \
while power-cycling via GPIO 201, mount as USB mass storage, copy the UF2. \
Subsequent Klipper firmware updates use flashtool over UART from klipper-host."

SRC_URI += " \
    file://config.rp2040-bed \
"

DEPENDS += "gcc-arm-none-eabi-native"

EXTRA_OEMAKE += "KCONFIG_CONFIG=../config.rp2040-bed"

do_install() {
    install -d ${D}/lib/firmware
    install -m 0644 ${S}/out/katapult.uf2 \
        ${D}/lib/firmware/katapult-rp2040-bed.uf2
}

FILES:${PN} = "/lib/firmware/katapult-rp2040-bed.uf2"
