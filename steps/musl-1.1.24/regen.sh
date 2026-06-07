#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# regen.sh -- regenerate every committed, host-produced build input for the
# musl 1.1.24 step, from a PRISTINE musl 1.1.24 tarball. Run on the host (needs
# sed, tar, make, python3); never in the chroot. Outputs, all committed:
#   <arch>/generated/bits/{alltypes,syscall}.h, <arch>/generated/internal/version.h
#       musl's three generated headers for the arch (the chroot has no sed/awk).
#       alltypes.h carries the __musl_va_list_t form from the va_list patch.
#       (<arch> is the chroot-facing name: amd64 / arm64.)
#   sysinclude.tar
#       ONE combined, flat, merged PUBLIC header set with per-arch subtrees
#       amd64/<headers> and arm64/<headers>, untarred into tcc's include dir in
#       the chroot (the in-chroot `cp` has no -r, so the bits/ overlay -- generic
#       then arch then generated -- is flattened here once). Headers only; the
#       musl *sources* are never repackaged (pristine tarball is the distfile).
#       The header set needs NO cross-toolchain (only `make -n` below does), so
#       BOTH arch subtrees are always rebuilt here -- a single regen produces the
#       complete combined tar regardless of which ARCH is passed.
#   <arch>/{apply-full,build-libc-subset,build-libc-full,copy-newsrc}.kaem,
#   <arch>/newsrc/, simple-patches/
#       produced by regen.py (see there). Only the passed ARCH's per-arch outputs
#       are rewritten; the other arch's stay untouched.
#
# Usage: ./regen.sh [ARCH] [MUSL_TARBALL]   (ARCH in x86_64|aarch64, default x86_64)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=1.1.24
ARCH=${1:-x86_64}
MUSL_TARBALL=${2:-/home/harmen/spack/var/spack/cache/_source-cache/archive/13/1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3.tar.gz}
[ -f "$MUSL_TARBALL" ] || { echo "musl tarball not found: $MUSL_TARBALL" >&2; exit 1; }

case "$ARCH" in
    x86_64)  OUT_DIR=amd64; CONFTGT=x86_64-linux-musl;  CONFCC= ;;
    aarch64) OUT_DIR=arm64; CONFTGT=aarch64-linux-musl; CONFCC="CC=aarch64-linux-gnu-gcc" ;;
    *) echo "unknown ARCH: $ARCH (want x86_64 or aarch64)" >&2; exit 1 ;;
esac
GENDIR="$HERE/$OUT_DIR/generated"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
tar -xzf "$MUSL_TARBALL" -C "$W"
PRISTINE="$W/musl-$VERSION"
[ -d "$PRISTINE" ] || { echo "unpacked tree not at $PRISTINE" >&2; exit 1; }

# Apply only the given arch's patch set (shared 0006 + the arch-specific patches;
# same selection as regen.py) to a fresh copy of the pristine tree at $2.
patch_tree() {  # $1=musl-arch  $2=dest-dir
    cp -r "$PRISTINE" "$2"
    ( cd "$2"
      for p in "$HERE"/patches/*.patch; do
          b=$(basename "$p")
          case "$b" in
              aarch64-*) [ "$1" = aarch64 ] || continue ;;
              0006-*)    : ;;                           # shared
              *)         [ "$1" = x86_64 ]  || continue ;;
          esac
          patch -p1 --no-backup-if-mismatch < "$p" >/dev/null
      done )
}

# Patched copy of THIS arch: drives the generated headers (patched alltypes.h.in)
# and the full source list. Fragments themselves are derived from the PRISTINE
# tree by regen.py.
patch_tree "$ARCH" "$W/patched"
cd "$W/patched"

echo "== $OUT_DIR/generated/ headers ($ARCH) =="
mkdir -p "$GENDIR/bits" "$GENDIR/internal"
sed -f tools/mkalltypes.sed \
    "arch/$ARCH/bits/alltypes.h.in" include/alltypes.h.in > "$GENDIR/bits/alltypes.h"
cp "arch/$ARCH/bits/syscall.h.in" "$GENDIR/bits/syscall.h"
sed -n 's/__NR_/SYS_/p' "arch/$ARCH/bits/syscall.h.in" >> "$GENDIR/bits/syscall.h"
printf '#define VERSION "%s"\n' "$VERSION" > "$GENDIR/internal/version.h"
grep -q __musl_va_list_t "$GENDIR/bits/alltypes.h" \
    || { echo "alltypes.h lacks __musl_va_list_t (va_list patch not applied?)" >&2; exit 1; }

# Stage one arch's flat PUBLIC header set into $STAGE/<out_dir>. The bits/ overlay
# order matches the chroot consumer: arch/generic, then arch/<a> (overrides),
# then the generated alltypes/syscall (overrides). Pure sed/cp -- no cross cc.
STAGE="$W/sys"
stage_headers() {  # $1=musl-arch  $2=out_dir  $3=patched-tree
    a=$1; out=$2; t=$3
    d="$STAGE/$out"
    rm -rf "$d"; mkdir -p "$d/bits"
    ( cd "$t/include" && find . -name '*.h' -exec cp --parents {} "$d/" \; )
    cp "$t/arch/generic/bits/"*.h "$d/bits/"
    cp "$t/arch/$a/bits/"*.h "$d/bits/" 2>/dev/null || true
    sed -f "$t/tools/mkalltypes.sed" \
        "$t/arch/$a/bits/alltypes.h.in" "$t/include/alltypes.h.in" > "$d/bits/alltypes.h"
    cp "$t/arch/$a/bits/syscall.h.in" "$d/bits/syscall.h"
    sed -n 's/__NR_/SYS_/p' "$t/arch/$a/bits/syscall.h.in" >> "$d/bits/syscall.h"
}

echo "== sysinclude.tar (combined flat public headers: amd64 + arm64) =="
rm -rf "$STAGE"; mkdir -p "$STAGE"
# Reuse $W/patched for whichever arch matches; build a fresh tree for the other.
for a in x86_64 aarch64; do
    case "$a" in x86_64) o=amd64 ;; aarch64) o=arm64 ;; esac
    if [ "$a" = "$ARCH" ]; then
        t="$W/patched"
    else
        t="$W/patched-$a"
        patch_tree "$a" "$t"
    fi
    stage_headers "$a" "$o" "$t"
done
# Reproducible tar (fixed mtime/owner, sorted names) so re-runs are byte-stable.
( cd "$STAGE" && find . -type f | LC_ALL=C sort | sed 's#^\./##' \
    | tar --format=ustar --mtime=@0 --owner=0 --group=0 --numeric-owner \
          -cf "$HERE/sysinclude.tar" -T - )

echo "== full source list (make -n; complex + arch-asm math removed first) =="
# Remove src/complex (tcc can't parse _Complex) and the arch asm math shims so
# musl's Makefile selects the portable generic src/math/*.c instead. make -n then
# prints the authoritative, override-resolved compile list -- we keep src/ only
# (crt is built explicitly by pass1.kaem).
cd "$W/patched"
rm -rf src/complex "src/math/$ARCH"
./configure --target="$CONFTGT" --disable-shared $CONFCC >/dev/null 2>&1
make -n 2>/dev/null | grep -E ' -c -o ' | awk '{print $NF}' \
    | grep '^src/' | sort -u > "$W/full.files"
echo "   full libc sources: $(wc -l < "$W/full.files")"

echo "== regen.py (fragments + verify + kaem, $ARCH) =="
python3 "$HERE/regen.py" "$ARCH" "$PRISTINE" "$W/full.files"

echo "regen.sh done ($ARCH)."
