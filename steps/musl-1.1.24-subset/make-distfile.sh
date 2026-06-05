#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# make-distfile.sh -- produce distfiles/musl-1.1.24-subset.tar.gz reproducibly,
# host-side, from a PRISTINE musl 1.1.24 tarball plus the three vendored
# tcc-compat patches (patches/00{06,30,40}). It:
#   1. unpacks pristine musl 1.1.24;
#   2. applies patches 0006 (static N declarators), 0030 (r10/r8 syscall asm),
#      0040 (SysV va_list; creates src/stdarg/va_list.c);
#   3. regenerates musl's three generated headers into generated/ (so the repo's
#      committed copies match the patched tree -- alltypes.h must carry the
#      __musl_va_list_t form), using the host sed ONCE here (never in-chroot);
#   4. runs make-subset-tarball.sh to repackage the subset, and drops the
#      resulting musl-1.1.24-subset.tar.gz into distfiles/.
#
# Usage: ./make-distfile.sh [MUSL_TARBALL]
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)            # steps/musl-1.1.24-subset
REPO=$(cd "$HERE/../.." && pwd)
VERSION=1.1.24
ARCH=x86_64

MUSL_TARBALL=${1:-/home/harmen/spack/var/spack/cache/_source-cache/archive/13/1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3.tar.gz}
[ -f "$MUSL_TARBALL" ] || { echo "musl tarball not found: $MUSL_TARBALL" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$MUSL_TARBALL" -C "$WORK"
MUSL="$WORK/musl-$VERSION"
[ -d "$MUSL" ] || { echo "unpacked tree not at $MUSL" >&2; exit 1; }

# 1. apply the three amd64 tcc-compat patches
for p in 0006-Strip-C99-static-N-array-declarators.patch \
         0030-syscall-$ARCH.patch \
         0040-$ARCH-sysv-va_list.patch; do
    echo "  applying $p"
    ( cd "$MUSL" && patch -p1 --no-backup-if-mismatch < "$HERE/patches/$p" >/dev/null )
done

# 2. regenerate musl's three generated headers into the repo's generated/ dir
echo "  regenerating generated/{bits/alltypes.h,bits/syscall.h,internal/version.h}"
mkdir -p "$HERE/generated/bits" "$HERE/generated/internal"
sed -f "$MUSL/tools/mkalltypes.sed" \
    "$MUSL/arch/$ARCH/bits/alltypes.h.in" "$MUSL/include/alltypes.h.in" \
    > "$HERE/generated/bits/alltypes.h"
cp "$MUSL/arch/$ARCH/bits/syscall.h.in" "$HERE/generated/bits/syscall.h"
sed -n 's/__NR_/SYS_/p' "$MUSL/arch/$ARCH/bits/syscall.h.in" >> "$HERE/generated/bits/syscall.h"
printf '#define VERSION "%s"\n' "$VERSION" > "$HERE/generated/internal/version.h"
grep -q __musl_va_list_t "$HERE/generated/bits/alltypes.h" \
    || { echo "generated alltypes.h lacks __musl_va_list_t (0040 not applied?)" >&2; exit 1; }

# 3. repackage the subset and install it as a distfile
mkdir -p "$REPO/distfiles"
"$HERE/make-subset-tarball.sh" "$MUSL" "$REPO/distfiles"

echo "wrote $REPO/distfiles/musl-$VERSION-subset.tar.gz"
sha256sum "$REPO/distfiles/musl-$VERSION-subset.tar.gz"
