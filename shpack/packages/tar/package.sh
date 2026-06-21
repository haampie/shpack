# SPDX-License-Identifier: MIT

description "GNU tar 1.35 -- a modern archiver. The stage0 seed tar is 1.12" \
           "(1999), which cannot extract POSIX pax-format tarballs (gcc 9.5+," \
           "glibc, binutils 2.46, python all ship pax). The same source builds" \
           "two ways: 1.35-musl is the static musl tar the bootstrap chain uses" \
           "to unpack pax sources before the final toolchain exists; 1.35 is the" \
           "glibc tar built with the final gcc 16, the user-facing archiver."
homepage "https://www.gnu.org/software/tar/"
license "GPL-3.0-or-later"

# tar's own release tarball is plain ustar/gnu, so the seed tar-1.12 can unpack
# this source. The same source builds two ways under separate version strings.
version 1.35 sha256=14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e \
    url=https://ftpmirror.gnu.org/tar/tar-1.35.tar.gz
version 1.35-musl sha256=14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e \
    url=https://ftpmirror.gnu.org/tar/tar-1.35.tar.gz

build_system autotools

# 1.35-musl: built by GCC 4.7 against musl 1.1.24 (static). 1.35: the glibc tar,
# built with the final gcc 16 via compiler-wrapper.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake when=1.35-musl
depends_on compiler-wrapper gmake when=1.35
# replace_bin_sh (below) compiles the shell path into the tar binary, a runtime
# dep: 1.35 (glibc) ships the clean dash, 1.35-musl the tcc-built bootstrap one.
depends_on dash        when=1.35
depends_on dash@0.5.12 when=1.35-musl

setup_build_environment() {
    # tar's configure refuses to run as root unless told the rmt setup is
    # intentional; belt-and-suspenders since the chroot drops to the real uid.
    export FORCE_UNSAFE_CONFIGURE=1
}

edit() {
    # tar runs compressors via a hardcoded execv("/bin/sh", -c) in src/system.c;
    # the sandbox denies host /bin/sh, so `tar czf` would fail.
    replace_bin_sh src/system.c
}

configure_args() {
    local triple
    # Explicit triple (no config.guess); musl vs glibc differ only here.
    case "$version" in
        1.35-musl) triple=$(triple musl unknown) ;;
        1.35)      triple=$(triple gnu) ;;
    esac
    printf '%s\n' \
        CC=gcc \
        --build="$triple" \
        --host="$triple" \
        --disable-nls
    # gcc 4.7 has no -ffile-prefix-map, so CFLAGS=-O2 drops the default -g (would
    # leak the build cwd as comp_dir). gcc 16's -g is reproducible.
    case "$version" in 1.35-musl) printf '%s\n' CFLAGS=-O2 ;; esac
}
