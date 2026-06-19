# SPDX-License-Identifier: MIT

description "Expat 2.8.1 -- a stream-oriented XML parser library written in C." \
            "Small autotools build."
homepage "https://libexpat.github.io/"
license "MIT"

# GitHub release tarball (R_2_8_1/expat-2.8.1.tar.bz2).
version 2.8.1 sha256=f5833dd2e1cd7739ec9182804a1a29c4f0cc7c2f26b633d3a2188b7766a88ecb \
    url=https://github.com/libexpat/libexpat/releases/download/R_2_8_1/expat-2.8.1.tar.bz2

build_system autotools

depends_on compiler-wrapper gmake

configure_args() {
    # --without-docbook (no doc toolchain) + --enable-static, per Spack. No
    # libbsd: glibc 2.43 provides getrandom for expat's entropy source. Explicit
    # glibc triple (no uname/config.guess in the sandbox).
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        --build="$t" \
        --host="$t" \
        --without-docbook \
        --enable-static
}
