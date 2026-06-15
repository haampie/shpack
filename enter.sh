#!/bin/sh

# Incremental chroot runner -- iterate on shpack recipes WITHOUT rebuilding the
# whole chain from seeds.
#
#   ./enter.sh <arch> shpack install <pkg>     # build/refresh one package
#   ./enter.sh <arch> shpack install gcc       # the full default target
#   ./enter.sh <arch>                           # interactive shell in the chroot
#
# Unlike build.sh, this does NOT `rm -rf rootfs`: it reuses the existing store
# (rootfs/opt/*), so already-built nodes are skipped via their dag.mk stamps and
# only the requested package (and any out-of-date deps) rebuild. Use build.sh
# once to seed the chain, then enter.sh to iterate on the upper layers.
#
# It also re-syncs the recipe tree (shpack/packages, lib, bin) from the source
# checkout into rootfs/shpack first, so edits on the host take effect here
# without a full restage.
#
# Requires an existing rootfs/ (run ./build.sh <arch> first). Uses the same sudo
# unshare+chroot path as build.sh, plus a /proc mount: gmake is linked against
# musl 1.1.24, whose realpath() reads /proc/self/fd, so kernel/glibc/gcc
# Makefiles that call $(realpath ...) need /proc present.

set -e

ARCH="$1"
shift || true
case "$ARCH" in
    amd64)   SEEDARCH=AMD64 ;;
    aarch64) SEEDARCH=AArch64 ;;
    *) echo "usage: $0 <amd64|aarch64> [command...]" >&2; exit 1 ;;
esac

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
[ -d rootfs/opt ] && [ -f rootfs/shpack/etc/config ] || {
    echo "no seeded rootfs/ -- run ./build.sh $ARCH first" >&2; exit 1; }

# Same throwaway-build-scratch tmpfs as build.sh (see STAGE_TMPFS there); default
# on, STAGE_TMPFS=0 to disable.
STAGE_TMPFS="${STAGE_TMPFS:-1}"

# Re-sync recipes/lib/bin and distfiles from the host checkout so host edits
# (new recipes, new tarballs) take effect without a full restage.
sudo cp -r shpack/packages shpack/lib shpack/bin rootfs/shpack/
sudo cp -n distfiles/. rootfs/external/distfiles/ 2>/dev/null || \
    sudo sh -c 'cp -n distfiles/* rootfs/external/distfiles/ 2>/dev/null || true'

# Minimal /dev + /proc (see header). Root-owned, so clean them up on exit.
cleanup() {
    sudo umount rootfs/tmp/shpack/stage 2>/dev/null || true
    sudo umount rootfs/proc 2>/dev/null || true
    sudo rm -rf rootfs/dev rootfs/proc
}
trap cleanup EXIT
sudo mkdir -p rootfs/dev rootfs/proc
sudo mknod -m 666 rootfs/dev/null    c 1 3 2>/dev/null || true
sudo mknod -m 666 rootfs/dev/zero    c 1 5 2>/dev/null || true
sudo mknod -m 666 rootfs/dev/full    c 1 7 2>/dev/null || true
sudo mknod -m 666 rootfs/dev/random  c 1 8 2>/dev/null || true
sudo mknod -m 666 rootfs/dev/urandom c 1 9 2>/dev/null || true
sudo mknod -m 666 rootfs/dev/tty     c 5 0 2>/dev/null || true
sudo mount -t proc proc rootfs/proc
# tmpfs for the throwaway build scratch (mode 1777 for the --setuid non-root build).
if [ "$STAGE_TMPFS" = 1 ]; then
    sudo mkdir -p rootfs/tmp/shpack/stage
    sudo mount -t tmpfs -o mode=1777 tmpfs rootfs/tmp/shpack/stage
fi

# BASEPATH from the staged config (same PATH floor the kaem phase hands shpack).
BP=$(sed -n 's/^BASEPATH=//p' rootfs/shpack/etc/config | head -1)

# Default command: the full install target.
[ "$#" -gt 0 ] || set -- shpack install gcc
# Map a leading bare `shpack` to the in-rootfs entry point.
if [ "$1" = shpack ]; then shift; set -- /bin/sh /shpack/bin/shpack "$@"; fi

sudo unshare --root=rootfs --wd=/shpack --setuid "$(id -u)" --setgid "$(id -g)" \
    /bin/sh -c "PATH='$BP'; export PATH; exec \"\$@\"" sh "$@"
