# Cosmos-Nebula: Upstream Audit

Audit of `meta-opencentauri` as it exists in upstream Cosmos.
Written before any Nebula modifications. All decisions documented here.

**Status legend:**
- `KEEP` — carry forward unchanged
- `ADAPT` — carry forward with modifications
- `REMOVE` — drop entirely
- `MOVE` — functionality moves to DSCS9
- `REPLACE` — drop and replace with new implementation
- `INVESTIGATE` — needs further understanding before deciding

---

## Hardware Reference

| Component | Detail |
|---|---|
| SoC | AllWinner R528-S3 |
| CPU | Dual Cortex-A7 (runs Linux) |
| DSP | Cadence HiFi4 @ 600MHz (runs Klipper mainboard MCU firmware) |
| Mainboard MCU | HiFi4 DSP — `/dev/ttyRPMSG0` |
| Bed MCU | STM32F401 — `/dev/ttyS4`, 250000 baud, reset via GPIO 201 (switched 5V) |
| Toolhead MCU | STM32F401 — `/dev/serial/by-path/platform-4101400.usb-usb-0:1:1.0`, reset via GPIO 140 |
| Bed connector | JST-XHB-5P: pin1=24V(unused), pin2=GND, pin3=5V(switched reset), pin4=TX, pin5=RX |
| Display | RGB888 parallel, driven via U-Boot framebuffer |
| WiFi | AIC8800 or Realtek RTW88 (board-dependent) |
| Serial console | ttyS0 @ 115200 baud |

**Nebula bed MCU change:** Original STM32F401 bed MCU replaced with custom RP2040 board.
RP2040 connects via the same JST-XHB-5P header (UART, not USB). Reset still via GPIO 201 (switched 5V on pin 3).

---

## Partition Layout

From `wic/opencentauri-mmc-image.wks.in`:

| # | Label | FS | Size | Mount | Notes |
|---|---|---|---|---|---|
| — | SPL | raw | — | — | U-Boot SPL, no partition entry |
| p1 | bootlogos | FAT | 6.3MB | `/boot-resource` | U-Boot boot logos |
| p2 | — | raw | 251KB | — | u-boot-initial-env (copy 1) |
| p3 | — | raw | 251KB | — | u-boot-initial-env (copy 2) |
| p4 | bootA | FAT | 6.3MB | — | Kernel + DTB, slot A |
| p5 | — | squashfs | 128MB | `/` | Read-only rootfs, slot A |
| p6 | dsp0A | ext4 | 1MB | — | DSP partition, slot A (purpose: INVESTIGATE) |
| p7 | bootB | FAT | 6.3MB | — | Kernel + DTB, slot B |
| p8 | — | squashfs | 128MB | `/` | Read-only rootfs, slot B |
| p9 | dsp0B | ext4 | 1MB | — | DSP partition, slot B (purpose: INVESTIGATE) |
| p10 | rootfs_data | ext4 | 128MB | `/data` | Writable overlay (overlayfs upper layer) |
| p11 | user | ext4 | 128MB | `/board-resource` | Klipper configs, persistent user data |
| p12 | private | ext4 | 1MB | — | Private data |
| p13 | UDISK | ext4 | ~6.7GB | `/user-resource` | G-code files, thumbnails |

**A/B scheme:** swupdate always writes to the inactive slot (bootX + rootfsX pair).
`systemAB_next` U-Boot env var tracks current slot. `dsp0A`/`dsp0B` are slot-paired but their
exact purpose is unknown — the kernel's remoteproc driver loads DSP firmware from
`/lib/firmware/rproc-1700000.dsp-fw` via standard Linux firmware loader. INVESTIGATE whether
`dsp0A`/`dsp0B` are also used or are legacy from Allwinner's proprietary boot flow.

**Key mounts:**
- `/data` (p10): overlayfs upper layer — `/etc` writes land here, persistent across boots
- `/board-resource` (p11): Klipper printer.cfg, configs, logs. Survives OTA.
- `/user-resource` (p13): G-code files, print queue. Survives OTA.

