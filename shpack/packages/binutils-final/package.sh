# SPDX-License-Identifier: MIT

description "Native aarch64 binutils 2.46 -- the first glibc-linked binutils." \
            "Built by gcc-boot0-wrapped against glibc 2.43; gprofng links the" \
            "static libstdcxx-boot1. The as/ld baked into the final GCC."
homepage "https://www.gnu.org/software/binutils/"
license "GPL-3.0-or-later"

# Separate recipe from binutils (2.30) and binutils@2.46.0 (2.46, musl/gcc9):
# this 2.46 is glibc-linked and is its own DAG node. Same isolation rationale
# as binutils@2.46.0.
version 2.46.0 sha256=0f3152632a2a9ce066f20963e9bb40af7cf85b9b6c409ed892fd0676e84ecd12 \
    url=https://ftp.gnu.org/gnu/binutils/binutils-2.46.0.tar.bz2

build_system autotools

# Built by gcc-boot0-wrapped against glibc 2.43. linux-headers: autoconf CPP
# sanity check. libstdcxx-boot1: gprofng is C++ and links the static
# libstdc++.a. binutils@2.46.0 supplies plain as/ld/ar on PATH for this build.
depends_on gcc-boot0-wrapped glibc linux-headers libstdcxx-boot1 binutils@2.46.0 \
    bison gmake sed grep gawk@3.0.4 diffutils tar

setup_build_environment() {
    # No host flex; 2.46 ships generated parsers (maintainer-mode off). Preseed
    # ac_cv_prog_lex_root so AC_PROG_LEX short-circuits.
    export ac_cv_prog_lex_root=lex.yy
    # glibc headers/libs + libgcc for the wrapped boot0 compiler.
    local glibc triple libstdcxx
    glibc=$(prefix_of glibc)
    triple=$(triple_of)
    libstdcxx=$(prefix_of libstdcxx-boot1)
    export C_INCLUDE_PATH="$glibc/include"
    # gprofng is C++ (#include <new>, <string>, ...). gcc-boot@16.1.0 was built
    # --disable-libstdc++-v3, so the wrapped boot0 compiler ships no C++ headers;
    # supply libstdcxx-boot1's. The triple subdir carries bits/c++config.h.
    export CPLUS_INCLUDE_PATH="$libstdcxx/include:$libstdcxx/include/$triple:$glibc/include"
    export LIBRARY_PATH="$glibc/lib"
}

triple_of() {
    case "$ARCH" in
        amd64)   printf x86_64-linux-gnu ;;
        aarch64) printf aarch64-linux-gnu ;;
    esac
}

configure_args() {
    local triple gcc libstdcxx
    triple=$(triple_of)
    gcc=$(prefix_of gcc-boot0-wrapped)
    libstdcxx=$(prefix_of libstdcxx-boot1)
    printf '%s\n' \
        CONFIG_SHELL=/bin/sh \
        "CC=$gcc/bin/gcc" \
        "CXX=$gcc/bin/g++" \
        MAKEINFO=true \
        "LDFLAGS=-L$libstdcxx/lib64 -L$libstdcxx/lib" \
        AR=ar AS=as NM=nm RANLIB=ranlib \
        OBJCOPY=objcopy OBJDUMP=objdump READELF=readelf STRIP=strip \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --prefix="$PREFIX" \
        --disable-multilib \
        --disable-werror \
        --disable-nls \
        --enable-deterministic-archives \
        --enable-64-bit-bfd
}
