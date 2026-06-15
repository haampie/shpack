# SPDX-License-Identifier: MIT

description "GNU Bison 3.8.2, built by the gcc-9.5 bridge. glibc 2.43 invokes" \
            "it at build time to generate intl/plural.c."
homepage "https://www.gnu.org/software/bison/"
license "GPL-3.0-or-later"

version 3.8.2 sha256=9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2 \
    url=https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz

build_system autotools

# Built by gcc 9.5 in the musl world (binutils@2.30 as/ld). m4 is a RUN dep:
# bison shells out to m4 to expand its skeletons. Seed m4@1.4.7 satisfies
# bison's `m4 >= 1.4.6` requirement, so no separate modern m4 is built.
depends_on gcc-boot@9.5.0 binutils@2.30 gmake sed tar m4

setup_build_environment() {
    # No host flex; bison ships its generated scanners, so the only obstacle is
    # AC_PROG_LEX fatally running $LEX. Preseed to short-circuit it.
    export ac_cv_prog_lex_root=lex.yy
}

configure_args() {
    case "$ARCH" in
        amd64)   triple=x86_64-linux-musl ;;
        aarch64) triple=aarch64-linux-musl ;;
    esac
    printf '%s\n' \
        CONFIG_SHELL=/bin/sh \
        SHELL=/bin/sh \
        "CC=$(prefix_of gcc-boot)/bin/gcc" \
        --build="$triple" \
        --host="$triple" \
        --disable-nls \
        ARFLAGS=crD
}
