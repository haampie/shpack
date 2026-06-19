# SPDX-License-Identifier: MIT

description "Multiple-precision floating-point library (gcc prerequisite)"
homepage "https://www.mpfr.org/"
license "LGPL-2.1-or-later"

version 2.4.2 sha256=246d7e184048b1fc48d3696dd302c9774e24e921204221540745e5464022b637 \
    url=https://ftpmirror.gnu.org/mpfr/mpfr-2.4.2.tar.gz

build_system autotools

depends_on tcc musl@1.1.24 gmake binutils@2.30-musl gmp grep@2.4-musl gawk@3.0.4

configure_args() {
    local triple
    # config.sub predates musl; the triple is cosmetic for this native
    # pure-math-library build, so use a -gnu triple the old config.sub knows.
    triple=$(triple gnu unknown)
    printf '%s\n' \
        CC=tcc \
        CFLAGS=-DHAVE_ALLOCA_H \
        --build="$triple" \
        --host="$triple" \
        --with-gmp="$(prefix_of gmp)" \
        --enable-static \
        --disable-shared
}