---

## DSP / RPMSG Architecture

The HiFi4 DSP is managed by a custom Linux remoteproc driver (`sunxi_r528_remoteproc.c`).
Boot sequence:
1. Linux loads ELF firmware from `/lib/firmware/rproc-1700000.dsp-fw`
2. Driver enables DSP clocks, deasserts resets, loads ELF segments into SRAM
3. DSP starts executing Klipper MCU firmware
4. Communication via RPMSG over Allwinner MSGBOX mailbox
5. Kernel presents RPMSG channel as `/dev/ttyRPMSG0`
6. Klipper connects to `/dev/ttyRPMSG0` as `[mcu]`

The DSP firmware is compiled from Kalico source (`rpmsg-with-new-hx71x` branch) using the
Xtensa HiFi4 cross-compiler (`gcc-xtensa-hifi4-elf-native`). This toolchain is a prebuilt
binary that supports both x86_64 and aarch64 host architectures.

**INVESTIGATE:** Role of `serial-multiplexer`. The three MCUs (`/dev/ttyRPMSG0`, `/dev/ttyS4`,
USB path) all appear as standard TTY devices accessible directly to Klipper. The serial-mux
may be unused, experimental, or serving an undocumented role.

---

## MCU Firmware Update Flow (Cosmos)

### Mainboard DSP
- Firmware: `/lib/firmware/rproc-1700000.dsp-fw` (compiled by Yocto, baked into squashfs)
- Update: delivered via swupdate (new squashfs contains new firmware binary)
- Init: `klipper-firmware-dsp-init-d` at priority S94, writes `start` to remoteproc sysfs

### Toolhead MCU (STM32F401)
- GPIO 140: reset control (high=on, low=reset)
- Serial: `/dev/serial/by-path/platform-4101400.usb-usb-0:1:1.0`
- Init script checks installed version vs available version
- If mismatch: flashes new Klipper firmware via `flashtool`
- If flashtool fails: uses `mcu-flasher` to deploy Katapult bootloader, then reflashes
- Firmware binary: `/lib/firmware/klipper-toolhead.bin` + version file

### Bed MCU (STM32F401, being replaced with RP2040)
- GPIO 201: reset control (high=on, low=reset) — same as switched 5V on JST pin 3
- Serial: `/dev/ttyS4` @ 250000 baud
- Reset sequence: `flashtool -r` twice (115200 then 250000 baud) before flashing
- Same version-check + Katapult deployer fallback pattern as toolhead

---

## Component Audit

### recipes-apps

#### atomscreen
Screen UI option. LVGL-based, connects to local Moonraker.
**Decision: REMOVE** — Moonraker moves to DSCS9. One screen app (guppyscreen) is sufficient.

#### camera-led-bridge
Polls local Moonraker for LED case state (`/printer/objects/query?led%20case`),
adjusts camera V4L2 backlight compensation on `/dev/video0`.
**Decision: MOVE** — Camera and Moonraker both live on DSCS9. Run there unchanged.

#### doom
fbdoom with touchscreen support patch and auto-start wrapper.
**Decision: REMOVE**

#### fluidd
Static web UI files + default config. Served by Moonraker.
**Decision: REMOVE** — Moonraker moves to DSCS9. Fluidd runs there.

#### grumyscreen
GrumpyScreen UI option. Python-based, connects to local Moonraker.
**Decision: REMOVE** — One screen app is sufficient.

#### guppyscreen
LVGL/C++ screen UI. Connects to Moonraker via `moonraker_host`/`moonraker_port` in
`/etc/klipper/config/guppyconfig.json`. Has four patches:
- `0001-lv_driver_fb_ioctls.patch` — framebuffer display driver fix
- `0001-Use-printer-data-config-folder.patch` — config path
- `0002-spdlog_fmt_initializer_list.patch` — C++ build fix
- `0003-lvgl-dpi-text-scale.patch` — display scaling
**Decision: KEEP + ADAPT** — Change `moonraker_host` to point at DSCS9 IP (discovered
at runtime via default gateway). All patches stay.

