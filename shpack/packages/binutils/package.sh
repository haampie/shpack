# SPDX-License-Identifier: MIT

description "GNU binutils: the assembler/linker gcc-linaro is configured with"
homepage "https://www.gnu.org/software/binutils/"
license "GPL-3.0-or-later"

version 2.30 sha256=8c3850195d1c093d290a716e20ebcaa72eda32abf5e3d8611154b39cff79e9ea \
    url=https://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.gz

build_system autotools

depends_on tcc musl gmake grep gawk diffutils m4

# The HOWTO table in bfd/elfnn-aarch64.c has #if/#else inside macro
# arguments, which tcc 0.9.26's preprocessor lineage cannot handle.
patch arm64-elfnn-howto.patch arch=aarch64

setup_build_environment() {
    # Skip the lex probe (binutils 2.30 ships generated parsers; no flex
    # exists). Cap libtool's command length so it never falls back to
    # piecewise archive linking: tcc -ar recreates the archive on each call,
    # so only the last batch would survive.
    export ac_cv_prog_lex_root=lex.yy
    export lt_cv_sys_max_cmd_len=131072
}

configure_args() {
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

build_args() {
    printf '%s\n' MAKEINFO=true "M4=$(prefix_of m4)/bin/m4"
}

install_targets() {
    printf '%s\n' install MAKEINFO=true "M4=$(prefix_of m4)/bin/m4"
}
