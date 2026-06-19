# SPDX-License-Identifier: MIT

description "GNU tar 1.35 -- a modern archiver. The stage0 seed tar is 1.12" \
           "(1999), which cannot extract POSIX pax-format tarballs (gcc 9.5+," \
           "glibc, binutils 2.46, python all ship pax). Consumers depend on it" \
           "so shpack's unpack() pipes through it instead of the seed tar."
homepage "https://www.gnu.org/software/tar/"
license "GPL-3.0-or-later"

# GNU tar's own release tarball is plain ustar/gnu (not pax), so the seed
# tar-1.12 can unpack THIS source -- no repack needed to bootstrap it.
version 1.35 sha256=14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e \
    url=https://ftpmirror.gnu.org/tar/tar-1.35.tar.gz

build_system autotools

# Built by the chain's real GCC 4.7 against musl 1.1.24 (static), like sed.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake

setup_build_environment() {
    # tar's configure refuses to run as (real or fake) root unless told the
    # rmt setup is intentional; the chroot drops to the real uid so this is a
    # belt-and-suspenders guard.
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
    # config.guess cannot probe this environment, so pass an explicit triple.
    triple=$(triple musl unknown)
    # CFLAGS=-O2 drops the autotools default -g: gcc-4.7 builds this and has no
    # -ffile-prefix-map, so -g would leak the build cwd as comp_dir (see builder.sh).
    printf '%s\n' \
        CC=gcc \
        CFLAGS=-O2 \
        --build="$triple" \
        --host="$triple" \
        --disable-nls
}
