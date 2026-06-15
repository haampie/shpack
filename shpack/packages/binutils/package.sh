# SPDX-License-Identifier: MIT

description "GNU binutils. 2.30 is the tcc-built early as/ld gcc 4.7/9.5 use;" \
            "2.46 is the glibc-cap as/ld/ar/gprofng built by the gcc-9.5 bridge" \
            "(first node of the musl->glibc transition toward GCC 16)."
homepage "https://www.gnu.org/software/binutils/"
license "GPL-3.0-or-later"

# 2.30: grown by tcc against the kaem-external musl 1.1.24.
version 2.30 sha256=8c3850195d1c093d290a716e20ebcaa72eda32abf5e3d8611154b39cff79e9ea \
    url=https://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.gz

# 2.46.0: glibc-cap binutils, built by gcc 9.5. The lower chain pins
# binutils@2.30, so this newer version never hijacks bare consumers.
version 2.46.0 sha256=0f3152632a2a9ce066f20963e9bb40af7cf85b9b6c409ed892fd0676e84ecd12 \
    url=https://ftp.gnu.org/gnu/binutils/binutils-2.46.0.tar.bz2

build_system autotools

# 2.30: tcc + kaem-external musl 1.1.24 + m4; seed make/sed/tar suffice.
depends_on tcc musl@1.1.24 gmake grep gawk@3.0.4 diffutils m4 when=2.30
# 2.46.0: gcc 9.5, with 2.30 supplying the plain as/ld/ar it assembles/links
# with (on PATH via topo order). Modern sed/tar: 2.46's configure needs sed -E
# and its tarball is pax (seed sed/tar are too old).
depends_on gcc-boot@9.5.0 binutils@2.30 gmake grep gawk@3.0.4 diffutils sed tar \
    when=2.46.0

# 2.30 only: the HOWTO table in bfd/elfnn-aarch64.c has #if/#else inside macro
# arguments, which tcc 0.9.26's preprocessor lineage cannot handle.
patch arm64-elfnn-howto.patch arch=aarch64 when=2.30

setup_build_environment() {
    # Both: binutils ships generated parsers and no flex exists, so the only
    # obstacle is AC_PROG_LEX fatally running $LEX -- preseed to short-circuit.
    export ac_cv_prog_lex_root=lex.yy
    # 2.30 only: cap libtool's command length so it never falls back to
    # piecewise archive linking (tcc -ar recreates the archive on each call, so
    # only the last batch would survive).
    case "$version" in
        2.30) export lt_cv_sys_max_cmd_len=131072 ;;
    esac
}

triple_of() {
    case "$ARCH" in
        amd64)   printf x86_64-linux-gnu ;;
        aarch64) printf aarch64-linux-gnu ;;
    esac
}

configure_args() {
    case "$version" in
        2.30)   configure_args_230 ;;
        2.46.0) configure_args_246 ;;
    esac
}

configure_args_230() {
    case "$ARCH" in
        amd64)   triple=x86_64-unknown-linux-musl ;;
        aarch64) triple=aarch64-unknown-linux-musl ;;
    esac
    printf '%s\n' \
        CC=tcc \
        LD=tcc \
        'AR=tcc -ar' \
        RANLIB=true \
        MAKEINFO=true \
        CFLAGS=-g \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --with-sysroot="$(prefix_of musl)" \
        --disable-dependency-tracking \
        --enable-64-bit-bfd \
        --disable-nls \
        --enable-static \
        --disable-shared \
        --disable-werror \
        --disable-plugins \
        --enable-deterministic-archives
}

configure_args_246() {
    local triple; triple=$(triple_of)
    printf '%s\n' \
        CONFIG_SHELL=/bin/sh \
        "CC=$(prefix_of gcc-boot)/bin/gcc" \
        "CXX=$(prefix_of gcc-boot)/bin/g++" \
        MAKEINFO=true \
        AR=ar AS=as NM=nm RANLIB=ranlib \
        OBJCOPY=objcopy OBJDUMP=objdump READELF=readelf STRIP=strip \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --with-sysroot=/ \
        --enable-install-libbfd \
        --enable-deterministic-archives \
        --enable-64-bit-bfd \
        --enable-static \
        --disable-shared \
        --disable-gprofng \
        --disable-nls \
        --disable-werror
}

build_args() {
    case "$version" in
        2.30)   printf '%s\n' MAKEINFO=true "M4=$(prefix_of m4)/bin/m4" ;;
        2.46.0) printf '%s\n' MAKEINFO=true ;;
    esac
}

install() {
    local triple f b
    case "$version" in
        2.30)
            make install MAKEINFO=true "M4=$(prefix_of m4)/bin/m4"
            ;;
        2.46.0)
            triple=$(triple_of)
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
    esac
}
