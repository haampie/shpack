# SPDX-License-Identifier: MIT

description "GNU findutils: find is needed by gcc's libstdc++ libtool" \
            "to merge the convenience archives into the static libstdc++.a"
homepage "https://www.gnu.org/software/findutils/"
license "GPL-3.0-or-later"

version 4.2.33 sha256=813cd9405aceec5cfecbe96400d01e90ddad7b512d3034487176ce5258ab0f78 \
    url=https://mirrors.kernel.org/gnu/findutils/findutils-4.2.33.tar.gz

build_system autotools

depends_on tcc musl@1.1.24 grep

# The release tarball ships a working pregenerated ./configure, so unlike
# live-bootstrap no autoreconf chain is needed; we just run it.
configure_args() {
    local triple
    # musl is unknown to the 2007 config.sub, so present as -gnu; uname says
    # "unknown" in the bare chroot, so give --build/--host explicitly.
    # __UCLIBC__ tells gnulib we are uClibc-like, avoiding glibc-only paths.
    # LD=tcc skips configure's fatal AC_PROG_LD probe (no binutils ld yet);
    # tcc links internally so no real ld is ever invoked.
    triple=$(triple gnu unknown)
    # CFLAGS=-O2 drops the autotools default -g: tcc has no -f*-prefix-map, so -g
    # would leak the build cwd as the stabs comp_dir (see builder.sh). Never debugged.
    printf '%s\n' \
        CC=tcc \
        LD=tcc \
        CFLAGS=-O2 \
        CPPFLAGS=-D__UCLIBC__ \
        --build="$triple" \
        --host="$triple" \
        --disable-nls
}

# No binutils ar yet: tcc's built-in archiver, which lacks the `u` mode that
# automake's default ARFLAGS=cru would ask for.
build_args() {
    printf '%s\n' MAKEINFO=true 'AR=tcc -ar' ARFLAGS=rc
}

install_targets() {
    printf '%s\n' install MAKEINFO=true 'AR=tcc -ar' ARFLAGS=rc
}
