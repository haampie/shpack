#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# regen.sh -- regenerate every committed, host-produced build input for the
# musl 1.1.24 step, from a PRISTINE musl 1.1.24 tarball. Run on the host (needs
# sed, tar, make, python3); never in the chroot. Outputs, all committed:
#   generated[/aarch64]/bits/{alltypes,syscall}.h, .../internal/version.h
#       musl's three generated headers for the arch (the chroot has no sed/awk).
#       alltypes.h carries the __musl_va_list_t form from the va_list patch.
#   sysinclude[.aarch64].tar
#       flat, merged PUBLIC header set, untarred into tcc's include dir in the
#       chroot (the in-chroot `cp` has no -r, so the bits/ overlay -- generic
#       then arch then generated -- is flattened here once). Headers only; the
#       musl *sources* are never repackaged (pristine tarball is the distfile).
#   simple-patches/, newsrc/, apply-*.kaem, build-libc-*.kaem, copy-newsrc*.kaem
#       produced by regen.py (see there).
#
# x86_64 outputs keep their bare names; aarch64 outputs are arch-suffixed, so a
# regen of one arch never clobbers the other.
#
# Usage: ./regen.sh [ARCH] [MUSL_TARBALL]   (ARCH in x86_64|aarch64, default x86_64)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=1.1.24
ARCH=${1:-x86_64}
MUSL_TARBALL=${2:-/home/harmen/spack/var/spack/cache/_source-cache/archive/13/1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3.tar.gz}
[ -f "$MUSL_TARBALL" ] || { echo "musl tarball not found: $MUSL_TARBALL" >&2; exit 1; }

case "$ARCH" in
    x86_64)  GENDIR="$HERE/generated";         SYSTAR="$HERE/sysinclude.tar";         CONFTGT=x86_64-linux-musl;  CONFCC= ;;
    aarch64) GENDIR="$HERE/generated/aarch64"; SYSTAR="$HERE/sysinclude.aarch64.tar"; CONFTGT=aarch64-linux-musl; CONFCC="CC=aarch64-linux-gnu-gcc" ;;
    *) echo "unknown ARCH: $ARCH (want x86_64 or aarch64)" >&2; exit 1 ;;
esac

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
tar -xzf "$MUSL_TARBALL" -C "$W"
PRISTINE="$W/musl-$VERSION"
[ -d "$PRISTINE" ] || { echo "unpacked tree not at $PRISTINE" >&2; exit 1; }

# Patched copy: drives the generated headers (patched alltypes.h.in), the public
# header set, and the authoritative full source list. Fragments themselves are
# derived from the PRISTINE tree by regen.py. Apply only THIS arch's patch set
# (shared 0006 + the arch-specific patches; same selection as regen.py).
cp -r "$PRISTINE" "$W/patched"
cd "$W/patched"
for p in "$HERE"/patches/*.patch; do
    b=$(basename "$p")
    case "$b" in
        aarch64-*) [ "$ARCH" = aarch64 ] || continue ;;
        0006-*)    : ;;                           # shared
        *)         [ "$ARCH" = x86_64 ]  || continue ;;
    esac
    patch -p1 --no-backup-if-mismatch < "$p" >/dev/null
done

echo "== generated/ headers ($ARCH) =="
mkdir -p "$GENDIR/bits" "$GENDIR/internal"
sed -f tools/mkalltypes.sed \
    "arch/$ARCH/bits/alltypes.h.in" include/alltypes.h.in > "$GENDIR/bits/alltypes.h"
cp "arch/$ARCH/bits/syscall.h.in" "$GENDIR/bits/syscall.h"
sed -n 's/__NR_/SYS_/p' "arch/$ARCH/bits/syscall.h.in" >> "$GENDIR/bits/syscall.h"
printf '#define VERSION "%s"\n' "$VERSION" > "$GENDIR/internal/version.h"
grep -q __musl_va_list_t "$GENDIR/bits/alltypes.h" \
    || { echo "alltypes.h lacks __musl_va_list_t (va_list patch not applied?)" >&2; exit 1; }

echo "== sysinclude.tar (flat public headers, $ARCH) =="
SYS="$W/sys"
rm -rf "$SYS"; mkdir -p "$SYS/bits"
( cd include && find . -name '*.h' -exec cp --parents {} "$SYS/" \; )
cp arch/generic/bits/*.h "$SYS/bits/"
cp "arch/$ARCH/bits/"*.h  "$SYS/bits/" 2>/dev/null || true
cp "$GENDIR/bits/"*.h "$SYS/bits/"
# Reproducible tar (fixed mtime/owner, sorted names) so re-runs are byte-stable.
( cd "$SYS" && find . -type f | LC_ALL=C sort | sed 's#^\./##' \
    | tar --format=ustar --mtime=@0 --owner=0 --group=0 --numeric-owner \
          -cf "$SYSTAR" -T - )

echo "== full source list (make -n; complex + arch-asm math removed first) =="
# Remove src/complex (tcc can't parse _Complex) and the arch asm math shims so
# musl's Makefile selects the portable generic src/math/*.c instead. make -n then
# prints the authoritative, override-resolved compile list -- we keep src/ only
# (crt is built explicitly by pass1.kaem).
rm -rf src/complex "src/math/$ARCH"
./configure --target="$CONFTGT" --disable-shared $CONFCC >/dev/null 2>&1
make -n 2>/dev/null | grep -E ' -c -o ' | awk '{print $NF}' \
    | grep '^src/' | sort -u > "$W/full.files"
echo "   full libc sources: $(wc -l < "$W/full.files")"

echo "== regen.py (fragments + verify + kaem, $ARCH) =="
python3 "$HERE/regen.py" "$ARCH" "$PRISTINE" "$W/full.files"

echo "regen.sh done ($ARCH)."
