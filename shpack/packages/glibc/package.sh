# SPDX-License-Identifier: MIT

description "glibc 2.43 -- the production aarch64 libc, built by the crippled" \
            "gcc-16-boot0. Second half of the musl->glibc transition; every" \
            "later cap stage links against this."
homepage "https://www.gnu.org/software/libc/"
license "LGPL-2.1-or-later"

# sha256 of the .tar.xz (ftp.gnu.org).
version 2.43 sha256=d9c86c6b5dbddb43a3e08270c5844fc5177d19442cf5b8df4be7c07cd5fa3831 \
    url=https://ftp.gnu.org/gnu/glibc/glibc-2.43.tar.xz

build_system generic

# Built by gcc-16-boot0 (unwrapped: glibc drives -nostdlib for its own
# bootstrap, no chicken-and-egg). binutils@2.46.0-musl as/ld (build+run). Kernel
# headers via --with-headers (build+run: we symlink them into our include/).
# Needs python (gen-as-const), bison+m4 (intl/plural.c), make >= 4. gawk@5.3.1 (not
# the seed gawk 3.0.4): glibc 2.43's configure rejects gawk < 3.1.2 as too old.
depends_on gcc-boot@16.1.0 binutils@2.46.0-musl linux-headers gmake python bison m4 \
    sed gawk@5.3.1 grep diffutils tar xz

setup_build_environment() {
    # Don't let inherited include paths shadow glibc's own headers.
    unset C_INCLUDE_PATH
    unset CPLUS_INCLUDE_PATH
}

install() {
    local triple cc headers python n
    triple=$(triple gnu)
    cc=$(prefix_of gcc-boot)/bin/gcc
    headers=$(prefix_of linux-headers)
    python=$(prefix_of python)

    # glibc requires an out-of-tree build.
    mkdir -p build
    cd build
    "$CONFIG_SHELL" ../configure \
        "CONFIG_SHELL=$CONFIG_SHELL" \
        "SHELL=$CONFIG_SHELL" \
        CC="$cc" \
        "BASH_SHELL=$CONFIG_SHELL" \
        "PYTHON=$python/bin/python3" \
        --build="$triple" \
        --host="$triple" \
        --prefix="$PREFIX" \
        --with-headers="$headers/include" \
        --enable-kernel=3.2.0 \
        --disable-nls \
        --disable-werror \
        --disable-profile \
        --with-default-link=no

    make $MAKEJOBS
    make install

    # Make <prefix>/include a complete /usr/include: glibc installs the libc
    # headers; symlink in the kernel headers (linux/, asm/, asm-generic/, ...)
    # so one --with-native-system-header-dir=<prefix>/include covers both for
    # the shipped gcc.
    for n in "$headers"/include/*; do
        b=${n##*/}
        [ -e "$PREFIX/include/$b" ] || ln -s "$n" "$PREFIX/include/$b"
    done
}
