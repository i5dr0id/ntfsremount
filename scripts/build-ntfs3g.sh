#!/bin/bash
#
# Build ntfs-3g linked against FUSE-T (kext-less) and install it into
# /opt/homebrew/opt/ntfs-3g-t, which is where ntfsremount expects to find it.
#
# Why: the Homebrew formula links against macFUSE, which does not work on
# current macOS. ntfsremount needs an ntfs-3g built against FUSE-T.
#
# Requirements:
#   brew install --cask fuse-t
#   brew install autoconf automake libtool pkg-config
#
set -euo pipefail

FUSE_T_PREFIX="${FUSE_T_PREFIX:-/usr/local}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/homebrew/opt/ntfs-3g-t}"
NTFS3G_VERSION="${NTFS3G_VERSION:-2022.10.3}"
WORK_DIR="${WORK_DIR:-/tmp/ntfs-3g-build}"
SRC_DIR="${WORK_DIR}/ntfs-3g-${NTFS3G_VERSION}"

for file in "${FUSE_T_PREFIX}/lib/libfuse-t.dylib" "${FUSE_T_PREFIX}/include/fuse/fuse.h"; do
    if [ ! -e "${file}" ]; then
        echo "error: ${file} not found. Is FUSE-T installed? (brew install --cask fuse-t)" >&2
        exit 1
    fi
done

mkdir -p "${WORK_DIR}/pc"

# FUSE-T does not ship a pkg-config file, so provide a shim that points the
# ntfs-3g configure script at libfuse-t.
cat > "${WORK_DIR}/pc/fuse.pc" <<EOF
prefix=${FUSE_T_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: fuse
Description: FUSE-T (kext-less FUSE for macOS)
Version: 2.9.9
Libs: -L\${libdir} -Wl,-rpath,\${libdir} -lfuse-t
Cflags: -D_FILE_OFFSET_BITS=64 -I\${includedir}/fuse
EOF

if [ ! -d "${SRC_DIR}" ]; then
    echo "==> downloading ntfs-3g ${NTFS3G_VERSION}"
    curl -fL -o "${WORK_DIR}/ntfs-3g.tar.gz" \
        "https://github.com/tuxera/ntfs-3g/archive/refs/tags/${NTFS3G_VERSION}.tar.gz"
    tar xzf "${WORK_DIR}/ntfs-3g.tar.gz" -C "${WORK_DIR}"
fi

cd "${SRC_DIR}"

if [ ! -x ./configure ]; then
    echo "==> generating configure (autoreconf)"
    autoreconf --verbose --install --force
fi

echo "==> configuring"
PKG_CONFIG_PATH="${WORK_DIR}/pc" ./configure \
    --prefix="${INSTALL_PREFIX}" \
    --exec-prefix="${INSTALL_PREFIX}" \
    --disable-static

echo "==> building"
make -j"$(sysctl -n hw.ncpu)"

echo "==> installing to ${INSTALL_PREFIX}"
make install

echo "==> done"
"${INSTALL_PREFIX}/bin/ntfs-3g" --version
