# Changelog

## [1.24.0-1] - 2026-10-07

First release, for Raspberry Pi OS trixie (arm64) with
`modemmanager 1.24.0-1+deb13u1`, tested with Raspberry Pi OS Lite 2026-09-15.

- ModemManager plugins for ASR-based MeiG modems, backported from
  ModemManager MR !1502 (ASR, MeiG ASR and Teltonika MeiG ASR plugins) to
  ModemManager 1.24.0.
- Support the MeiG SLM770A in RNDIS mode (`2dee:4d57`, Teltonika TRM200 as
  shipped) and ECM mode (`2dee:4d58`, with a udev rule that binds the `option`
  driver to it).
- Dial MeiG modems with `+ECMDUP` instead of `+CGACT`, hang up with
  `+ECMDUP=<cid>,0` and poll the connection status with `+ECMDUP?`. With
  `+CGACT`, traffic stopped after reconnects or ModemManager restarts while the
  connection was reported as up.
- Skip the `ATZ` init, which ASR MeiG modems reject, so enabling works at boot,
  after ModemManager restarts and after inhibition.
- Fixes needed to load the plugins into Debian's ModemManager, which builds
  plugins as separate modules: shared-module version info for `shared-asr` and
  `shared-meig` (missing in MR !1502), an explicit dependency of
  `libmm-shared-meig.so` on `libmm-shared-asr.so`, and a plugin-local address
  normalizer instead of a helper that only exists in ModemManager `main`.
- Debian package that depends on the exact `modemmanager`/`libmm-glib0`
  version and reloads udev and ModemManager on install.
- CI builds on Debian trixie with the Raspberry Pi OS archive, checks the
  plugins' symbols against Debian's ModemManager and test-installs the package.
- Tested on a Teltonika TRM200 (firmware `SLM770A_A.57.3_EQ102`) on a
  Raspberry Pi 5: connects via NetworkManager with IPv4 data in RNDIS and ECM
  mode; reconnects, ModemManager restarts, re-plugs and recovery from
  connection drops tested in RNDIS mode.
