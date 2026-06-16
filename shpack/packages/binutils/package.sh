# SPDX-License-Identifier: MIT

description "GNU binutils. 2.46.0 is the glibc-linked as/ld baked into the final" \
            "GCC; the -musl versions are the bootstrap as/ld used to build the" \
            "musl-world chain (2.30 for gcc 4.7/9.5, 2.46.0-musl for the cap)."
homepage "https://www.gnu.org/software/binutils/"
license "GPL-3.0-or-later"

# The same 2.46.0 source is built three ways, distinguished by version string
# because a node id is name-version (so they cannot share one). 2.46.0 (no
# suffix) is the glibc-linked one baked into the shipped GCC; the -musl ones are
# bootstrap-only as/ld in the musl world. They are separate DAG nodes anyway --
# the glibc 2.46.0 depends (via glibc) on 2.46.0-musl, so they could never be a
# single node. Nothing depends on a bare `binutils` (every consumer pins a
# version), so the fact that vercmp ranks 2.46.0-musl as "newest" is moot.

# 2.46.0: glibc-linked, built by gcc-boot-wrapper against glibc 2.43; gprofng
# links the static libstdcxx-boot1. The as/ld baked into the final GCC.
version 2.46.0 sha256=0f3152632a2a9ce066f20963e9bb40af7cf85b9b6c409ed892fd0676e84ecd12 \
    url=https://ftp.gnu.org/gnu/binutils/binutils-2.46.0.tar.bz2

# 2.46.0-musl: glibc-cap as/ld/ar built by the gcc-9.5 bridge in the musl world
# (first node of the musl->glibc transition toward GCC 16).
version 2.46.0-musl sha256=0f3152632a2a9ce066f20963e9bb40af7cf85b9b6c409ed892fd0676e84ecd12 \
    url=https://ftp.gnu.org/gnu/binutils/binutils-2.46.0.tar.bz2

# 2.30-musl: the tcc-built early as/ld gcc 4.7/9.5 use.
version 2.30-musl sha256=8c3850195d1c093d290a716e20ebcaa72eda32abf5e3d8611154b39cff79e9ea \
    url=https://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.gz

build_system autotools

# 2.30-musl: tcc + kaem-external musl 1.1.24 + m4; seed make/sed/tar suffice.
depends_on tcc musl@1.1.24 gmake grep gawk@3.0.4 diffutils m4 when=2.30-musl
# 2.46.0-musl: gcc 9.5, with 2.30-musl supplying the plain as/ld/ar it
# assembles/links with (on PATH via topo order). Modern sed/tar: 2.46's
# configure needs sed -E and its tarball is pax (seed sed/tar are too old).
depends_on gcc-boot@9.5.0 binutils@2.30-musl gmake grep gawk@3.0.4 diffutils sed tar \
    when=2.46.0-musl
# 2.46.0 (glibc): built by gcc-boot-wrapper against glibc 2.43. linux-headers:
# autoconf CPP sanity check. libstdcxx-boot1: gprofng is C++ and links the
# static libstdc++.a. binutils@2.46.0-musl supplies plain as/ld/ar on PATH.
depends_on gcc-boot-wrapper glibc linux-headers libstdcxx-boot1 binutils@2.46.0-musl \
    bison gmake sed grep gawk@3.0.4 diffutils tar when=2.46.0

# 2.30 only: the HOWTO table in bfd/elfnn-aarch64.c has #if/#else inside macro
# arguments, which tcc 0.9.26's preprocessor lineage cannot handle.
patch arm64-elfnn-howto.patch arch=aarch64 when=2.30-musl

setup_build_environment() {
    local glibc triple libstdcxx
    # All: binutils ships generated parsers and no flex exists, so the only
    # obstacle is AC_PROG_LEX fatally running $LEX -- preseed to short-circuit.
    export ac_cv_prog_lex_root=lex.yy
    case "$version" in
        2.30-musl)
            # Cap libtool's command length so it never falls back to piecewise
            # archive linking (tcc -ar recreates the archive on each call, so
            # only the last batch would survive).
            export lt_cv_sys_max_cmd_len=131072
            ;;
        2.46.0)
            # glibc headers/libs + libgcc for the wrapped boot0 compiler. gprofng
            # is C++ (#include <new>, <string>, ...); gcc-boot@16.1.0 was built
            # --disable-libstdc++-v3, so supply libstdcxx-boot1's C++ headers (the
            # triple subdir carries bits/c++config.h).
            glibc=$(prefix_of glibc)
            triple=$(triple gnu)
            libstdcxx=$(prefix_of libstdcxx-boot1)
            export C_INCLUDE_PATH="$glibc/include"
            export CPLUS_INCLUDE_PATH="$libstdcxx/include:$libstdcxx/include/$triple:$glibc/include"
            export LIBRARY_PATH="$glibc/lib"
            ;;
    esac
}