#### helixscreen
Modern Python screen UI. Connects to Moonraker.
**Decision: REMOVE** — One screen app is sufficient.

#### katapult/flashtool
Katapult Python flash tool (`flash_can.py` equivalent). Used to send MCU firmware
over Katapult bootloader protocol via serial.
**Decision: KEEP** — Required for MCU firmware updates from DSCS9 (SSH-triggered).

#### katapult/toolhead-bootloader-stock
Builds Katapult deployer that reverts toolhead to stock STM32 bootloader.
**Decision: KEEP** — Useful for recovery/reverting to stock.

#### katapult/toolhead-bootloader-upgrade
Builds Katapult deployer for toolhead STM32F401.
Config: `config.toolhead` (STM32F401, USB, 48KB offset).
**Decision: KEEP** — Toolhead MCU is unchanged.

#### katapult/bed-bootloader-stock
Builds deployer to revert bed MCU to stock STM32 bootloader.
**Decision: REPLACE** — Original bed MCU is being removed. Replace with RP2040
Katapult firmware build (UART transport, GPIO 201 reset).

#### katapult/bed-bootloader-upgrade
Builds Katapult deployer for original STM32F401 bed MCU.
**Decision: REPLACE** — Same reason as above.

#### klipper/kalico (host app)
`kalico_2026.02.00.bb` — Klipper Python host application.
`klipper_0.13.0.bb` — older Klipper recipe.
**Decision: REMOVE** — Klipper host moves to DSCS9.

#### klipper/kalico-firmware-dsp
`kalico-firmware-dsp_2026.02.00.bb` — Compiles Klipper MCU firmware for the HiFi4 DSP
using `gcc-xtensa-hifi4-elf-native`. Installs to `/lib/firmware/rproc-1700000.dsp-fw`.
Init script at S94 triggers remoteproc load.
**Decision: KEEP** — The DSP is physically inside the R528-S3. Its firmware must live
on Cosmos and be loaded by Cosmos's kernel regardless of where the Klipper host runs.
DSP firmware version must match Klipper host version on DSCS9 — keep in sync.

#### klipper/kalico-firmware-bed
Compiles Klipper MCU firmware for STM32F401 bed MCU.
**Decision: REMOVE** — Bed MCU replaced by RP2040. RP2040 Klipper firmware compiled
on DSCS9 using standard `make` + Xtensa toolchain, pushed to Cosmos via SSH for flashing.

#### klipper/kalico-firmware-toolhead
Compiles Klipper MCU firmware for STM32F401 toolhead MCU.
**Decision: REMOVE** — Klipper MCU firmware compilation moves to DSCS9 for all external
MCUs. DSCS9 compiles, SCPs binary to Cosmos, triggers `flashtool` via SSH.

#### klipper/klipper-firmware-dsp-init-d
Remoteproc sysfs init script. Writes `start`/`stop` to `/sys/class/remoteproc/remoteproc0/state`.
**Decision: KEEP** — Required for DSP firmware loading at boot.

#### klipper/klipper-firmware-toolhead-init-d
Checks toolhead firmware version, flashes if mismatch. Uses GPIO 140 for reset, Katapult flashtool.
**Decision: KEEP + ADAPT** — Firmware binary no longer compiled on Cosmos. Instead of
checking a local version file, this script will be adapted to be triggered externally
(SSH call from DSCS9) rather than running automatically at boot.

#### klipper/klipper-firmware-bed-init-d
Same pattern as toolhead. GPIO 201, `/dev/ttyS4`, 250000 baud.
**Decision: REPLACE** — Rewrite for RP2040. GPIO 201 and `/dev/ttyS4` stay the same.
Reset mechanism (power-cycle via GPIO 201) stays. Katapult UART flash protocol instead
of Ymodem/mcu-flasher fallback.

