# SPDX-License-Identifier: GPL-3.0-or-later

src_prepare() {
    # The HOWTO table in bfd/elfnn-aarch64.c has #if/#else inside macro args,
    # which tcc 0.9.26 (the compiler we built with) cannot handle.
    if [ "${ARCH}" = aarch64 ]; then
        patch -Np1 < "${patch_dir}/binutils-arm64-elfnn-howto.patch"
    fi
}

src_configure() {
    case "${ARCH}" in
        amd64)   TRIPLE=x86_64-unknown-linux-musl ;;
        aarch64) TRIPLE=aarch64-unknown-linux-musl ;;
    esac

    # ac_cv_prog_lex_root: skip the lex probe (binutils 2.30 ships generated
    # parsers; no flex needed).  lt_cv_sys_max_cmd_len: prevent libtool from
    # using piecewise archive linking — tcc -ar recreates archives on each call
    # so only the last batch would survive.
    export ac_cv_prog_lex_root=lex.yy
    export lt_cv_sys_max_cmd_len=131072

    ./configure \
        CC=tcc \
        LD=tcc \
        "AR=tcc -ar" \
        RANLIB=true \
        MAKEINFO=true \
        CFLAGS=-g \
        --prefix="${PREFIX}" \
        --build="${TRIPLE}" \
        --host="${TRIPLE}" \
        --target="${TRIPLE}" \
        --with-sysroot="${LIBC_PREFIX}" \
        --disable-dependency-tracking \
        --enable-64-bit-bfd \
        --disable-nls \
        --enable-static \
        --disable-shared \
        --disable-werror \
        --disable-plugins \
        --enable-deterministic-archives
}

src_compile() {
    make "${MAKEJOBS}" MAKEINFO=true "M4=${PKGDIR}/m4-1.4.7/bin/m4"
}

src_install() {
    make install MAKEINFO=true "M4=${PKGDIR}/m4-1.4.7/bin/m4"
}
