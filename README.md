# modemmanager-meig-asr

ModemManager plugins for ASR-based MeiG modems, packaged for
[tsOS](https://github.com/trackIT-Systems/tsOS-base). They make the **Teltonika TRM200**
(MeiG SLM770A inside) work with ModemManager and NetworkManager.

The plugins are built against the exact ModemManager version in the tsOS image
and dropped into its plugin directory. Debian's `modemmanager` package stays
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

`build.sh` also makes `libmm-shared-meig.so` depend on `libmm-shared-asr.so`
(`DT_NEEDED` + `RUNPATH=$ORIGIN`). ModemManager opens shared modules in
directory order with immediate binding, so `shared-meig` would otherwise fail
whenever it happens to be opened before `shared-asr`.

The backport leaves daemon code untouched. Only `src/plugins/` and the build
files change. Debian's `1.24.0-1+deb13u1` only patches the Fibocom plugin, so
upstream `1.24.0` is ABI-identical to it.

## Build output

`build.sh` produces `dist/modemmanager-meig-asr-<version>-<arch>.tar.gz`,
which contains only files (no directory entries) and unpacks onto `/`:

```
usr/lib/aarch64-linux-gnu/ModemManager/libmm-plugin-meig-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-plugin-teltonika-meig-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-shared-asr.so
usr/lib/aarch64-linux-gnu/ModemManager/libmm-shared-meig.so
usr/lib/udev/rules.d/70-meig-slm770a-ecm-option.rules
usr/lib/udev/rules.d/77-mm-meig-port-types.rules
usr/lib/udev/rules.d/77-mm-teltonika-port-types.rules
usr/share/doc/modemmanager-meig-asr/{BUILDINFO,README.md,LICENSE}
```

`check-symbols.sh` verifies that every ModemManager symbol the plugins import
is exported by the installed Debian `modemmanager`/`libmm-glib0`. CI runs it
on every build.

## Installing in tsOS

In `tsOS-base.Pifile`, after the software installation:

```sh
# Install ModemManager plugins for ASR/MeiG modems (Teltonika TRM200)
MM_MEIG_ASR_VERSION=1.24.0-1
RUN sh -c "curl -fsSL https://github.com/trackIT-Systems/modemmanager-meig-asr/releases/download/${MM_MEIG_ASR_VERSION}/modemmanager-meig-asr-${MM_MEIG_ASR_VERSION}-${ARCH}.tar.gz | tar xz -C /"
RUN sh -c '. /usr/share/doc/modemmanager-meig-asr/BUILDINFO && test "$(dpkg-query -W -f="\${Version}" modemmanager)" = "$mm_debian_version"'
```

The second `RUN` reads the ModemManager version the plugins were built for from
`BUILDINFO`. It fails the image build if the image's `modemmanager` doesn't match
it. In that case, see below. Upgrading the plugins only means changing
`MM_MEIG_ASR_VERSION`.

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

On Debian trixie (or in a `debian:trixie` container):

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

The tag tells you which ModemManager a release loads into. The exact Debian
version it was checked against is in `versions.env` and in the tarball's
`BUILDINFO`. Tags have no `v` prefix.

## Releasing

Add a `## [<tag>]` section to `CHANGELOG.md`, then push the tag. CI builds the
arm64 tarball and attaches it to a GitHub (pre)release.

## Status

Tested on a Teltonika TRM200 (firmware `SLM770A_A.57.3_EQ102`) on a Raspberry Pi 5
with tsOS and Debian's `modemmanager 1.24.0-1+deb13u1`:

* The `meig-asr` plugin claims the modem in both modes, RNDIS (`2dee:4d57`,
  `rndis_host`) and ECM (`2dee:4d58`, `cdc_ether`). The modem reports LTE, the
  packet service is attached, and NetworkManager connects with a normal `gsm`
  profile (APN only).
* The plugin dials with `+CGDCONT`/`+CGACT` on cid 2. `usb0` gets a DHCP lease
  with a /30, /29 or /26 and a real gateway in the carrier network, so there's no
  clash with the tsOS hotspot. `169.254.0.1` is only the DHCP server identifier,
  in both modes.
* IPv4 traffic works (ping, HTTPS). A 2 MB download ran at ~4.7 Mbit/s over ECM
  and ~3.8 Mbit/s over RNDIS (single samples, LTE Cat 1, roaming).
* Enabling works at hot-plug, after a ModemManager restart and after
  inhibition, because `ATZ` isn't sent.

Known issues:

* The first connect after a ModemManager restart once timed out waiting for
  DHCP. NetworkManager's immediate retry succeeded.
* `ttyUSB3` (GPS) is reported as an unhandled port. There's no location support yet.
* No global IPv6 address on `usb0` with an `ipv4v6` context.
* On a Pi 5 with the default 600 mA USB current limit, the USB power switch
  tripped (`over-current change` on all ports) several times, mostly under
  data load, and the modem re-enumerated. ModemManager and NetworkManager
  reconnected on their own within ~40 s. That's a power-supply issue, not a
  plugin issue.

## License

GPL-2.0-or-later, like ModemManager's plugins.
