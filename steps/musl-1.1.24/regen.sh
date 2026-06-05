#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# regen.sh -- regenerate every committed, host-produced build input for the
# musl 1.1.24 step, from a PRISTINE musl 1.1.24 tarball. Run on the host (needs
# sed, tar, make, python3); never in the chroot. Outputs, all committed:
#   generated/bits/{alltypes,syscall}.h, generated/internal/version.h
#       musl's three generated headers for x86_64 (the chroot has no sed/awk).
#       alltypes.h carries the __musl_va_list_t form from patch 0040.
#   sysinclude.tar
#       flat, merged PUBLIC header set, untarred into tcc's include dir in the
#       chroot (the in-chroot `cp` has no -r, so the bits/ overlay -- generic
#       then arch then generated -- is flattened here once). Headers only; the
#       musl *sources* are never repackaged (pristine tarball is the distfile).
#   simple-patches/, newsrc/, apply-*.kaem, build-libc-*.kaem
#       produced by regen.py (see there).
#
# Usage: ./regen.sh [MUSL_TARBALL]
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=1.1.24
ARCH=x86_64
MUSL_TARBALL=${1:-/home/harmen/spack/var/spack/cache/_source-cache/archive/13/1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3.tar.gz}
[ -f "$MUSL_TARBALL" ] || { echo "musl tarball not found: $MUSL_TARBALL" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
tar -xzf "$MUSL_TARBALL" -C "$W"
PRISTINE="$W/musl-$VERSION"
[ -d "$PRISTINE" ] || { echo "unpacked tree not at $PRISTINE" >&2; exit 1; }

# Patched copy: drives the generated headers (patched alltypes.h.in), the public
# header set, and the authoritative full source list. Fragments themselves are
# derived from the PRISTINE tree by regen.py.
cp -r "$PRISTINE" "$W/patched"
cd "$W/patched"
for p in "$HERE"/patches/*.patch; do
    patch -p1 --no-backup-if-mismatch < "$p" >/dev/null
done

echo "== generated/ headers =="
mkdir -p "$HERE/generated/bits" "$HERE/generated/internal"
sed -f tools/mkalltypes.sed \
    "arch/$ARCH/bits/alltypes.h.in" include/alltypes.h.in > "$HERE/generated/bits/alltypes.h"
cp "arch/$ARCH/bits/syscall.h.in" "$HERE/generated/bits/syscall.h"
sed -n 's/__NR_/SYS_/p' "arch/$ARCH/bits/syscall.h.in" >> "$HERE/generated/bits/syscall.h"
printf '#define VERSION "%s"\n' "$VERSION" > "$HERE/generated/internal/version.h"
grep -q __musl_va_list_t "$HERE/generated/bits/alltypes.h" \
    || { echo "alltypes.h lacks __musl_va_list_t (0040 not applied?)" >&2; exit 1; }

echo "== sysinclude.tar (flat public headers) =="
SYS="$W/sys"
mkdir -p "$SYS/bits"
( cd include && find . -name '*.h' -exec cp --parents {} "$SYS/" \; )
cp arch/generic/bits/*.h "$SYS/bits/"
cp "arch/$ARCH/bits/"*.h  "$SYS/bits/" 2>/dev/null || true
cp "$HERE/generated/bits/"*.h "$SYS/bits/"
( cd "$SYS" && tar --format=ustar -cf "$HERE/sysinclude.tar" * )

echo "== full source list (make -n; complex + arch-asm math removed first) =="
# Remove src/complex (tcc can't parse _Complex) and the x86_64 asm math shims so
# musl's Makefile selects the portable generic src/math/*.c instead. make -n then
# prints the authoritative, override-resolved compile list -- we keep src/ only
# (crt is built explicitly by pass1.kaem).
rm -rf src/complex "src/math/$ARCH"
./configure --target="$ARCH-linux-musl" --disable-shared >/dev/null 2>&1
make -n 2>/dev/null | grep -E ' -c -o ' | awk '{print $NF}' \
    | grep '^src/' | sort -u > "$W/full.files"
echo "   full libc sources: $(wc -l < "$W/full.files")"

echo "== regen.py (fragments + verify + kaem) =="
python3 "$HERE/regen.py" "$PRISTINE" "$W/full.files"

echo "regen.sh done."