#### klipper/printer.cfg, machine.cfg, macros.cfg, etc.
Klipper configuration files.
**Decision: REMOVE from Cosmos** — Klipper config lives on DSCS9. The existing `machine.cfg`
is a valuable hardware reference document and is preserved in `docs/` for reference.

#### klipper/patches (Python host patches)
Four patches for Klipper Python host: log rotation, tmp file locations, save-config check,
calibration tolerance (load cell specific).
**Decision: NOT NEEDED for DSP firmware build** — These patches only affect Python host code.
The DSP firmware build only compiles C MCU firmware. Patches stay in the recipe for reference
but do not need to be applied to the DSP-only build.

#### lzbench
Compression benchmark tool.
**Decision: REMOVE**

#### mainsail
Klipper web UI static files.
**Decision: REMOVE** — Runs on DSCS9.

#### mcu-flasher
Elegoo-specific Ymodem protocol flasher. Used as a fallback in the toolhead/bed init
scripts when Katapult deployer needs to be flashed (requires original Elegoo bootloader).
**Decision: KEEP** — Still needed for toolhead bootloader upgrade fallback path.
May also be needed for initial RP2040 provisioning if UART boot is used.

#### mjpg-streamer
Camera streaming via HTTP MJPEG.
**Decision: REMOVE** — Camera moves to DSCS9.

#### moonraker
Klipper API/WebSocket server.
**Decision: REMOVE** — Moves to DSCS9.

#### screen-actions (`uiprompt`, `uiclear`)
Shell scripts that send `_SHOW_PROMPT` / `_HIDE_PROMPT` G-code via local Moonraker HTTP.
**Decision: REMOVE** — Moonraker moves to DSCS9. Klipper macros running on DSCS9 would
need to call these scripts remotely. Guppyscreen gets all its state from Moonraker directly,
so this mechanism is redundant.

#### serial-multiplexer
Rust binary. Described as "Send multiple serial devices over a single serial."
Creates PTY pairs in `/tmp/vtty/` named per config entry.
**Decision: INVESTIGATE** — The three MCUs connect directly as standard TTY devices
(`/dev/ttyRPMSG0`, `/dev/ttyS4`, USB). It is unclear if the serial-mux is actually used
in the current Cosmos setup. Must understand its role before deciding. If unused, REMOVE.
If used, understand why before adapting.

#### ustreamer
HTTP MJPEG camera streamer with retry-on-bind patch.
**Decision: REMOVE** — Camera moves to DSCS9.

---

### recipes-bsp

#### u-boot
Custom U-Boot for R528-S3 with: elegoo-centauri-carbon1 device tree, display support
(RGB888 with R/B channel swap), AC remap fix, framebuffer size reduction.
**Decision: KEEP** — Bootloader. Do not modify unless absolutely necessary.

---

### recipes-core

#### base-files
fstab and MOTD.
**Decision: KEEP + ADAPT** — Update MOTD from OpenCentauri branding to Cosmos-Nebula.
fstab partition mounts stay the same.

#### busybox
BusyBox with NTP client, `ip`, and `tree` enabled.
**Decision: KEEP**

#### dev-by-id
udev rule `99-dev-by-id.rules` creating `/dev/serial/by-id/` symlinks.
**Decision: KEEP** — Required for stable device paths.

#### init-ifupdown
`/etc/network/interfaces` — wlan0 DHCP with `post-up iw dev wlan0 set power_save off`,
eth0 DHCP, USB gadget static IP, Bluetooth (bnep0).
**Decision: ADAPT** — Remove eth0, USB gadget, and Bluetooth entries.
wlan0 stays as DHCP client. wpa_supplicant.conf will be generated from nebula config.
The `post-up power_save off` line is already correct.

