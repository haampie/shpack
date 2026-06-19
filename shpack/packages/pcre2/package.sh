# SPDX-License-Identifier: MIT

description "PCRE2 10.44 -- a Perl-compatible regular expression library." \
            "Default 8-bit libpcre2-8 build."
homepage "https://www.pcre.org"
license "BSD-3-Clause"

# GitHub release tarball (pcre2-10.44/pcre2-10.44.tar.bz2).
version 10.44 sha256=d34f02e113cf7193a1ebf2770d3ac527088d485d4e047ed10e5d217c6ef5de96 \
    url=https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.bz2

build_system autotools

depends_on compiler-wrapper gmake

configure_args() {
    # Default 8-bit build (libpcre2-8). Explicit glibc triple (no
    # uname/config.guess in the sandbox).
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        --build="$t" \
        --host="$t"
}
