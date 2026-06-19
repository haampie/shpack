# SPDX-License-Identifier: MIT

description "GNU Bison 3.8.2, built by the gcc-9.5 bridge. glibc 2.43 invokes" \
            "it at build time to generate intl/plural.c."
homepage "https://www.gnu.org/software/bison/"
license "GPL-3.0-or-later"

version 3.8.2 sha256=9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2 \
    url=https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz

build_system autotools

# Built by gcc 9.5 in the musl world (binutils@2.30-musl as/ld). m4 is a RUN dep:
# bison shells out to it to expand skeletons; seed m4@1.4.7 meets `m4 >= 1.4.6`.
depends_on gcc-boot@9.5.0 binutils@2.30-musl gmake sed@4.9-musl tar@1.35-musl m4 xz@5.2.5-musl

setup_build_environment() {
    # No host flex; bison ships its generated scanners, so the only obstacle is
    # AC_PROG_LEX fatally running $LEX. Preseed to short-circuit it.
    export ac_cv_prog_lex_root=lex.yy
}

configure_args() {
    local triple
    triple=$(triple musl)
    # CFLAGS=-O2 drops autotools' default -g: -g would leak the build cwd as the
    # DWARF comp_dir (see builder.sh).
    printf '%s\n' \
        "CC=$(prefix_of gcc-boot)/bin/gcc" \
        CFLAGS=-O2 \
        --build="$triple" \
        --host="$triple" \
        --disable-nls \
        ARFLAGS=crD
}
