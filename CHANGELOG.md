# Changelog

## [Unreleased]

- Backport ModemManager MR !1502 (ASR, MeiG ASR and Teltonika MeiG ASR plugins) to ModemManager 1.24.0.
- Keep the address normalizer local to the ASR plugin so it loads into the unmodified 1.24 daemon.
- Support the MeiG SLM770A in RNDIS mode (`2dee:4d57`), as used in the Teltonika TRM200.
- Build only the plugins against Debian trixie's `modemmanager 1.24.0-1+deb13u1`, with a symbol check in CI.
- Define shared-module version info for `shared-asr` and `shared-meig` (missing in MR !1502). Without it, ModemManager refuses to load them.
- Make `libmm-shared-meig.so` depend on `libmm-shared-asr.so`, so it loads regardless of directory order.
- `check-symbols.sh` also checks module version exports and that shared-module dependency.
- Tested on a Teltonika TRM200: connects via NetworkManager, IPv4 data works.
- Version releases as `<ModemManager version>-<revision>`. The first release will be `1.24.0-1`.
- Write `BUILDINFO` as shell-sourceable, so the image build reads the required `modemmanager` version from it.
