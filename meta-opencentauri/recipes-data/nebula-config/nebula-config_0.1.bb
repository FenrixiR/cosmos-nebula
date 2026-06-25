DESCRIPTION = "Cosmos-Nebula central configuration and boot-time config generator"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

SRC_URI = " \
    file://nebula.toml \
    file://nebula-init \
"

inherit update-rc.d

INITSCRIPT_NAME = "nebula-init"
INITSCRIPT_PARAMS = "defaults 02 98"

do_install() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/nebula.toml ${D}${sysconfdir}/nebula.toml

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/nebula-init ${D}${sysconfdir}/init.d/nebula-init
}

FILES:${PN} = " \
    ${sysconfdir}/nebula.toml \
    ${sysconfdir}/init.d/nebula-init \
"

CONFFILES:${PN} = "${sysconfdir}/nebula.toml"
