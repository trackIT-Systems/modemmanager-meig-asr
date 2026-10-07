#!/bin/sh
# Build the ASR/MeiG ModemManager plugins against a pinned ModemManager release
# and package them as a .deb for Debian / Raspberry Pi OS trixie.
#
# Runs on trixie with the build dependencies from the README installed.
# usage: ./build.sh [version]
#   version defaults to the git tag on HEAD, or <MM_TAG>-0~git<date>.<count>.<sha>
#   for untagged builds (sorts before the first release for that MM version;
#   the commit count keeps builds from the same day in order).
set -eu

TOP=$(cd "$(dirname "$0")" && pwd)
. "$TOP/versions.env"

NAME=modemmanager-meig-asr
MAINTAINER="Jonas Höchst <hoechst@trackit.systems>"
HOMEPAGE=https://github.com/trackIT-Systems/modemmanager-meig-asr

SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$TOP" log -1 --format=%ct 2>/dev/null || date +%s)}
export SOURCE_DATE_EPOCH

if [ $# -ge 1 ]; then
    VERSION=$1
elif tag=$(git -C "$TOP" describe --tags --exact-match 2>/dev/null); then
    VERSION=$tag
else
    VERSION="$MM_TAG-0~git$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d).$(git -C "$TOP" rev-list --count HEAD).$(git -C "$TOP" rev-parse --short HEAD)"
fi
dpkg --validate-version "$VERSION"

ARCH=$(dpkg --print-architecture)
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)

WORK=$TOP/build
SRC=$WORK/src
BUILD=$WORK/meson
STAGE=$WORK/stage
DIST=$TOP/dist

if [ -e "$WORK" ]; then
    echo "error: $WORK exists, remove it for a clean build" >&2
    exit 1
fi
mkdir -p "$WORK" "$DIST"

# Fetch the pinned ModemManager release and apply the plugin patches
git clone --quiet --depth 1 --branch "$MM_TAG" "$MM_REPO" "$SRC"
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$MM_COMMIT" ]; then
    echo "error: tag $MM_TAG does not point to $MM_COMMIT" >&2
    exit 1
