# SPDX-License-Identifier: MIT

description "GNU gzip 1.14 -- the gzip/gunzip/zcat CLI (DEFLATE .gz codec)." \
            "Built at the gcc-16 layer; the bootstrap seed gzip is the 1.2.4" \
            "(1993) one, this is the modern replacement."
homepage "https://www.gnu.org/software/gzip/"
license "GPL-3.0-or-later"

version 1.14 sha256=613d6ea44f1248d7370c7ccdeee0dd0017a09e6c39de894b3c6f03f981191c6b \
    url=https://ftpmirror.gnu.org/gzip/gzip-1.14.tar.gz

build_system autotools

# compiler-wrapper supplies gcc 16 + glibc; grep comes in transitively through
# its closure (configure needs it).
depends_on compiler-wrapper gmake

# gzip makes a recursive symlink if built in-source, so configure out-of-tree.
build_directory spack-build

configure_args() {
    # No uname/config.guess in the sandbox, so give an explicit glibc triple.
    # CC=gcc resolves to the wrapper on PATH.
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        --build="$t" \
        --host="$t" \
        --disable-nls
}
