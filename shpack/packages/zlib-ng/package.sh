# SPDX-License-Identifier: MIT

description "zlib-ng 2.3.3 -- a zlib replacement with optimizations for modern" \
            "systems. Built in --zlib-compat mode, so it installs zlib.h and a" \
            "drop-in libz.so.1 carrying the classic zlib ABI."
homepage "https://github.com/zlib-ng/zlib-ng"
license "Zlib"

# GitHub source archive (extracts zlib-ng-2.3.3/). The archive carries a
# hand-written ./configure (autotools-free), so no autoconf is needed.
version 2.3.3 sha256=f9c65aa9c852eb8255b636fd9f07ce1c406f061ec19a2e7d508b318ca0c907d1 \
    url=https://github.com/zlib-ng/zlib-ng/archive/2.3.3.tar.gz \
    fname=zlib-ng-2.3.3.tar.gz

build_system generic

# compiler-wrapper supplies the final gcc 16 + glibc loader/rpath, like zlib did.
depends_on compiler-wrapper gmake

install() {
    # zlib-ng ships its own configure (not autotools); it honours $CC.
    # --zlib-compat builds the classic-ABI libz.so.1 + zlib.h, so anything that
    # links plain zlib links this with no source changes.
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    "$sh" ./configure --prefix="$PREFIX" --zlib-compat
    make $makejobs
    make install
}