#### psplash
Boot splash screen with Cosmos artwork.
**Decision: KEEP + ADAPT** — Replace artwork with Cosmos-Nebula branding later. Functional
behaviour unchanged.

#### swu-flasher
`flash` script: A/B swupdate with `systemAB_next` env var logic.
`readonly-config-reset`: resets read-only config overlay on update.
**Decision: KEEP** — Core OTA infrastructure, do not modify.

#### sysvinit
SysVinit customization bbappend.
**Decision: KEEP**

#### usb-automount
udev rule + `usb-mount` script. On USB insert:
1. Copies `wpa_supplicant.conf` from USB (WiFi config update path)
2. Copies `.gcode` files to `/user-resource`
3. Installs `emergency.swu` (emergency firmware update)
The emergency path checks for `dsp0_partition` in the SWU and calls `restore-mcu-firmware`
first if present.
**Decision: KEEP + ADAPT** — Remove `copy_gcode_files` (G-code management moves to DSCS9).
Keep WiFi config copy and emergency firmware paths. Adapt `uiprompt` calls to not depend
on local Moonraker.

#### zram
RAM compression + eMMC swap.
**Decision: KEEP**

---

### recipes-data

#### config-manager
Python config manager. Reads/writes `/etc/klipper/config/cosmos.conf`.
Manages: `ui.screen_ui`, `ui.web_ui`, `ui.screen_brightness`, `update.release`,
`klipper.*` (camera LED sync, bypass calibration, temperatures).
**Decision: ADAPT** — Remove `klipper.*` section (Klipper config moves to DSCS9).
Remove `ui.web_ui` (no local web UI). Keep `ui.screen_ui` (guppyscreen/none),
`ui.screen_brightness`, `update.release`. Rename config key from `cosmos.conf` to
`nebula.conf` or integrate with `nebula.toml`.

#### config-switcher / gui-switcher
Reads `config-manager ui screen_ui`, starts selected GUI init script, sets brightness.
Finishes psplash, then launches screen UI.
**Decision: KEEP + ADAPT** — Valid options become `guppyscreen` and `none` only.
Remove atomscreen/grumpyscreen from valid values.

#### opencentauri-bootlogos
Boot logo BMP files displayed by U-Boot.
**Decision: KEEP + ADAPT** — Replace artwork with Cosmos-Nebula branding later.
Mechanism unchanged.

#### support-zip
Generates support zip with system logs and diagnostics.
**Decision: KEEP** — Useful for debugging.

#### update-scripts
Collection of maintenance scripts:
- `factory-reset` — touches `/data/.factory-reset`, reboots. **KEEP**
- `update-cosmos` — downloads OTA from OpenCentauri GitHub releases. **ADAPT** — point at nebula release infrastructure
- `restore-mcu-firmware` — flashes stock bootloaders to bed + toolhead. **ADAPT** — bed changes to RP2040
- `flash-artifact.py` — flashes individual SWU artifacts. **KEEP**
- `switch-to-oc-patched` / `switch-to-stock` — switches between firmware variants. **INVESTIGATE**
- `swu-decrypt.py` — SWU decryption helper. **KEEP**

---

### recipes-devtools

#### external-hifi4-toolchain
Prebuilt Xtensa HiFi4 ELF cross-compiler. Supports x86_64 and aarch64 hosts.
Required for DSP firmware compilation.
**Decision: KEEP**

#### python3 bbappend
Python3 customization.
**Decision: KEEP** — Required for DSP firmware build system.

---

### recipes-kernel

#### aic8800
Out-of-tree WiFi driver for AIC8800 chipset.
**Decision: KEEP**

#### linux
Kernel with patches for:
- elegoo-centauri-carbon1 device tree
- R528 remoteproc + RPMSG (HiFi4 DSP support) — custom `sunxi_r528_remoteproc.c` and `sunxi-r528-msgbox.c`
- RGB888 display with R/B channel swap
- Allwinner PWM driver
- Thermal driver
- squashfs + overlayfs config
- USB net adapters
**Decision: KEEP** — Do not modify kernel unless there is a specific need.

