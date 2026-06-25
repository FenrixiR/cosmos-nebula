inherit cargo update-rc.d

SUMMARY = "TCP Serial Bridge — exposes Cosmos MCU serial devices over TCP for klipper-host Klipper"
HOMEPAGE = "https://github.com/FenrixiR/cosmos-nebula"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://../LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# SRCREV must be updated to the commit that includes tcp-serial-bridge/ in the repo.
# After writing this recipe, commit + push, then update SRCREV to the resulting hash.
#
# Crate entries below are generated on the build machine with:
#   cd tcp-serial-bridge && cargo fetch
#   cargo bitbake   (if cargo-bitbake is installed: cargo install cargo-bitbake)
# OR manually from Cargo.lock:
#   awk '/^\[\[package\]\]/{name=""; ver=""; ck=""} /^name/{name=$3} /^version/{ver=$3}
#        /^checksum/{ck=$3; gsub(/"/,"",name); gsub(/"/,"",ver); gsub(/"/,"",ck);
#        print "    crate://crates.io/"name"/"ver" \\"}' Cargo.lock
# SHA256 checksums:
#   awk '/^\[\[package\]\]/{name=""; ver=""; ck=""} /^name/{name=$3} /^version/{ver=$3}
#        /^checksum/{ck=$3; gsub(/"/,"",name); gsub(/"/,"",ver); gsub(/"/,"",ck);
#        print "SRC_URI["name"-"ver".sha256sum] = \""ck"\""}' Cargo.lock

SRCREV = "REPLACE_WITH_COMMIT_HASH"

SRC_URI = "git://github.com/FenrixiR/cosmos-nebula.git;protocol=https;branch=main \
    file://tcp-serial-bridge.conf \
    file://tcp-serial-bridge-init-d \
    \
    crate://crates.io/PLACEHOLDER/0.0.0 \
"

# Replace the PLACEHOLDER crate line above with the full list generated from Cargo.lock.
# One line per crate: crate://crates.io/<name>/<version> \

S = "${WORKDIR}/git/tcp-serial-bridge"

INITSCRIPT_NAME = "tcp-serial-bridge"
INITSCRIPT_PARAMS = "defaults 95 5"

do_install:append() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/tcp-serial-bridge.conf \
        ${D}${sysconfdir}/tcp-serial-bridge.conf

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/tcp-serial-bridge-init-d \
        ${D}${sysconfdir}/init.d/tcp-serial-bridge
}

FILES:${PN} += " \
    ${sysconfdir}/tcp-serial-bridge.conf \
    ${sysconfdir}/init.d/tcp-serial-bridge \
"

CONFFILES:${PN} = "${sysconfdir}/tcp-serial-bridge.conf"

INSANE_SKIP:${PN} += "already-stripped"
