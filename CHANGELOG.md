# Changelog

## [Unreleased]

- Backport ModemManager MR !1502 (ASR, MeiG ASR and Teltonika MeiG ASR plugins) to ModemManager 1.24.0.
- Keep the address normalizer local to the ASR plugin so it loads into the unmodified 1.24 daemon.
- Support the MeiG SLM770A in RNDIS mode (`2dee:4d57`), as used in the Teltonika TRM200.
- Build only the plugins against Debian trixie's `modemmanager 1.24.0-1+deb13u1`, with a symbol check in CI.
- Define shared-module version info for `shared-asr` and `shared-meig` (missing in MR !1502). Without it, ModemManager refuses to load them.
- Make `libmm-shared-meig.so` depend on `libmm-shared-asr.so`, so it loads regardless of directory order.
- `check-symbols.sh` also checks module version exports and that shared-module dependency.
- Skip the `ATZ` init, which ASR MeiG modems reject. Enabling no longer fails at boot, after ModemManager restarts or after inhibition.
- Add a udev rule that binds the `option` driver to the ECM variant `2dee:4d58`, which the kernel doesn't know.
- Dial MeiG modems with `+ECMDUP` instead of `+CGACT`, hang up with `+ECMDUP=<cid>,0` and poll the connection status with `+ECMDUP?`. With `+CGACT`, traffic stopped after reconnects or ModemManager restarts while the connection was reported as up.
- Tested on a Teltonika TRM200 in RNDIS and ECM mode: connects via NetworkManager, IPv4 data works, survives reconnects, ModemManager restarts and re-plugs, and recovers from connection drops.
- Ship the plugins as a Debian package for Raspberry Pi OS trixie (arm64) instead of a tarball. It depends on the exact `modemmanager`/`libmm-glib0` version and reloads udev and ModemManager on install.
- CI builds against Debian trixie plus the Raspberry Pi OS archive and test-installs the package.
- Version releases as `<ModemManager version>-<revision>`. The first release will be `1.24.0-1`.
