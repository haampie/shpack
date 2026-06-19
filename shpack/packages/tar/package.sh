# SPDX-License-Identifier: MIT

description "GNU tar 1.35 -- a modern archiver. The stage0 seed tar is 1.12" \
           "(1999), which cannot extract POSIX pax-format tarballs (gcc 9.5+," \
           "glibc, binutils 2.46, python all ship pax). The same source builds" \
           "two ways: 1.35-musl is the static musl tar the bootstrap chain uses" \
           "to unpack pax sources before the final toolchain exists; 1.35 is the" \
           "glibc tar built with the final gcc 16, the user-facing archiver."
homepage "https://www.gnu.org/software/tar/"
license "GPL-3.0-or-later"

# GNU tar's own release tarball is plain ustar/gnu (not pax), so the seed
# tar-1.12 can unpack THIS source -- no repack needed to bootstrap it. The two
# versions are separate DAG nodes: 1.35 (glibc) depends, via compiler-wrapper ->
# gcc -> binutils, on nodes that themselves use 1.35-musl, so they could never
# be one node. Nothing depends on a bare `tar` (every consumer pins a version),
# so vercmp ranking of the two 1.35s is moot.
version 1.35 sha256=14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e \
    url=https://ftpmirror.gnu.org/tar/tar-1.35.tar.gz
version 1.35-musl sha256=14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e \
    url=https://ftpmirror.gnu.org/tar/tar-1.35.tar.gz

build_system autotools

# 1.35-musl: built by the chain's real GCC 4.7 against musl 1.1.24 (static), like
# sed. 1.35: the glibc tar, built with the final gcc 16 via compiler-wrapper.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake when=1.35-musl
depends_on compiler-wrapper gmake when=1.35

setup_build_environment() {
    # tar's configure refuses to run as (real or fake) root unless told the
    # rmt setup is intentional; the chroot drops to the real uid so this is a
    # belt-and-suspenders guard. Applies to both builds.
    export FORCE_UNSAFE_CONFIGURE=1
}

edit() {
    # tar runs compressors (`tar czf`) via execv("/bin/sh", -c) hardcoded in
    # src/system.c, bypassing libc. The sandbox denies host /bin/sh, so `tar czf`
    # would fail ("gzip: Cannot exec"; binutils' gprofng docs hit this).
    replace_bin_sh src/system.c
}

configure_args() {
    local triple
    # config.guess cannot probe this environment, so pass an explicit triple
    # (musl-world vs glibc differ only here for the common flags).
    case "$version" in
        1.35-musl) triple=$(triple musl unknown) ;;
        1.35)      triple=$(triple gnu) ;;
    esac
    printf '%s\n' \
        CC=gcc \
        --build="$triple" \
        --host="$triple" \
        --disable-nls
    # Delta: gcc 4.7 (musl) has no -ffile-prefix-map, so CFLAGS=-O2 drops the
    # autotools default -g (which would leak the build cwd as the stabs comp_dir;
    # see builder.sh). gcc 16's -g is reproducible, so leave CFLAGS at default.
    case "$version" in 1.35-musl) printf '%s\n' CFLAGS=-O2 ;; esac
}
