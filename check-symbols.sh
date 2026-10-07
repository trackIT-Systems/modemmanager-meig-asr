#!/bin/sh
# Verify that every symbol the built plugins import is provided by the installed
# ModemManager daemon, libmm-glib or another of the built plugins. Catches
# plugins that would fail to load on the target system.
#
# Needs the Debian modemmanager package (MM_DEBIAN_VERSION) installed.
# usage: ./check-symbols.sh
set -eu

TOP=$(cd "$(dirname "$0")" && pwd)
. "$TOP/versions.env"

MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
PLUGINDIR=$TOP/build/stage/usr/lib/$MULTIARCH/ModemManager
DAEMON=/usr/sbin/ModemManager
LIBMM=$(ldd "$DAEMON" | awk '/libmm-glib\.so/ { print $3 }')

installed=$(dpkg-query -W -f='${Version}' modemmanager)
if [ "$installed" != "$MM_DEBIAN_VERSION" ]; then
    echo "error: modemmanager $installed installed, expected $MM_DEBIAN_VERSION" >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

defined() {
    nm -D --defined-only "$@" | awk 'NF == 3 { sub(/@.*/, "", $3); print $3 }'
}

defined "$DAEMON" "$LIBMM" "$PLUGINDIR"/*.so | sort -u > "$tmp/provided"
nm -D --undefined-only "$PLUGINDIR"/*.so | awk '{ sub(/@.*/, "", $2); print $2 }' |
    grep -E '^_?mm_' | sort -u > "$tmp/needed"

missing=$(comm -23 "$tmp/needed" "$tmp/provided")
if [ -n "$missing" ]; then
    echo "error: symbols not provided by modemmanager $installed:" >&2
    echo "$missing" >&2
    exit 1
fi
echo "ok: all $(wc -l < "$tmp/needed") ModemManager symbols resolve against modemmanager $installed"

# ModemManager rejects modules without these exports
fail=0
for so in "$PLUGINDIR"/*.so; do
    case $(basename "$so") in
        libmm-shared-*) want="mm_shared_major_version mm_shared_minor_version mm_shared_name" ;;
        libmm-plugin-*) want="mm_plugin_major_version mm_plugin_minor_version mm_plugin_create" ;;
        *) continue ;;
    esac
    defined "$so" > "$tmp/exports"
    for sym in $want; do
        if ! grep -qx "$sym" "$tmp/exports"; then
            echo "error: $(basename "$so") does not export $sym" >&2
            fail=1
        fi
    done
done

# shared-meig must pull in shared-asr itself, see build.sh
if ! readelf -d "$PLUGINDIR/libmm-shared-meig.so" | grep -q 'NEEDED.*\[libmm-shared-asr\.so\]'; then
    echo "error: libmm-shared-meig.so does not declare its dependency on libmm-shared-asr.so" >&2
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "ok: module version exports and shared-module dependencies present"