#### rtw88
Out-of-tree Realtek WiFi driver with LED disabled patch.
**Decision: KEEP**

---

### recipes-python

All packages are dependencies of Moonraker (Python ASGI server stack) or Klipper host:
`tornado`, `uvloop`, `msgspec`, `apprise`, `inotify-simple`, `streaming-form-data`,
`preprocess-cancellation`, `smart-open`, `ldap3`, `libnacl`, `importlib-metadata`.

**Decision: REMOVE ALL** — Moonraker and Klipper host move to DSCS9.

---

### recipes-support

#### allwinner-ota-burnboot
Allwinner bootloader burning support for OTA.
**Decision: KEEP**

#### swupdate
SWUpdate with custom `awboot` handler (Allwinner boot partition update), RSA signing,
hardware revision check.
**Decision: KEEP** — Core OTA infrastructure.

---

### images

#### opencentauri-image-base.bb
Defines `CORE_IMAGE_EXTRA_INSTALL`. This is the primary list to adapt.
**Decision: ADAPT** — Remove Klipper stack, camera, unused UIs. Add nebula-specific recipes.

#### opencentauri-image-mmc.bb
eMMC image with read-only rootfs + overlayfs-etc + package management.
**Decision: KEEP + ADAPT** — Rename description. Extend overlayfs to cover `/lib/firmware`.

#### opencentauri-image-usb.bb
USB install trigger image.
**Decision: KEEP** — Install mechanism unchanged.

#### opencentauri-upgrade.bb
Builds signed `.swu` OTA package with: squashfs rootfs, bootA partition, bootlogos, U-Boot.
RSA signed with private key.
**Decision: KEEP + ADAPT** — Generate new RSA keypair for Nebula builds.

#### overlayfs-etc-preinit.sh.in
Preinit script: mounts `/data`, sets up overlayfs for `/etc`.
**Decision: ADAPT** — Extend to also overlay `/lib/firmware` so DSP firmware can be
updated from DSCS9 without a Yocto rebuild.

---

## Open Questions (INVESTIGATE items)

1. **serial-multiplexer actual role** — Are the MCU TTY devices (`/dev/ttyRPMSG0`, `/dev/ttyS4`, USB path) used directly by Klipper, or does the serial-mux sit in between? If the mux creates PTY devices that Klipper actually connects to, the tcp-serial-bridge approach works. If Klipper connects to the real TTY devices directly, the bridge approach is different.

2. **dsp0A / dsp0B partitions** — What are they for? The kernel's remoteproc driver loads DSP firmware from `/lib/firmware` via the standard firmware loader. Are these partitions used at all in the Cosmos kernel/U-Boot, or are they legacy from Allwinner's proprietary firmware?

3. **switch-to-oc-patched / switch-to-stock** — What do these do? Are they relevant to Nebula?

4. **klipper-firmware-toolhead-init-d adaptation** — In Nebula, toolhead MCU firmware is compiled on DSCS9 and pushed to Cosmos. Define the exact SSH-triggered workflow for MCU firmware updates.

---

## Infrastructure Decisions (to establish before any changes)

These need to be agreed upon before we start modifying recipes:

1. **TCP bridge strategy for MCU access from DSCS9**
2. **WiFi configuration approach** (nebula.toml → generated wpa_supplicant.conf)
3. **DSP firmware update workflow** (DSCS9 → SCP to `/lib/firmware` → remoteproc restart)
4. **External MCU firmware update workflow** (DSCS9 compile → SCP to Cosmos → flashtool via SSH)
5. **OTA update infrastructure** (release channels, signing keys)
6. **Screen UI configuration** (guppyscreen only, config via nebula.toml)
7. **Writable overlay scope** (`/etc` already, extend to `/lib/firmware`)
