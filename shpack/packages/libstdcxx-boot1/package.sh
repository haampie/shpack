# SPDX-License-Identifier: MIT

description "Intermediate aarch64 libstdc++ (static-only) from GCC 16 source." \
            "gcc-boot@16.1.0 was built --disable-libstdc++-v3, but binutils-final" \
            "(gprofng) and gcc's build tools need to link one."
homepage "https://gcc.gnu.org/"
license "GPL-3.0-or-later"

# Same GCC 16 source as gcc-boot@16.1.0 / gcc; only libstdc++-v3 is configured.
version 16.1.0 sha256=50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79 \
    url=https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz

build_system generic

# Built by gcc-boot0-wrapped against glibc 2.43 (static libstdc++.a, no .so).
# linux-headers: autoconf CPP sanity check. find/diff: libtool merges the
# libsupc++/c++NN convenience archives into libstdc++.a by extracting them and
# enumerating objects with find -- without findutils, libstdc++.a ships only
# the compatibility*.o and every downstream C++ link breaks.
depends_on gcc-boot0-wrapped glibc linux-headers gmake sed grep gawk diffutils \
    findutils tar xz

setup_build_environment() {
    # libstdc++ #include_next <stdlib.h> etc. must reach glibc's headers.
    local glibc; glibc=$(prefix_of glibc)
    export CPLUS_INCLUDE_PATH="$glibc/include"
    export C_INCLUDE_PATH="$glibc/include"
    export LIBRARY_PATH="$glibc/lib"
}

triple_of() {
    case "$ARCH" in
        amd64)   printf x86_64-linux-gnu ;;
        aarch64) printf aarch64-linux-gnu ;;
    esac
}

install() {
    local triple gcc
    triple=$(triple_of)
    gcc=$(prefix_of gcc-boot0-wrapped)

    # libstdc++-v3 configure probes `g++ -v`; make it a no-op so the probe
    # cannot fail when the compiler binary name differs.
    sed -i 's/g++ -v/true/' libstdc++-v3/configure

    # The convenience-archive rules do `date > stamp-*` purely to touch a make
    # stamp. `date` isn't in the seed coreutils subset, and a real timestamp
    # would be non-reproducible anyway -- use `touch` (which the seed has).
    sed -i 's/date > stamp/touch stamp/g' libstdc++-v3/src/Makefile.in

    mkdir -p build
    cd build
    # Defaults (threads on, dual-abi on): glibc 2.43 has real pthreads and the
    # cxx11 ABI, both of which GCC 16's C++20 src/c++20/tzdb.cc requires (with
    # cxx11 ABI off, <chrono>'s tzdb omits zones/links but tzdb.cc references
    # them). --disable-shared so downstream links it statically.
    #
    # LIBS=-lm: glibc keeps ceilf/cosf/... in libm, and libstdc++'s native
    # AC_CHECK_FUNCS link tests (ceilf, cosf, ...) don't add -lm, so they'd come
    # out "no" -> _GLIBCXX_HAVE_CEILF undefined -> <cmath> omits `using ::ceilf`
    # -> the C++23 `std` module (std-clib.cc) fails ("ceilf not declared in
    # std"). Adding -lm lets those checks link. Harmless to the static archive
    # build (libstdc++.a is ar'd, not linked).
    ../libstdc++-v3/configure \
        CONFIG_SHELL=/bin/sh \
        "CC=$gcc/bin/gcc" \
        "CXX=$gcc/bin/g++" \
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

    make $MAKEJOBS
    make install
}
