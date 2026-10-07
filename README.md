# modemmanager-meig-asr

ModemManager plugins for ASR-based MeiG modems, packaged for
[tsOS](https://github.com/trackIT-Systems/tsOS-base). They make the **Teltonika TRM200**
(MeiG SLM770A inside) work with ModemManager and NetworkManager.

The plugins are built against the exact ModemManager version of Raspberry Pi OS
trixie (arm64), which tsOS is based on, and shipped as a Debian package that adds
them to ModemManager's plugin directory. Debian's `modemmanager` package stays
unchanged.

## Why

Stock ModemManager 1.24 handles the SLM770A with its generic plugin, which
can't connect:

* `AT+WS46=?` returns `ERROR`, so MM thinks the modem has no LTE, never queries
  `+CEREG`, and reports the packet service as *detached* on LTE.
* `ATZ` returns `ERROR`, so enabling fails when the modem is already attached
  when MM starts (e.g. at boot).
* The generic plugin can't bring up the RNDIS/ECM network interface.

## Supported devices

| USB ID | Device | Plugin |
|---|---|---|
| `2dee:4d57` | MeiG SLM770A, RNDIS mode (`AT+SER=3`), e.g. **Teltonika TRM200** | `meig-asr` |
| `2dee:4d58` | MeiG SLM770A, ECM mode (`AT+SER=2`) | `meig-asr` |
| `1d12:0102` | Teltonika ALA440 | `teltonika-meig-asr` |

Port layout (all variants): if 2 ASR DIAG (ignored), if 3 AT primary,
if 4 AT secondary, if 5 GPS.

The kernel's `option` driver only knows `2dee:4d57`. For ECM mode,
`udev/70-meig-slm770a-ecm-option.rules` adds `2dee:4d58` to `option` at
runtime. Without it, only the `cdc_ether` interface comes up and the AT ports
stay unbound.

Switching a TRM200 between modes is persistent and reboots the modem:
`AT+SER=2,1` (ECM, `cdc_ether`) or `AT+SER=3,1` (RNDIS, `rndis_host`, factory default).

## Where the code comes from

`patches/` is applied on top of upstream ModemManager `1.24.0`
(pinned in `versions.env`):

| Patch | Source |
|---|---|
| 0001–0004 | [ModemManager MR !1502](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/merge_requests/1502) ("Add support for Teltonika -> MeiG -> ASR modems", by lvoegl, commit `0076a216`), backported from `main` to 1.24.0 |
| 0005 | local: plugin-private copy of `mm_3gpp_normalize_address()`, which only exists in MM `main` and isn't exported by the 1.24 daemon |
| 0006 | local: adds the RNDIS variant `2dee:4d57` (TRM200) |
| 0007 | local: `MM_DEFINE_SHARED` for `shared-asr`/`shared-meig`. The MR lacks it, so these modules don't load unless plugins are built in |
| 0008 | local: skip the `ATZ` init, which the modem answers with `ERROR`. Otherwise enabling fails at boot, after MM restarts and after inhibition |
| 0009 | local: MeiG modems dial and hang up with `+ECMDUP` and report the connection status from `+ECMDUP?`. With `+CGACT` (as in the MR) the context isn't routed to the network interface |

`build.sh` also makes `libmm-shared-meig.so` depend on `libmm-shared-asr.so`
(`DT_NEEDED` + `RUNPATH=$ORIGIN`). ModemManager opens shared modules in
directory order with immediate binding, so `shared-meig` would otherwise fail
whenever it happens to be opened before `shared-asr`.

The backport leaves daemon code untouched. Only `src/plugins/` and the build
files change. Debian's `1.24.0-1+deb13u1` only patches the Fibocom plugin, so
upstream `1.24.0` is ABI-identical to it.

## Build output

`build.sh` produces `dist/modemmanager-meig-asr_<version>_<arch>.deb` with:

```
usr/lib/aarch64-linux-gnu/ModemManager/libmm-plugin-meig-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-plugin-teltonika-meig-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-shared-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-shared-meig.so
usr/lib/udev/rules.d/70-meig-slm770a-ecm-option.rules
usr/lib/udev/rules.d/77-mm-meig-port-types.rules
usr/lib/udev/rules.d/77-mm-teltonika-port-types.rules
usr/share/doc/modemmanager-meig-asr/{README.md,copyright,changelog.Debian.gz}
```

The package depends on the exact `modemmanager` and `libmm-glib0` version it
was built against (`MM_DEBIAN_VERSION` in `versions.env`), because the plugins
use daemon-internal symbols. apt therefore refuses to install it next to any
other ModemManager. If a later `modemmanager` update arrives, `apt upgrade`
holds it back, while `apt full-upgrade` would remove this package. Rebuild for
the new version first (see below).

On a running system, `postinst`/`postrm` reload the udev rules and restart
ModemManager. In image builds (chroot, no systemd running) they do nothing.

`check-symbols.sh` verifies that every ModemManager symbol the plugins import
is exported by the installed Debian `modemmanager`/`libmm-glib0`. CI runs it on
every build and test-installs the package on Debian trixie with the Raspberry
Pi OS archive (`archive.raspberrypi.com`) enabled, i.e. the package set of
Raspberry Pi OS trixie.

## Installing in tsOS

In `tsOS-base.Pifile`, after the software installation:

```sh
# Install ModemManager plugins for ASR/MeiG modems (Teltonika TRM200)
MM_MEIG_ASR_VERSION=1.24.0-1
RUN sh -c "curl -fsSL -o /tmp/modemmanager-meig-asr.deb https://github.com/trackIT-Systems/modemmanager-meig-asr/releases/download/${MM_MEIG_ASR_VERSION}/modemmanager-meig-asr_${MM_MEIG_ASR_VERSION}_${ARCH}.deb"
RUN apt-get install -y /tmp/modemmanager-meig-asr.deb
RUN rm /tmp/modemmanager-meig-asr.deb
```

`apt-get install` fails the image build if the image's `modemmanager` isn't the
version the plugins were built for. In that case, see below. Upgrading the
plugins only means changing `MM_MEIG_ASR_VERSION`.

On any other Raspberry Pi OS trixie (arm64) system, download the `.deb` from the
release and run `sudo apt install ./modemmanager-meig-asr_<version>_arm64.deb`.

## When Debian updates ModemManager

The plugins use daemon-internal symbols, so they're tied to one ModemManager
version. When the image gets a new `modemmanager`:

1. Update `MM_TAG`, `MM_COMMIT` and `MM_DEBIAN_VERSION` in `versions.env`.
   Check `debian/patches` of the new Debian version for changes outside
   `src/plugins/`.
2. Rebase `patches/` if needed (`git am` onto the new tag, then
   `git format-patch --zero-commit --no-signature <tag>..HEAD`).
3. Tag a release (see [Versioning](#versioning)), then update
   `MM_MEIG_ASR_VERSION` in the Pifile.

Once MR !1502 is merged and shipped by Debian, this repository is obsolete.

## Building locally

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

`build.sh` refuses to run if `build/` exists. Remove it for a fresh build.

## Versioning

Releases are tagged `<ModemManager version>-<revision>`, like Debian package
revisions:

```
1.24.0-1   first release for ModemManager 1.24.0
1.24.0-2   our own changes (fixes, new USB IDs, ...) or a Debian-only update
           of ModemManager 1.24.0 (e.g. +deb13u2), still for 1.24.0
1.26.0-1   rebuilt for ModemManager 1.26.0, revision starts again at 1
```

The tag tells you which ModemManager a release loads into, and it is also the
Debian package version. The exact Debian ModemManager version is in
`versions.env` and in the package's `Depends`. Tags have no `v` prefix.

Untagged builds (CI on `main`, local builds) get
`<ModemManager version>-0~git<date>.<commit count>.<commit>`, e.g.
`1.24.0-0~git20261007.10.e814430`, which apt sorts before the first release.
Builds are only distinguishable by version once committed: rebuilding with
uncommitted changes reuses the version, and apt won't reinstall it.

## Releasing

Add a `## [<tag>]` section to `CHANGELOG.md`, then push the tag. CI builds the
arm64 `.deb` and attaches it to a GitHub (pre)release.

## Status

Tested on a Teltonika TRM200 (firmware `SLM770A_A.57.3_EQ102`) on a Raspberry Pi 5
with tsOS and Debian's `modemmanager 1.24.0-1+deb13u1`:

* The `meig-asr` plugin claims the modem in both modes, RNDIS (`2dee:4d57`,
  `rndis_host`) and ECM (`2dee:4d58`, `cdc_ether`). The modem reports LTE, the
  packet service is attached, and NetworkManager connects with a normal `gsm`
  profile (APN only).
* The MeiG plugin dials with `+CGDCONT`, `*AUTHREQ` and then
  `+ECMDUP=<cid>,1,<pdp type>,"<apn>"`, hangs up with `+ECMDUP=<cid>,0`, and
  polls the connection status with `+ECMDUP?` (patch 0009). `usb0` gets a DHCP
  lease with a /29 or /30 and a real gateway in the carrier network, so there's
  no clash with the tsOS hotspot. `169.254.0.1` is only the DHCP server
  identifier, in both modes.
* IPv4 traffic works (ping, HTTPS). A 2 MB download ran at ~4.7 Mbit/s over ECM
  and ~3.8 Mbit/s over RNDIS (single samples, LTE Cat 1, roaming).
* With data checked after each step: 5 of 5 NetworkManager disconnect/reconnect
  cycles, a ModemManager restart and a USB re-plug.
* A connection dropped by the modem (`+ECMDUP=<cid>,0` behind ModemManager's
  back) was detected within ~10 s; NetworkManager reconnected and data flowed
  again ~15 s after the drop.
* Enabling works at hot-plug, after a ModemManager restart and after
  inhibition, because `ATZ` isn't sent.

Why `+ECMDUP` and not `+CGACT` (tested on firmware `SLM770A_A.57.3_EQ102`):

* A context activated with `+CGACT` is not routed to `usb0`. NetworkManager
  reported a connection with a valid DHCP lease, but no traffic passed.
* `+ECMDUP=<cid>,1,…,"<apn>"` activates the context itself and connects it.
  Activating it with `+CGACT` first makes the following `+ECMDUP` fail.
* `+ECMDUP=<cid>,0` disconnects `usb0`; the LTE default bearer stays active.

Known issues:
* `ttyUSB3` (GPS) is reported as an unhandled port. There's no location support yet.
* No global IPv6 address on `usb0` with an `ipv4v6` context.
* **Pi 5 power:** with a 3 A supply, the Pi 5 limits all USB ports together to
  600 mA. The USB power switch then tripped (`over-current change` on all ports)
  several times, mostly under data load, and the modem re-enumerated.
  ModemManager and NetworkManager reconnected on their own within ~40 s.
  With a 5 A supply (USB limit lifted automatically, `usb_max_current_enable=1`),
  5 × 2 MB downloads and 2 × 1 MB uploads ran without a single trip. **Use a 5 A
  supply** (or a powered hub) for the TRM200 on a Pi 5.

## License

GPL-2.0-or-later, like ModemManager's plugins.
