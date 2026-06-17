# SPDX-License-Identifier: MIT

description "re2c 3.0 -- lexer generator. Build dependency of clingo (turns" \
            "*.re into C++). 3.0 (not 3.1+) because 3.1's configure hard-requires" \
            "a Python >=3.7 interpreter we don't have yet; 3.0 only probes for it."
homepage "https://re2c.org/"
license "Public-Domain"

# 3.0 self-bootstraps its own lexer/parser from the shipped generated sources, so
# it needs no host re2c/bison/python -- a plain C++ compiler suffices.
version 3.0 sha256=b3babbbb1461e13fe22c630a40c43885efcfbbbb585830c6f4c0d791cf82ba0b \
    url=https://github.com/skvadrik/re2c/releases/download/3.0/re2c-3.0.tar.xz

build_system autotools

depends_on compiler-wrapper gmake

configure_args() {
    # gcc/g++ resolve to the wrapper via the composed PATH. Explicit triple:
    # config.guess can't probe this environment (no date/uname).
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        CXX=g++ \
        --build="$t" \
        --host="$t"
}
