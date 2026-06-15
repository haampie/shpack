# SPDX-License-Identifier: MIT

description "Multiple-precision complex arithmetic library (gcc prerequisite)"
homepage "https://www.multiprecision.org/mpc/"
license "LGPL-3.0-or-later"

version 1.0.3 sha256=617decc6ea09889fb08ede330917a00b16809b8db88c29c31bfbb49cbf88ecc3 \
    url=https://ftpmirror.gnu.org/mpc/mpc-1.0.3.tar.gz

build_system autotools

depends_on tcc musl@1.1.24 gmake binutils@2.30-musl gmp mpfr grep gawk@3.0.4

configure_args() {
    # config.guess cannot probe this environment (uname says "unknown", no
    # /usr/bin/file), so pass an explicit triple, matching gmp/mpfr.
    triple=$(triple gnu unknown)
    printf '%s\n' \
        CC=tcc \
        CFLAGS=-DHAVE_ALLOCA_H \
        --build="$triple" \
        --host="$triple" \
        --with-gmp="$(prefix_of gmp)" \
        --with-mpfr="$(prefix_of mpfr)" \
        --enable-static \
        --disable-shared
}