fi
git -C "$SRC" -c user.name=build -c user.email=build@localhost \
    am --quiet "$TOP"/patches/*.patch

# Configure like Debian's package, but build only the plugin targets
meson setup "$BUILD" "$SRC" \
    --buildtype=plain \
    -Dpolkit=permissive \
    -Dmbim=true -Dqmi=true -Dqrtr=true \
    -Dintrospection=false -Dvapi=false -Dman=false \
    -Dbash_completion=false -Dtests=false -Dexamples=false \
    -Dauto_features=disabled \
    -Dplugin_meig_asr=enabled \
    -Dplugin_teltonika_meig_asr=enabled

LIBS="libmm-shared-asr.so libmm-shared-meig.so libmm-plugin-meig-asr.so libmm-plugin-teltonika-meig-asr.so"
RULES="meig/77-mm-meig-port-types.rules teltonika/77-mm-teltonika-port-types.rules"

targets=""
for lib in $LIBS; do
    targets="$targets src/plugins/$lib"
done
# shellcheck disable=SC2086
ninja -C "$BUILD" $targets

# Stage the files at their install locations
PLUGINDIR=$STAGE/usr/lib/$MULTIARCH/ModemManager
UDEVDIR=$STAGE/usr/lib/udev/rules.d
DOCDIR=$STAGE/usr/share/doc/$NAME
install -d "$PLUGINDIR" "$UDEVDIR" "$DOCDIR"

for lib in $LIBS; do
    install -m 644 "$BUILD/src/plugins/$lib" "$PLUGINDIR/"
    # drop the build-tree RUNPATH and debug info, like `meson install` + dh_strip
    patchelf --remove-rpath "$PLUGINDIR/$lib"
    strip --strip-unneeded --remove-section=.comment --remove-section=.note "$PLUGINDIR/$lib"
done

# libmm-shared-meig.so uses symbols from libmm-shared-asr.so. ModemManager
# opens shared modules in directory order with immediate binding, so make the
# dependency explicit: the dynamic loader then loads shared-asr first.
patchelf --add-needed libmm-shared-asr.so --set-rpath '$ORIGIN' \
    "$PLUGINDIR/libmm-shared-meig.so"

for rule in $RULES; do
    install -m 644 "$SRC/src/plugins/$rule" "$UDEVDIR/"
done
install -m 644 "$TOP"/udev/*.rules "$UDEVDIR/"

# Documentation, as required by Debian policy
install -m 644 "$TOP/README.md" "$TOP/docs/TRM200.md" "$DOCDIR/"
cat > "$DOCDIR/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ModemManager
Upstream-Contact: https://gitlab.freedesktop.org/mobile-broadband/ModemManager
Source: $HOMEPAGE

Files: *
Copyright: ModemManager contributors
           2026 TDT AG (ASR, MeiG and Teltonika plugins, ModemManager MR !1502)
           2026 trackIT Systems
License: GPL-2+
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 .
 On Debian systems, the complete text of the GNU General Public License
 version 2 can be found in /usr/share/common-licenses/GPL-2.
EOF
cat > "$WORK/changelog.Debian" <<EOF
$NAME ($VERSION) trixie; urgency=medium

  * Built from $(git -C "$TOP" rev-parse --short HEAD 2>/dev/null || echo unknown) against ModemManager $MM_TAG ($MM_COMMIT),
    for Debian modemmanager $MM_DEBIAN_VERSION.
  * See $HOMEPAGE/blob/main/CHANGELOG.md

 -- $MAINTAINER  $(date -u -R -d "@$SOURCE_DATE_EPOCH")
EOF
gzip -9n < "$WORK/changelog.Debian" > "$DOCDIR/changelog.Debian.gz"
chmod 644 "$DOCDIR"/*

# Runtime library dependencies. -S lets dpkg-shlibdeps resolve
# libmm-shared-asr.so from the package itself.
mkdir -p "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$NAME" "$NAME" > "$WORK/shlibs/debian/control"
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -O -S"$STAGE" "$PLUGINDIR"/*.so |
    sed -n 's/^shlibs:Depends=//p')
if [ -z "$SHLIBS" ]; then
    echo "error: dpkg-shlibdeps found no library dependencies" >&2
    exit 1
fi
# libmm-glib0 gets an exact dependency below instead of the generated one
SHLIBS=$(echo "$SHLIBS" | tr ',' '\n' | sed 's/^ *//' | grep -v '^libmm-glib0 ' | paste -sd, - | sed 's/,/, /g')

# The plugins use daemon-internal symbols: only the exact ModemManager build fits
DEPENDS="$SHLIBS, modemmanager (= $MM_DEBIAN_VERSION), libmm-glib0 (= $MM_DEBIAN_VERSION)"

install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)
Depends: $DEPENDS
Section: net
Priority: optional
Homepage: $HOMEPAGE
Description: ModemManager plugins for ASR-based MeiG modems (Teltonika TRM200)
 ModemManager plugins for modems based on ASR chipsets: the MeiG SLM770A in
 RNDIS (2dee:4d57) and ECM (2dee:4d58) mode, as used in the Teltonika TRM200,
 and the Teltonika ALA440 (1d12:0102).
 .
 Backported from ModemManager merge request !1502 to ModemManager $MM_TAG and
 built against Debian's modemmanager $MM_DEBIAN_VERSION.
EOF

# Reload udev rules and restart ModemManager on a running system. In image
# builds (chroot, no systemd running) there is nothing to do.
for script in postinst postrm; do
    cat > "$STAGE/DEBIAN/$script" <<'EOF'
#!/bin/sh
set -e

if [ -d /run/systemd/system ]; then
    udevadm control --reload || true
    deb-systemd-invoke try-restart ModemManager.service >/dev/null || true
fi

exit 0
EOF
    chmod 755 "$STAGE/DEBIAN/$script"
done

(cd "$STAGE" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z | xargs -0 md5sum) \
    > "$STAGE/DEBIAN/md5sums"

DEB=$DIST/${NAME}_${VERSION}_${ARCH}.deb
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB"
dpkg-deb --info "$DEB"
dpkg-deb --contents "$DEB"
