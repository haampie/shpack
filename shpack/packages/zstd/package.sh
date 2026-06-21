# SPDX-License-Identifier: MIT

description "Zstandard 1.5.7 -- a fast lossless compressor: the zstd CLI plus" \
            "libzstd. Built at the gcc-16 layer via the upstream Makefile."
homepage "https://facebook.github.io/zstd/"
license "BSD-3-Clause OR GPL-2.0-or-later"

# GitHub source archive (extracts zstd-1.5.7/).
version 1.5.7 sha256=37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3 \
    url=https://github.com/facebook/zstd/archive/v1.5.7.tar.gz \
    fname=zstd-1.5.7.tar.gz

# 1.5.7-boot: same source, but a static-only libzstd.a built in the toolchain
# layer (by gcc-boot-wrapper, against glibc) so gcc/binutils can link zstd
# statically -- no shared-lib resolution in the hot compiler path.
version 1.5.7-boot sha256=37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3 \
    url=https://github.com/facebook/zstd/archive/v1.5.7.tar.gz \
    fname=zstd-1.5.7.tar.gz

build_system generic

# 1.5.7: app-layer shared build via compiler-wrapper (final gcc 16).
# 1.5.7-boot: toolchain-layer static build by gcc-boot-wrapper.
depends_on compiler-wrapper gmake when=1.5.7
depends_on gcc-boot-wrapper glibc gmake when=1.5.7-boot
depends_on dash

setup_build_environment() {
    # zstd's Makefiles do `$(shell uname)` to pick the shared-lib soname/flags;
    # uname is absent in the sandbox (see perl), so shim a minimal one to keep
    # libzstd.so's Linux soname.
    local m
    case "$ARCH" in amd64) m=x86_64 ;; aarch64) m=aarch64 ;; esac
    mkdir -p "$stage_dir/shimbin"
    cat > "$stage_dir/shimbin/uname" <<EOF
#!$sh
case "\$1" in -m|-p|-i) echo $m ;; *) echo Linux ;; esac
EOF
    chmod 755 "$stage_dir/shimbin/uname"
    export PATH="$stage_dir/shimbin:$PATH"
}

install() {
    local cc glibc
    case "$version" in
        1.5.7)
            cc=$(prefix_of compiler-wrapper)/bin/gcc
            # Install the library (pkg-config, headers, static + shared) then the
            # zstd CLI. The optional zlib/lzma/lz4 backends are turned off
            # explicitly so the Makefile does not auto-detect and link them.
            make -C lib "SHELL=$sh" "CC=$cc" $makejobs PREFIX="$PREFIX" \
                install-pc install-includes install-static install-shared
            make -C programs "SHELL=$sh" "CC=$cc" $makejobs PREFIX="$PREFIX" \
                HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 install
            ;;
        1.5.7-boot)
            # Library only, static only: no install-shared (no .so forces
            # static linking) and no CLI. Wrapper supplies glibc loader/libs
            # but not headers; add them.
            glibc=$(prefix_of glibc)
            cc=$(prefix_of gcc-boot-wrapper)/bin/gcc
            export C_INCLUDE_PATH="$glibc/include"
            export LIBRARY_PATH="$glibc/lib"
            make -C lib "SHELL=$sh" "CC=$cc" $makejobs PREFIX="$PREFIX" \
                install-pc install-includes install-static
            ;;
    esac
}
