# SPDX-License-Identifier: MIT

description "zlib 1.3.1 -- compression library. First glibc-linked application" \
            "library; Python (zlib/gzip/zipfile) and many tools need it."
homepage "https://zlib.net/"
license "Zlib"

version 1.3.1 sha256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23 \
    url=https://zlib.net/fossils/zlib-1.3.1.tar.gz

build_system generic

# compiler-wrapper pulls in the final gcc + glibc and shadows gcc on PATH so the
# produced libz.so.1 gets glibc's loader/rpath from the gcc specs file.
depends_on compiler-wrapper gmake

install() {
    # zlib ships a hand-written configure (not autotools); it honours $CC.
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    "$sh" ./configure --prefix="$PREFIX"
    make $makejobs
    make install
}
