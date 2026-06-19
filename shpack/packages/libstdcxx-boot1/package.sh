# SPDX-License-Identifier: MIT

description "Intermediate aarch64 libstdc++ (static-only) from GCC 16 source." \
            "gcc-boot@16.1.0 was built --disable-libstdc++-v3, but binutils" \
            "(gprofng) and gcc's build tools need to link one."
homepage "https://gcc.gnu.org/"
license "GPL-3.0-or-later"

# Same GCC 16 source as gcc-boot@16.1.0 / gcc; only libstdc++-v3 is configured.
version 16.1.0 sha256=50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79 \
    url=https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz

build_system generic

# Built by gcc-boot-wrapper against glibc 2.43 (static libstdc++.a, no .so).
# linux-headers: autoconf CPP sanity check. findutils: libtool merges the
# convenience archives into libstdc++.a by enumerating objects with find --
# without it the archive ships only compatibility*.o and C++ links break.
depends_on gcc-boot-wrapper glibc linux-headers gmake sed@4.9-musl grep@2.4-musl gawk@5.3.1 diffutils \
    findutils tar@1.35-musl xz@5.2.5-musl

setup_build_environment() {
    # libstdc++ #include_next <stdlib.h> etc. must reach glibc's headers.
    local glibc; glibc=$(prefix_of glibc)
    export CPLUS_INCLUDE_PATH="$glibc/include"
    export C_INCLUDE_PATH="$glibc/include"
    export LIBRARY_PATH="$glibc/lib"
}


edit() {
    # libstdc++-v3 configure probes `g++ -v`; no-op it so it can't fail when the
    # compiler binary name differs.
    sed -i 's/g++ -v/true/' libstdc++-v3/configure

    # `date > stamp-*` just touches a make stamp; `date` isn't in the seed
    # coreutils and a real timestamp is non-reproducible -- use `touch`.
    sed -i 's/date > stamp/touch stamp/g' libstdc++-v3/src/Makefile.in
}

install() {
    local triple gcc
    triple=$(triple gnu)
    gcc=$(prefix_of gcc-boot-wrapper)

    mkdir -p build
    cd build
    # Keep threads + dual-abi defaults on: GCC 16's C++20 tzdb.cc needs the cxx11
    # ABI's <chrono> tzdb. --disable-shared so downstream links it statically.
    #
    # LIBS=-lm: libstdc++'s AC_CHECK_FUNCS link tests (ceilf, cosf, ...) don't add
    # -lm, so they'd come out "no" -> _GLIBCXX_HAVE_CEILF undefined -> <cmath>
    # drops `using ::ceilf` -> the C++23 `std` module fails. Harmless to the .a.
    "$sh" ../libstdc++-v3/configure \
        "CONFIG_SHELL=$sh" \
        "CC=$gcc/bin/gcc" \
        "CXX=$gcc/bin/g++" \
        "CFLAGS=-g -O2 $file_prefix_map" \
        "CXXFLAGS=-g -O2 $file_prefix_map" \
        MAKEINFO=true \
        LIBS=-lm \
        --build="$triple" \
        --host="$triple" \
        --prefix="$PREFIX" \
        --disable-multilib \
        --disable-nls \
        --disable-shared \
        --disable-libstdcxx-pch \
        --with-gxx-include-dir="$PREFIX/include"

    make $makejobs
    make install
}
