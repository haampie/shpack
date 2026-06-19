# SPDX-License-Identifier: MIT

description "GNU multiple-precision arithmetic library (gcc prerequisite)"
homepage "https://gmplib.org/"
license "LGPL-3.0-or-later"

version 4.3.2 sha256=7be3ad1641b99b17f6a8be6a976f1f954e997c41e919ad7e0c418fe848c13c97 \
    url=https://ftpmirror.gnu.org/gmp/gmp-4.3.2.tar.gz

build_system autotools

depends_on tcc musl@1.1.24 gmake binutils@2.30-musl m4 grep@2.4-musl gawk@3.0.4

configure_args() {
    # --build/--host=none-... forces GMP into generic-C mode: no hand-written
    # x86_64/aarch64 assembly, which tcc cannot assemble.
    printf '%s\n' \
        CC=tcc \
        CFLAGS=-DHAVE_ALLOCA_H \
        --build=none-unknown-linux-gnu \
        --host=none-unknown-linux-gnu \
        --enable-static \
        --disable-shared
}
