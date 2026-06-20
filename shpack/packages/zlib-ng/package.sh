# SPDX-License-Identifier: MIT

description "zlib-ng 2.3.3 -- a zlib replacement with optimizations for modern" \
            "systems. Built in --zlib-compat mode, so it installs zlib.h and a" \
            "drop-in libz.so.1 carrying the classic zlib ABI."
homepage "https://github.com/zlib-ng/zlib-ng"
license "Zlib"

# GitHub source archive (extracts zlib-ng-2.3.3/). The archive carries a
# hand-written ./configure (autotools-free), so no autoconf is needed.
version 2.3.3 sha256=f9c65aa9c852eb8255b636fd9f07ce1c406f061ec19a2e7d508b318ca0c907d1 \
    url=https://github.com/zlib-ng/zlib-ng/archive/2.3.3.tar.gz \
    fname=zlib-ng-2.3.3.tar.gz

# 2.3.3-boot: same source, but a static-only libz.a built in the toolchain
# layer (by gcc-boot-wrapper, against glibc) so gcc/binutils can link zlib
# statically -- no shared-lib resolution in the hot compiler path.
version 2.3.3-boot sha256=f9c65aa9c852eb8255b636fd9f07ce1c406f061ec19a2e7d508b318ca0c907d1 \
    url=https://github.com/zlib-ng/zlib-ng/archive/2.3.3.tar.gz \
    fname=zlib-ng-2.3.3.tar.gz

build_system generic

# 2.3.3: app-layer shared build via compiler-wrapper (final gcc 16).
# 2.3.3-boot: toolchain-layer static build by gcc-boot-wrapper.
depends_on compiler-wrapper gmake when=2.3.3
depends_on gcc-boot-wrapper glibc gmake when=2.3.3-boot

install() {
    # zlib-ng ships its own configure (not autotools); it honours $CC.
    # --zlib-compat builds the classic-ABI libz (zlib.h + the zlib ABI).
    case "$version" in
        2.3.3)
            export CC=$(prefix_of compiler-wrapper)/bin/gcc
            "$sh" ./configure --prefix="$PREFIX" --zlib-compat
            make $makejobs
            make install
            ;;
        2.3.3-boot)
            # Wrapper supplies glibc loader/libs but not headers; add them.
            # --static builds libz.a only (no .so), forcing static linking.
            local glibc
            glibc=$(prefix_of glibc)
            export CC=$(prefix_of gcc-boot-wrapper)/bin/gcc
            export C_INCLUDE_PATH="$glibc/include"
            export LIBRARY_PATH="$glibc/lib"
            "$sh" ./configure --prefix="$PREFIX" --zlib-compat --static
            make $makejobs
            make install
            ;;
    esac
}
