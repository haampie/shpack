# SPDX-License-Identifier: MIT

description "GNU grep -- pattern matching. 2.4-musl is the tiny tcc-built grep" \
            "that scripts the early chain's configure/Makefiles (every GNU" \
            "configure needs grep); 3.11 is the modern glibc grep built with the" \
            "final gcc 16, the user-facing one."
homepage "https://www.gnu.org/software/grep/"
license "GPL-2.0-or-later"

# 3.11: autotools, built with gcc 16 against glibc -- the user-facing grep.
version 3.11 sha256=1f31014953e71c3cddcedb97692ad7620cb9d6d04fbdc19e0d8dd836f87622bb \
    url=https://ftpmirror.gnu.org/grep/grep-3.11.tar.gz
# 2.4-musl: grown by tcc against the kaem-external musl 1.1.24, driven by a
# replacement files/Makefile (grep 2.4's own configure needs tools we lack here).
version 2.4-musl sha256=a32032bab36208509466654df12f507600dfe0313feebbcd218c32a70bf72a16 \
    url=https://mirrors.kernel.org/gnu/grep/grep-2.4.tar.gz

# 2.4-musl builds from a shipped Makefile (no configure); 3.11 is autotools. The
# two build systems diverge and build_system cannot vary per version, so use
# generic and branch install() on $version (the gawk pattern).
build_system generic

depends_on tcc musl@1.1.24 when=2.4-musl
depends_on compiler-wrapper gmake when=3.11

install() {
    local t
    case "$version" in
        2.4-musl)
            # Replicate the old makefile build system: the replacement Makefile
            # (files/Makefile) drives the tcc build (PREFIX-parameterized).
            cp "$package_dir/files/Makefile" ./Makefile
            make -f Makefile "SHELL=$sh" $makejobs PREFIX="$PREFIX"
            make -f Makefile "SHELL=$sh" PREFIX="$PREFIX" install
            ;;
        3.11)
            # gcc 16 via the wrapper. Explicit glibc triple (no uname). Drop NLS
            # and the optional PCRE backend (grep -P) so it stays self-contained.
            t=$(triple gnu)
            "$sh" ./configure \
                "CONFIG_SHELL=$sh" "SHELL=$sh" \
                CC=gcc \
                --build="$t" \
                --host="$t" \
                --prefix="$PREFIX" \
                --disable-dependency-tracking \
                --disable-nls \
                --disable-perl-regexp
            make $makejobs
            make install
            ;;
    esac
}
