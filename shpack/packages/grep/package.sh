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

# 2.4-musl builds from a shipped Makefile (no configure); 3.11 is autotools.
# 2.4-musl needs no hook: the makefile default edit copies files/Makefile and the
# default build/install run the same `make -f Makefile SHELL= PREFIX= [install]`.
build_system makefile  when=2.4-musl
build_system autotools when=3.11

depends_on tcc musl@1.1.24 when=2.4-musl
depends_on compiler-wrapper gmake when=3.11

configure_args() {
    # 3.11 only (the makefile build never calls this). gcc 16 via the wrapper,
    # explicit glibc triple (no uname). The default configure already supplies
    # --prefix, --disable-dependency-tracking, CONFIG_SHELL, SHELL. Drop NLS and
    # the optional PCRE backend (grep -P) so it stays self-contained.
    local t
    t=$(triple gnu)
    printf '%s\n' CC=gcc "--build=$t" "--host=$t" \
        --disable-nls --disable-perl-regexp
}
