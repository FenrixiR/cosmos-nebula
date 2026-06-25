# Cosmos-Nebula Configuration Reference

Cosmos-Nebula uses a single file, `/etc/nebula.toml`, as the central configuration
for all environment-specific settings. Edit this file on Cosmos and reboot — all
dependent config files are regenerated automatically at boot.

---

## /etc/nebula.toml

### Location and persistence

- **Path:** `/etc/nebula.toml`
- **Lives on:** the writable overlayfs upper layer (`/data`), not the read-only squashfs
- **Survives:** OTA firmware updates (the overlayfs layer is preserved across A/B swaps)
- **Edit via:** SSH from DSCS9 — `ssh root@cosmos-nebula nano /etc/nebula.toml`

After editing, reboot Cosmos:

```sh
reboot
```

### Reference

```toml
[wifi]
ssid     = "cosmos-nebula"   # SSID of the DSCS9 access point
password = "CHANGE_ME"       # WPA2-PSK passphrase

[bridge]
mainboard_port = 7001        # Mainboard DSP MCU (ttyRPMSG0)
bed_port       = 7002        # Bed MCU (ttyS4, STM32F401 or RP2040)
toolhead_port  = 7003        # Toolhead MCU (USB serial)

[ntp]
server = "192.168.4.1"       # NTP server — DSCS9's WiFi interface IP
```

### What gets generated

nebula-init runs at SysVinit priority S02 (before networking) and generates:

| File | From section | Notes |
|---|---|---|
| `/etc/wpa_supplicant.conf` | `[wifi]` | Used by wlan0 to connect to DSCS9 AP |
| `/etc/tcp-serial-bridge.conf` | `[bridge]` | Read by tcp-serial-bridge at S95 |
| `/etc/chrony.conf` | `[ntp]` | chrony connects to NTP server post-network |

Do not edit the generated files directly — they are overwritten on every boot.

---

## WiFi setup

Cosmos connects to DSCS9 as a WiFi client (DSCS9 runs hostapd as an AP).

**First boot / initial WiFi setup:**

1. Insert a USB drive containing a valid `wpa_supplicant.conf` file. Cosmos will copy
   it automatically on USB insertion (the usb-automount mechanism).

2. Then SSH into Cosmos and update `/etc/nebula.toml` with the same credentials so
   they persist across reboots:

   ```sh
   nano /etc/nebula.toml
   # set wifi.ssid and wifi.password
   reboot
   ```

**Changing WiFi credentials:**

Edit `/etc/nebula.toml` → change `[wifi]` section → reboot. The USB wpa_supplicant.conf
drop mechanism is still available as a recovery path if Cosmos cannot connect.

---

## TCP Serial Bridge

The `tcp-serial-bridge` daemon exposes each MCU serial port as a TCP socket so
DSCS9's Klipper can connect remotely.

### Default port assignments

| MCU | Serial device | Port |
|---|---|---|
| Mainboard DSP (HiFi4) | `/dev/ttyRPMSG0` | 7001 |
| Bed MCU (STM32F401 or RP2040) | `/dev/ttyS4` | 7002 |
| Toolhead MCU (STM32F401, USB) | `/dev/serial/by-path/platform-4101400.usb-usb-0:1:1.0` | 7003 |

### DSCS9 printer.cfg connection strings

```ini
[mcu]
serial: socket://cosmos-nebula:7001

[mcu toolhead]
serial: socket://cosmos-nebula:7003

# For STM32F401 bed MCU (original):
[mcu bed]
serial: socket://cosmos-nebula:7002

# For RP2040 bed MCU (custom Klicky/servo board):
[mcu rp2040_bed]
serial: socket://cosmos-nebula:7002
```

Only one bed MCU definition should be active at a time — comment out the one not in use.

### Changing ports

Edit `[bridge]` in `/etc/nebula.toml`, reboot Cosmos, and update the corresponding
`serial:` lines in DSCS9's `printer.cfg`.

---

## Bed MCU: RP2040 Klicky probe board

The custom RP2040-Zero bed MCU replaces the original Elegoo STM32F401 bed MCU.
Both are supported; the active choice is made in DSCS9's `printer.cfg` (above).

### RP2040 GPIO assignments

| Signal | GPIO |
|---|---|
| UART0 TX (to Cosmos ttyS4 RX) | GP0 |
| UART0 RX (from Cosmos ttyS4 TX) | GP1 |
| Servo PWM (MG90S swing arm) | GP2 |
| Klicky probe contact | GP3 |
| Onboard WS2812 LED | GP16 (reserved) |

### Klipper config for RP2040 bed MCU

