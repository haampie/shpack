# SPDX-License-Identifier: MIT

description "Multiple-precision floating-point library (gcc prerequisite)"
homepage "https://www.mpfr.org/"
license "LGPL-2.1-or-later"

version 2.4.2 sha256=246d7e184048b1fc48d3696dd302c9774e24e921204221540745e5464022b637 \
    url=https://ftpmirror.gnu.org/mpfr/mpfr-2.4.2.tar.gz

build_system autotools

depends_on tcc musl gmake binutils gmp grep gawk

configure_args() {
    # config.sub predates musl; the triple is cosmetic for this native
    # pure-math-library build, so use a -gnu triple the old config.sub knows.
    case "$ARCH" in
        amd64)   triple=x86_64-unknown-linux-gnu ;;
        aarch64) triple=aarch64-unknown-linux-gnu ;;
    esac
    printf '%s\n' \
        CC=tcc \
        CFLAGS=-DHAVE_ALLOCA_H \
        --build="$triple" \
        --host="$triple" \
        --with-gmp="$(prefix_of gmp)" \
        --enable-static \
        --disable-shared
}
