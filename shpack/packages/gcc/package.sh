# SPDX-License-Identifier: MIT

description "GCC 4.7 (Linaro): the first real C compiler; Linaro because" \
            "FSF GCC 4.7 lacks native aarch64 support"
homepage "https://launchpad.net/gcc-linaro"
license "GPL-3.0-or-later"

version 4.7-2013.11 sha256=d0ea2c72ceb66d3851986840dd8962941824a2980a8aca2a800abb5b489acedf \
    url=https://launchpadlibrarian.net/156843777/gcc-linaro-4.7-2013.11.tar.bz2

build_system autotools

depends_on tcc musl gmake binutils gmp mpfr mpc grep gawk diffutils m4 findutils

# libiberty's C_alloca conflicts with musl's alloca/__builtin_alloca; rename
# C_alloca -> alloca throughout (same fix as Guix).
patch 0001-alloca.patch

# Work around a tcc 0.9.27 AArch64 spill-slot collision that miscompiles a
# nested 16-byte-struct-return call in set_lattice_value, crashing the
# tcc-built cc1 in the tree-ccp pass (libgcc2.c __cmpti2). Splitting the call
# into a temporary avoids it. See bugs/tcc-aarch64-nested-struct-return-spill.md.
patch 0002-tree-ssa-ccp-spill.patch

# libstdc++'s gnu-linux os_defines.h uses __GLIBC_PREREQ(2,15), undefined on
# musl; guard it so the gets() check evaluates false.
patch 0003-libstdcxx-musl-glibc-prereq.patch

# gnu-linux ctype uses glibc-internal mask names and __ctype_b_loc(), absent
# on musl; swap in the portable config/os/generic ctype (same approach as
# Alpine / musl-cross-make).
patch 0004-libstdcxx-generic-ctype.patch

# GCC requires an out-of-tree build dir: configure in _build/ and stay there
# (phases share one shell, so the cd persists into build/install).
configure() {
    case "$ARCH" in
        amd64)   triple=x86_64-unknown-linux-musl ;;
        aarch64) triple=aarch64-unknown-linux-musl ;;
    esac
    mkdir -p _build
    cd _build
    # C only is built (--disable-build-with-cxx), but gcc/configure still
    # runs a fatal AC_PROG_CXXCPP probe; `tcc -E` satisfies it (tcc cannot
    # compile C++ but preprocesses it fine; no C++ is actually compiled by
    # the stage1 tools).
    ../configure \
        CC=tcc \
        CC_FOR_BUILD=tcc \
        CXX=tcc \
        "CXXCPP=tcc -E" \
        CFLAGS=-DHAVE_ALLOCA_H \
        MAKEINFO=true \
        --prefix="$PREFIX" \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --with-sysroot="$(prefix_of musl)" \
        --with-native-system-header-dir=/include \
        --with-gmp="$(prefix_of gmp)" \
        --with-mpfr="$(prefix_of mpfr)" \
        --with-mpc="$(prefix_of mpc)" \
        --with-as="$(prefix_of binutils)/bin/as" \
        --with-ld="$(prefix_of binutils)/bin/ld" \
        --enable-languages=c,c++ \
        --enable-static \
        --disable-shared \
        --enable-threads=single \
        --disable-threads \
        --disable-libstdcxx-pch \
        --disable-build-with-cxx \
        --disable-bootstrap \
        --disable-multilib \
        --disable-decimal-float \
        --disable-lto \
        --disable-lto-plugin \
        --disable-plugin \
        --disable-libatomic \
        --disable-libcilkrts \
        --disable-libgomp \
        --disable-libitm \
        --disable-libmudflap \
        --disable-libquadmath \
        --disable-libsanitizer \
        --disable-libssp \
        --disable-libvtv
}

build_args() {
    printf '%s\n' MAKEINFO=true
}

install_targets() {
    printf '%s\n' install MAKEINFO=true
}
