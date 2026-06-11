# SPDX-License-Identifier: GPL-3.0-or-later

src_configure() {
    # config.guess can't probe this environment (uname returns "unknown", no
    # /usr/bin/file), so pass an explicit triple. It's cosmetic for this native
    # pure-math-lib build; use a -gnu triple, matching gmp/mpfr.
    case "${ARCH}" in
        amd64)   TRIPLE=x86_64-unknown-linux-gnu ;;
        aarch64) TRIPLE=aarch64-unknown-linux-gnu ;;
    esac

    ./configure \
        CC=tcc \
        CFLAGS=-DHAVE_ALLOCA_H \
        --prefix="${PREFIX}" \
        --build="${TRIPLE}" \
        --host="${TRIPLE}" \
        --with-gmp="${PKGDIR}/gmp-4.3.2" \
        --with-mpfr="${PKGDIR}/mpfr-2.4.2" \
        --enable-static \
        --disable-shared
}

src_compile() {
    make "${MAKEJOBS}"
}

src_install() {
    make install
}
