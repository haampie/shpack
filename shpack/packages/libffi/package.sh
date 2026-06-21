# SPDX-License-Identifier: MIT

description "libffi 3.4.6 -- foreign function interface. Provides CPython's" \
            "_ctypes, which Spack imports at startup (archspec CPU detection" \
            "via ctypes), so it's required even though clingo uses the C-API."
homepage "https://sourceware.org/libffi/"
license "MIT"

version 3.4.6 sha256=b0dea9df23c863a7a50e825440f3ebffabd65df1497108e5d437747843895a4e \
    url=https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz

build_system autotools

depends_on compiler-wrapper gmake
depends_on dash

configure_args() {
    # Explicit triple (no date/uname for config.guess). --disable-multi-os-directory
    # keeps the lib in lib/ (not a multiarch subdir) so the wrapper's -L finds it.
    # --disable-docs drops the doc/ subdir (no makeinfo in the store).
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        CXX=g++ \
        --build="$t" \
        --host="$t" \
        --with-pic \
        --disable-multi-os-directory \
        --disable-docs
}