```ini
[mcu rp2040_bed]
serial: socket://cosmos-nebula:7002

[servo klicky_servo]
pin: rp2040_bed:gpio2
maximum_servo_angle: 180
minimum_pulse_width: 0.0005   # 0.5ms = 0 degrees
maximum_pulse_width: 0.0025   # 2.5ms = 180 degrees

[probe]
pin: ^!rp2040_bed:gpio3       # pulled up, active low (Klicky contact = GND)
speed: 5
lift_speed: 10
samples: 3
```

### Initial RP2040 provisioning (one-time)

The RP2040 must have the Katapult bootloader flashed before Klipper can update it
over UART. The Katapult UF2 is available at `/lib/firmware/katapult-rp2040-bed.uf2`
on Cosmos.

1. Copy the UF2 from Cosmos to your workstation:
   ```sh
   scp root@cosmos-nebula:/lib/firmware/katapult-rp2040-bed.uf2 .
   ```
2. Hold the BOOTSEL button on the RP2040-Zero, then power-cycle it via GPIO 201
   (or disconnect and reconnect the JST connector with BOOTSEL held).
3. The RP2040 appears as a USB mass storage device (`RPI-RP2`).
4. Copy the UF2 to the mounted drive — the RP2040 reboots into Katapult automatically.

After this, all subsequent Klipper firmware updates happen automatically from DSCS9
over UART via the tcp-serial-bridge.

### Emergency RP2040 recovery

If Katapult becomes corrupted, repeat the provisioning steps above. The RP2040's
UF2 bootloader lives in mask ROM and cannot be overwritten — BOOTSEL always works.

---

## MCU firmware management

Firmware for external MCUs (toolhead STM32F401, bed STM32F401 or RP2040) is compiled
on DSCS9 and pushed to Cosmos via SSH. Cosmos only handles power-on/reset via GPIO.

### Toolhead MCU firmware update (from DSCS9)

```sh
# On DSCS9:
cd ~/klipper
make KCONFIG_CONFIG=config.toolhead
scp out/klipper.bin root@cosmos-nebula:/lib/firmware/klipper-toolhead.bin

# Power-cycle toolhead MCU (enters Katapult window):
ssh root@cosmos-nebula "/etc/init.d/klipper-firmware-toolhead restart"

# Flash via Katapult:
python3 scripts/flash_can.py -d /dev/ttyACM0  # adjust device
# OR use flashtool directly on Cosmos:
ssh root@cosmos-nebula "flashtool -d /dev/serial/by-path/platform-4101400.usb-usb-0:1:1.0 \
    -f /lib/firmware/klipper-toolhead.bin"
```

### DSP (mainboard MCU) firmware update (from DSCS9)

The DSP firmware is compiled as part of the Yocto image but can be updated without
a full reflash by placing a new binary at `/lib/firmware/rproc-1700000.dsp-fw`
(the overlayfs `/lib/firmware` mount makes this writable):

```sh
# On DSCS9, after building Klipper for HiFi4:
scp out/klipper.elf root@cosmos-nebula:/lib/firmware/rproc-1700000.dsp-fw
ssh root@cosmos-nebula "/etc/init.d/klipper-firmware-dsp restart"
```

DSP firmware version must be kept in sync with the Klipper host version on DSCS9.

---

## Reverting to stock / OC-patched firmware

To revert Cosmos to the original Elegoo firmware or OpenCentauri firmware:

```sh
# On Cosmos:
switch-to-stock          # download and flash stock Elegoo firmware
switch-to-oc-patched     # download and flash OpenCentauri firmware
```

These scripts call `restore-mcu-firmware` which flashes stock bootloaders to the
toolhead MCU and (if applicable) the STM32F401 bed MCU. RP2040 bed MCU users:
your hardware-modified bed will not function under stock firmware — this is expected.

---

## Boot sequence (SysVinit priorities)

| Priority | Service | What it does |
|---|---|---|
| S02 | `nebula-init` | Generates wpa_supplicant.conf, tcp-serial-bridge.conf, chrony.conf |
| S21 | `zram-emmc-swap` | RAM compression + swap |
| ~S40 | networking | wlan0 connects to DSCS9 AP using generated wpa_supplicant.conf |
| S94 | `klipper-firmware-dsp` | Loads HiFi4 DSP firmware via remoteproc |
| S94 | `klipper-firmware-toolhead` | Powers on toolhead MCU (GPIO 140) |
| S94 | `klipper-firmware-bed` | Powers on bed MCU (GPIO 201) |
| S95 | `tcp-serial-bridge` | Bridges MCU serial ports to TCP sockets |
| S96 | `gui-switcher` → `guppyscreen` | Discovers DSCS9 gateway, starts screen UI |
