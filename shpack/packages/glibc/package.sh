# SPDX-License-Identifier: MIT

description "glibc 2.43 -- the production aarch64 libc, built by the crippled" \
            "gcc-16-boot0. Second half of the musl->glibc transition; every" \
            "later cap stage links against this."
homepage "https://www.gnu.org/software/libc/"
license "LGPL-2.1-or-later"

version 2.43 sha256=d9c86c6b5dbddb43a3e08270c5844fc5177d19442cf5b8df4be7c07cd5fa3831 \
    url=https://ftp.gnu.org/gnu/glibc/glibc-2.43.tar.xz

build_system generic

# Built by gcc-16-boot0 (unwrapped: glibc drives its own -nostdlib bootstrap).
# binutils@2.46.0-musl as/ld; kernel headers via --with-headers. Needs python
# (gen-as-const), bison+m4 (intl/plural.c), make >= 4, gawk@5.3.1 (configure
# rejects gawk < 3.1.2).
depends_on gcc-boot@16.1.0 binutils@2.46.0-musl linux-headers gmake python bison m4 \
    sed@4.9-musl gawk@5.3.1 grep@2.4-musl diffutils tar@1.35-musl xz@5.2.5-musl

install() {
    local triple cc headers python n b
    triple=$(triple gnu)
    cc=$(prefix_of gcc-boot)/bin/gcc
    headers=$(prefix_of linux-headers)
    python=$(prefix_of python)

    # glibc requires an out-of-tree build.
    mkdir -p build
    cd build
    "$sh" ../configure \
        "CONFIG_SHELL=$sh" \
        "SHELL=$sh" \
        CC="$cc" \
        "CFLAGS=-g -O2 $file_prefix_map $debug_prefix_map" \
        "BASH_SHELL=$sh" \
        "PYTHON=$python/bin/python3" \
        --build="$triple" \
        --host="$triple" \
        --prefix="$PREFIX" \
        --with-headers="$headers/include" \
        --enable-kernel=4.18.0 \
        --disable-nls \
        --disable-werror \
        --disable-profile \
        --with-default-link=no

    make $makejobs
    make install

    # Make <prefix>/include complete: symlink the kernel headers beside glibc's
    # so one --with-native-system-header-dir covers both for the shipped gcc.
    for n in "$headers"/include/*; do
        b=${n##*/}
        [ -e "$PREFIX/include/$b" ] || ln -s "$n" "$PREFIX/include/$b"
    done
}
