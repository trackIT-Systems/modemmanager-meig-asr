#!/bin/sh
# Build the ASR/MeiG ModemManager plugins against a pinned ModemManager release
# and package them as a tarball that unpacks onto /.
#
# Runs on Debian trixie with the build dependencies from the README installed.
# usage: ./build.sh [version]     (version defaults to `git describe`)
set -eu

TOP=$(cd "$(dirname "$0")" && pwd)
. "$TOP/versions.env"

VERSION=${1:-$(git -C "$TOP" describe --tags --always --dirty 2>/dev/null || echo dev)}
ARCH=$(dpkg --print-architecture)
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
NAME=modemmanager-meig-asr

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
    strip --strip-unneeded "$PLUGINDIR/$lib"
done
for rule in $RULES; do
    install -m 644 "$SRC/src/plugins/$rule" "$UDEVDIR/"
done
install -m 644 "$TOP/README.md" "$TOP/LICENSE" "$DOCDIR/"

cat > "$DOCDIR/BUILDINFO" <<EOF
name=$NAME
version=$VERSION
arch=$ARCH
mm_tag=$MM_TAG
mm_commit=$MM_COMMIT
mm_debian_version=$MM_DEBIAN_VERSION
EOF

# Files only, no directory entries: extracting onto / must not touch the
# permissions or mtimes of existing directories like /usr.
TARBALL=$DIST/$NAME-$VERSION-$ARCH.tar.gz
(cd "$STAGE" && find . -type f | sed 's|^\./||' | sort) |
    tar --owner=0 --group=0 --numeric-owner -C "$STAGE" -czf "$TARBALL" -T -
echo "built $TARBALL"
tar -tzvf "$TARBALL"
