# SPDX-License-Identifier: GPL-3.0-or-later

src_configure() {
    # --build=none-unknown-linux-gnu forces GMP into generic-C mode: no
    # hand-written x86_64/aarch64 assembly, which TCC cannot assemble.
    # Without this GMP's configure detects the host CPU and selects ASM paths
    # that fail to compile under TCC.
    ./configure \
        CC=tcc \
        CFLAGS=-DHAVE_ALLOCA_H \
        --prefix="${PREFIX}" \
        --build=none-unknown-linux-gnu \
        --host=none-unknown-linux-gnu \
        --enable-static \
        --disable-shared
}

src_compile() {
    make "${MAKEJOBS}"
}

src_install() {
    make install DESTDIR="${DESTDIR}"
}
