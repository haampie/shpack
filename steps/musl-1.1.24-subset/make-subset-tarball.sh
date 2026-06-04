#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Repackage a minimal, MIT-compliant subset of musl 1.1.24 sufficient to build the
# bootstrap tcc, dropping GNU mes libc. Produces musl-1.1.24-subset.tar.gz containing
# exact musl source files (subset), the headers needed to compile them, musl's three
# generated headers (pre-generated for x86_64), our glue, and musl's COPYRIGHT notice.
#
# Usage: ./make-subset-tarball.sh <path-to-musl-1.1.24-source-tree> [output-dir]
set -eu

MUSL=${1:?usage: make-subset-tarball.sh <musl-1.1.24-srcdir> [outdir]}
OUT=${2:-.}
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=musl-1.1.24-subset
STAGE=$(mktemp -d)
DST=$STAGE/$NAME

mkdir -p "$DST"

# 1. exact subset source files (the 120 from musl-subset.files), plus the per-directory
#    private headers they #include relative to themselves (e.g. src/time/time_impl.h,
#    src/stdio/putc.h, src/errno/__strerror.h, src/multibyte/internal.h).
srcdirs=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$DST/$(dirname "$f")"
    cp "$MUSL/$f" "$DST/$f"
    srcdirs="$srcdirs $(dirname "$f")"
done < "$HERE/musl-subset.files"
for d in $(echo "$srcdirs" | tr ' ' '\n' | sort -u); do
    for h in "$MUSL/$d"/*.h; do
        [ -e "$h" ] && cp "$h" "$DST/$d/"
    done
done

# 2. crt entry C file (crt1.c #includes "crt_arch.h", which ships inside arch/x86_64)
mkdir -p "$DST/crt"
cp "$MUSL/crt/crt1.c" "$DST/crt/crt1.c"

# 3. headers needed to compile the subset (small; trimming headers is not worth it)
for d in include arch/x86_64 arch/generic src/include src/internal; do
    mkdir -p "$DST/$d"
    cp -r "$MUSL/$d/." "$DST/$d/"
done

# 4. musl's three generated headers, pre-generated for x86_64 (no sed/awk at build time)
mkdir -p "$DST/obj/include/bits" "$DST/obj/src/internal"
cp "$HERE/generated/bits/alltypes.h"     "$DST/obj/include/bits/alltypes.h"
cp "$HERE/generated/bits/syscall.h"      "$DST/obj/include/bits/syscall.h"
cp "$HERE/generated/internal/version.h"  "$DST/obj/src/internal/version.h"

# 5. our glue + the file list + the MIT notice
cp -r "$HERE/glue"            "$DST/glue"
cp    "$HERE/musl-subset.files" "$DST/musl-subset.files"
cp    "$MUSL/COPYRIGHT"       "$DST/COPYRIGHT"
cat > "$DST/README" <<EOF
Minimal subset of musl 1.1.24 (MIT licensed; see COPYRIGHT), repackaged to bootstrap
tcc without GNU mes. Exact upstream source files; obj/ holds the three pre-generated
headers for x86_64. glue/ replaces musl's __errno_location and __libc_start_main.
EOF

mkdir -p "$OUT"
( cd "$STAGE" && tar -czf "$NAME.tar.gz" "$NAME" )
mv "$STAGE/$NAME.tar.gz" "$OUT/"
rm -rf "$STAGE"
echo "wrote $OUT/$NAME.tar.gz"