# Shared base + per-version deltas (the configure_args hook concatenates every
# emitted line). --prefix and --disable-dependency-tracking come from
# default_configure.
configure_args() {
    local triple gcc libstdcxx
    case "$version" in
        2.30-musl)         triple=$(triple musl unknown) ;;
        2.46.0-musl|2.46.0) triple=$(triple gnu) ;;
    esac
    # Common to all three: native build, 64-bit BFD, reproducible archives, no
    # NLS/werror. (static/shared and multilib differ per build, below.)
    printf '%s\n' \
        MAKEINFO=true \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --enable-64-bit-bfd \
        --enable-deterministic-archives \
        --disable-nls \
        --disable-werror
    case "$version" in
        2.30-musl)
            # tcc as compiler/linker/archiver against the kaem-external musl
            # sysroot; no real ld plugins.
            printf '%s\n' \
                CC=tcc \
                LD=tcc \
                'AR=tcc -ar' \
                RANLIB=true \
                CFLAGS=-g \
                --with-sysroot="$(prefix_of musl)" \
                --disable-dependency-tracking \
                --disable-plugins \
                --enable-static \
                --disable-shared
            ;;
        2.46.0-musl)
            # gcc 9.5 + the plain binutils 2.30-musl tools on PATH; install
            # libbfd, skip gprofng (no C++/libstdc++ in the musl world yet).
            printf '%s\n' \
                CONFIG_SHELL=/bin/sh \
                "CC=$(prefix_of gcc-boot)/bin/gcc" \
                "CXX=$(prefix_of gcc-boot)/bin/g++" \
                AR=ar AS=as NM=nm RANLIB=ranlib \
                OBJCOPY=objcopy OBJDUMP=objdump READELF=readelf STRIP=strip \
                --with-sysroot=/ \
                --enable-install-libbfd \
                --disable-gprofng \
                --enable-static \
                --disable-shared
            ;;
        2.46.0)
            # gcc-boot-wrapper against glibc; gprofng links static libstdcxx-boot1.
            gcc=$(prefix_of gcc-boot-wrapper)
            libstdcxx=$(prefix_of libstdcxx-boot1)
            printf '%s\n' \
                CONFIG_SHELL=/bin/sh \
                "CC=$gcc/bin/gcc" \
                "CXX=$gcc/bin/g++" \
                "LDFLAGS=-L$libstdcxx/lib64 -L$libstdcxx/lib" \
                AR=ar AS=as NM=nm RANLIB=ranlib \
                OBJCOPY=objcopy OBJDUMP=objdump READELF=readelf STRIP=strip \
                --disable-multilib
            ;;
    esac
}

build_args() {
    printf '%s\n' MAKEINFO=true
    case "$version" in
        2.30-musl) printf '%s\n' "M4=$(prefix_of m4)/bin/m4" ;;
    esac
}

install() {
    local triple f b
    case "$version" in
        2.30-musl)
            make install MAKEINFO=true "M4=$(prefix_of m4)/bin/m4"
            ;;
        2.46.0-musl)
            triple=$(triple gnu)
            make install MAKEINFO=true
            # Add <triple>-<tool> symlinks beside the plain names a native build
            # installs. Downstream configures pass --host=<triple>, so
            # AC_CHECK_TOOL looks for <triple>-ar etc. first; the symlinks make
            # those resolve to our tools (and shadow any host binutils on PATH).
            for f in "$PREFIX"/bin/*; do
                b=${f##*/}
                case "$b" in "$triple"-*) continue ;; esac
                [ -e "$PREFIX/bin/$triple-$b" ] || ln -s "$b" "$PREFIX/bin/$triple-$b"
            done
            ;;
        2.46.0)
            make install MAKEINFO=true
            ;;
    esac
}
