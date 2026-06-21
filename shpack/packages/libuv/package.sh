# SPDX-License-Identifier: MIT

description "libuv 1.52.0 -- cross-platform asynchronous I/O library. Static" \
            "libuv only."
homepage "https://libuv.org/"
license "MIT"

# The -dist tarball ships a pregenerated configure (no autoconf in the bootstrap).
version 1.52.0 sha256=a34f3eaabff4cb9e08b17a25b459f8330e6536d256a3180e249e8cb2bb49ccd6 \
    url=https://dist.libuv.org/dist/v1.52.0/libuv-v1.52.0-dist.tar.gz

build_system autotools

depends_on compiler-wrapper gmake
depends_on dash

configure_args() {
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        --build="$t" \
        --host="$t" \
        --enable-static \
        --disable-shared
}
