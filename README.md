# modemmanager-meig-asr

ModemManager plugins for ASR-based MeiG modems, packaged for **Raspberry Pi OS**.
They make the **Teltonika TRM200** USB LTE modem (MeiG SLM770A inside) work with
ModemManager and NetworkManager: the modem is detected correctly, connects via a
normal NetworkManager `gsm` connection, and reconnects on its own.

## Target system

| | |
|---|---|
| OS | Raspberry Pi OS (64-bit) **trixie** (Debian 13), tested with **Raspberry Pi OS Lite, release 2026-09-15** ([`2026-09-15-raspios-trixie-arm64-lite.img.xz`](https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-09-15/)) |
| Architecture | `arm64` only |
| ModemManager | `modemmanager 1.24.0-1+deb13u1` from Debian trixie (also what Raspberry Pi OS trixie installs) |

The package adds plugins to ModemManager's plugin directory. Debian's
`modemmanager` package stays unchanged. Because the plugins use
ModemManager-internal symbols, each release works with **exactly one**
`modemmanager` version, see [Compatibility and updates](#compatibility-and-updates).

## Supported devices

| USB ID | Device | Plugin |
|---|---|---|
| `2dee:4d57` | MeiG SLM770A, RNDIS mode (`AT+SER=3`), e.g. **Teltonika TRM200** as shipped | `meig-asr` |
| `2dee:4d58` | MeiG SLM770A, ECM mode (`AT+SER=2`) | `meig-asr` |
| `1d12:0102` | Teltonika ALA440 (untested) | `teltonika-meig-asr` |

## Installation

Download the `.deb` for your release from the
[releases page](https://github.com/trackIT-Systems/modemmanager-meig-asr/releases)
and install it with apt, which also installs ModemManager if it isn't installed yet:

```sh
sudo apt install ./modemmanager-meig-asr_<version>_arm64.deb
```

The package reloads the udev rules and restarts ModemManager. Re-plug the modem
(or reboot) so it's picked up with the new udev rules.

Check that the plugin handles the modem:

```sh
mmcli -L                      # [MEIG INCORPORATED] SLM770A
mmcli -m any | grep plugin    # plugin: meig-asr
```

Then create a NetworkManager connection with your SIM's APN:

```sh
sudo nmcli connection add type gsm ifname '*' con-name cellular apn <your-apn>
```

NetworkManager connects automatically. The modem's network interface
(`usb0`) gets an address by DHCP.

> [!IMPORTANT]
> **The plugin changes the modem's stored configuration.** It turns the
> modem's auto-dial off (`AT+DIALMODE=1`). A factory-new TRM200 dials on its
> own at power-on; after the plugin has run, it no longer does, even after
> this package is removed or the modem is used on another host. To restore
> auto-dial, send `AT+DIALMODE=0`. See [docs/TRM200.md](docs/TRM200.md#the-plugin-changes-the-modems-configuration).

### In image builds

The package can be installed in a chroot, e.g. with
[pi-gen](https://github.com/RPi-Distro/pi-gen) or
[pimod](https://github.com/Nature40/pimod). Without a running systemd, the
package scripts do nothing. Example for a pimod `Pifile`:

```sh
MM_MEIG_ASR_VERSION=1.24.0-1
RUN sh -c "curl -fsSL -o /tmp/modemmanager-meig-asr.deb https://github.com/trackIT-Systems/modemmanager-meig-asr/releases/download/${MM_MEIG_ASR_VERSION}/modemmanager-meig-asr_${MM_MEIG_ASR_VERSION}_arm64.deb"
RUN apt-get install -y /tmp/modemmanager-meig-asr.deb
RUN rm /tmp/modemmanager-meig-asr.deb
```

`apt-get install` fails the build if the image's `modemmanager` isn't the
version the release was built for.

## Compatibility and updates

The package depends on the exact `modemmanager` and `libmm-glib0` version it
was built against, e.g. `modemmanager (= 1.24.0-1+deb13u1)`. apt refuses to
install it next to any other ModemManager version, and the plugins can't end up
loaded into a ModemManager they don't fit.

When Debian publishes a new `modemmanager` for trixie:

* `apt upgrade` holds the new `modemmanager` back.
* `apt full-upgrade` would remove this package to install it.

Wait for a release of this repository for the new version, or build one (see
[Maintenance](#maintenance)). Check the installed version with
`apt-cache policy modemmanager`.

## Hardware notes

* **Raspberry Pi 5 power:** with a power supply that doesn't negotiate 5 A, the
  Pi 5 limits all USB ports together to 600 mA. Under data load the USB power
  switch then trips (`over-current change` on all ports in the kernel log) and
  the modem re-enumerates. ModemManager and NetworkManager recover on their own
  within ~40 s, but the connection drops each time. **Use the 5 A (27 W)
  supply** (the USB limit is then lifted automatically, `usb_max_current_enable=1`)
  or a powered USB hub.
* **RNDIS or ECM:** the TRM200 ships in RNDIS mode (`rndis_host`), which works
  out of the box. Switching to ECM (`cdc_ether`) is persistent and reboots the
  modem: `AT+SER=2,1` for ECM, `AT+SER=3,1` back to RNDIS. The kernel's `option`
  driver only knows the RNDIS ID; for ECM, the package's udev rule
  `70-meig-slm770a-ecm-option.rules` adds `2dee:4d58` so the AT ports come up.
* **Port layout** (both modes): interface 2 ASR diagnostics (ignored),
  interface 3 primary AT port, interface 4 secondary AT port, interface 5 GPS.
* **Addresses:** the modem's DHCP server identifies itself as `169.254.0.1`, but
  the router it hands out is in the carrier network (e.g. a /29), so it doesn't
  clash with link-local setups on other interfaces.

More hardware and firmware details (USB boot stage, dial settings, `+ECMDUP`
quirks, unsupported AT commands, how to test a change) are in
[docs/TRM200.md](docs/TRM200.md).

## Background

Stock ModemManager 1.24 handles the SLM770A with its generic plugin, which
can't connect:

* `AT+WS46=?` returns `ERROR`, so ModemManager thinks the modem has no LTE,
  never queries `+CEREG`, and reports the packet service as *detached* on LTE.
* `ATZ` returns `ERROR`, so enabling fails whenever the modem was already
  attached when ModemManager started (e.g. at boot).
* The generic plugin can't bring up the RNDIS/ECM network interface.

The ASR, MeiG and Teltonika plugins come from
[ModemManager MR !1502](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/merge_requests/1502).
`patches/` backports them to ModemManager `1.24.0` and fixes what testing on a
TRM200 turned up:

| Patch | Source |
|---|---|
| 0001–0004 | MR !1502 ("Add support for Teltonika -> MeiG -> ASR modems", by lvoegl, commit `0076a216`), backported from `main` to 1.24.0 |
| 0005 | plugin-private copy of `mm_3gpp_normalize_address()`, which only exists in ModemManager `main` and isn't exported by the 1.24 daemon |
| 0006 | adds the RNDIS variant `2dee:4d57` (TRM200) |
| 0007 | `MM_DEFINE_SHARED` for `shared-asr`/`shared-meig`. The MR lacks it, so these modules don't load unless plugins are built into the daemon |
| 0008 | skips the `ATZ` init, which the modem answers with `ERROR` |
| 0009 | MeiG modems dial and hang up with `+ECMDUP` and report the connection status from `+ECMDUP?` |

Why `+ECMDUP` instead of `+CGACT` (as in the MR), tested on firmware
`SLM770A_A.57.3_EQ102`:

* A context activated with `+CGACT` isn't routed to the network interface.
  NetworkManager reported a connection with a valid DHCP lease, but no traffic
  passed.
* `+ECMDUP=<cid>,1,<pdp type>,"<apn>"` activates the context itself and connects
  it. Activating it with `+CGACT` first makes the following `+ECMDUP` fail.
* `+ECMDUP=<cid>,0` disconnects the interface; the LTE default bearer stays
  active, so `+CGACT?` can't show a dropped connection, while `+ECMDUP?` can.

`build.sh` also makes `libmm-shared-meig.so` depend on `libmm-shared-asr.so`
(`DT_NEEDED` + `RUNPATH=$ORIGIN`): ModemManager opens shared modules in
directory order with immediate binding, so `shared-meig` would otherwise fail
whenever it happens to be opened first.

The backport leaves daemon code untouched; only `src/plugins/` and the build
files change. Debian's `1.24.0-1+deb13u1` only patches the Fibocom plugin, so
upstream `1.24.0` is ABI-identical to it.

The [MeiG SLM770A AT command manual](https://wiki.teltonika-networks.com/images/a/a9/MeiG_SLM770A_AT_Commands_Manual_TRM200.pdf)
is published by Teltonika.

## Status

Tested on a Teltonika TRM200 (firmware `SLM770A_A.57.3_EQ102`) on a Raspberry Pi 5
running Raspberry Pi OS Lite 2026-09-15 (arm64) with `modemmanager 1.24.0-1+deb13u1`:

* The `meig-asr` plugin claims the modem in both RNDIS and ECM mode. The modem
  reports LTE, the packet service is attached, and NetworkManager connects with
  a `gsm` connection that only sets the APN.
* IPv4 traffic works (ping, HTTPS). A 2 MB download ran at ~4.7 Mbit/s over ECM
  and ~3.8 Mbit/s over RNDIS (single samples, LTE Cat 1, roaming).
* With data checked after each step: 5 of 5 NetworkManager disconnect/reconnect
  cycles, a ModemManager restart and a USB re-plug (RNDIS mode).
* A connection dropped by the modem was detected within ~10 s; NetworkManager
  reconnected and data flowed again ~15 s after the drop.
* Enabling works at hot-plug, at boot, after a ModemManager restart and after
  inhibition.

Known issues:

* The `+ECMDUP` dialing (patch 0009) was only tested in RNDIS mode; ECM mode
  was tested with the earlier `+CGACT` dialing.
* The GPS port is reported as unhandled; there's no location support yet.
* No global IPv6 address on the network interface with an `ipv4v6` connection
  (tested with one carrier only).

## Maintenance

### Building

On Raspberry Pi OS or Debian trixie, arm64 (or in a `debian:trixie` container):

```sh
apt-get install --no-install-recommends \
  build-essential ca-certificates dpkg-dev git gettext \
  meson ninja-build pkg-config patchelf python3 xsltproc \
  libdbus-1-dev libglib2.0-dev libgudev-1.0-dev \
  libmbim-glib-dev libqmi-glib-dev libqrtr-glib-dev \
  libpolkit-gobject-1-dev libsystemd-dev systemd-dev modemmanager
./build.sh
./check-symbols.sh
```

`build.sh` fetches the ModemManager release pinned in `versions.env`, applies
`patches/`, builds only the plugin targets and packages
`dist/modemmanager-meig-asr_<version>_arm64.deb` with:

```
usr/lib/aarch64-linux-gnu/ModemManager/libmm-plugin-meig-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-plugin-teltonika-meig-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-shared-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-shared-meig.so
usr/lib/udev/rules.d/70-meig-slm770a-ecm-option.rules
usr/lib/udev/rules.d/77-mm-meig-port-types.rules
usr/lib/udev/rules.d/77-mm-teltonika-port-types.rules
usr/share/doc/modemmanager-meig-asr/{README.md,TRM200.md,copyright,changelog.Debian.gz}
```

It refuses to run if `build/` exists; remove it for a fresh build.

`check-symbols.sh` verifies that every ModemManager symbol the plugins import is
exported by the installed `modemmanager`/`libmm-glib0`, and that the modules
export what ModemManager's loader requires. CI runs it on every build and
test-installs the package on Debian trixie with the Raspberry Pi OS archive
(`archive.raspberrypi.com`) enabled, i.e. the package set of Raspberry Pi OS
trixie.

### When Debian updates ModemManager

1. Update `MM_TAG`, `MM_COMMIT` and `MM_DEBIAN_VERSION` in `versions.env`.
   Check `debian/patches` of the new Debian version for changes outside
   `src/plugins/`.
2. Rebase `patches/` if needed (`git am` onto the new tag, then
   `git format-patch -N --zero-commit --no-signature <tag>..HEAD`).
3. Build, test on hardware, and release (see below).

Once MR !1502 is merged and shipped by Debian, this repository is obsolete.

### Versioning

Releases are tagged `<ModemManager version>-<revision>`, like Debian package
revisions. The tag is also the package version:

```
1.24.0-1   first release for ModemManager 1.24.0
1.24.0-2   our own changes (fixes, new USB IDs, ...) or a Debian-only update
           of ModemManager 1.24.0 (e.g. +deb13u2), still for 1.24.0
1.26.0-1   rebuilt for ModemManager 1.26.0, revision starts again at 1
```

The exact Debian ModemManager version is in `versions.env` and in the package's
`Depends`. Tags have no `v` prefix.

Untagged builds (CI on `main`, local builds) get
`<ModemManager version>-0~git<date>.<commit count>.<commit>`, e.g.
`1.24.0-0~git20261007.10.e814430`, which apt sorts before the first release.
Builds are only distinguishable by version once committed: rebuilding with
uncommitted changes reuses the version, and apt won't reinstall it.

### Releasing

Add a `## [<tag>]` section to `CHANGELOG.md`, then push the tag. CI builds the
arm64 `.deb` and attaches it to a GitHub (pre)release.

## License

GPL-2.0-or-later, like ModemManager's plugins.
