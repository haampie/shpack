# SPDX-License-Identifier: GPL-3.0-or-later

src_configure() {
    # MPFR 2.4.2's config.sub predates musl; the triplet is cosmetic for this
    # native pure-math-lib build, so use a -gnu triple the old config.sub
    # recognizes (aarch64/x86_64 are both known to it).
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
        --enable-static \
        --disable-shared
}

src_compile() {
    make "${MAKEJOBS}"
}

src_install() {
    make install
}
