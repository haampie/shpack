# SPDX-License-Identifier: GPL-3.0-or-later

src_prepare() {
    # libiberty's C_alloca conflicts with musl's alloca/__builtin_alloca.
    # Rename C_alloca -> alloca throughout libiberty (same fix as Guix).
    patch -Np1 < "${patch_dir}/0001-alloca.patch"

    # Work around a tcc 0.9.27 AArch64 spill-slot collision that miscompiles a
    # nested 16-byte-struct-return call in set_lattice_value, crashing the
    # tcc-built cc1 inside the tree-ccp pass (libgcc2.c __cmpti2). Splitting the
    # call into a temporary avoids it; lets us build libgcc with -O2 tree-ccp on.
    # See bugs/tcc-aarch64-nested-struct-return-spill.md.
    patch -Np1 < "${patch_dir}/0002-tree-ssa-ccp-spill.patch"

    # libstdc++'s gnu-linux os_defines.h uses __GLIBC_PREREQ(2,15), which musl
    # does not define; the bare macro name breaks the preprocessor on every
    # libsupc++/EH object. Guard it so the gets() check evaluates false on musl.
    patch -Np1 < "${patch_dir}/0003-libstdcxx-musl-glibc-prereq.patch"

    # gnu-linux ctype uses glibc-internal mask names (_ISupper, ...) and
    # __ctype_b_loc(), absent on musl -> every libstdc++ TU fails. Swap in the
    # portable config/os/generic ctype (own mask bits, classify via isXXX()).
    # Same approach as Alpine / musl-cross-make. Proven on amd64 + aarch64.
    patch -Np1 < "${patch_dir}/0004-libstdcxx-generic-ctype.patch"
}

src_configure() {
    case "${ARCH}" in
        amd64)   TRIPLE=x86_64-unknown-linux-musl ;;
        aarch64) TRIPLE=aarch64-unknown-linux-musl ;;
    esac

    # GCC requires an out-of-tree build directory.  CWD becomes _build/ and
    # stays there for src_compile/src_install (the src_* functions share CWD).
    mkdir -p _build
    cd _build

    # We build C only (--disable-build-with-cxx), but gcc/configure still runs a
    # fatal AC_PROG_CXXCPP probe. With no C++ compiler it falls back to /lib/cpp,
    # which is absent here, and aborts. tcc can't *compile* .cpp ("unrecognized
    # file type"), but `tcc -E` happily *preprocesses* it, which is all the probe
    # needs, so point CXX/CXXCPP at tcc. No C++ is actually compiled.
    ../configure \
        CC=tcc \
        CC_FOR_BUILD=tcc \
        CXX=tcc \
        "CXXCPP=tcc -E" \
        CFLAGS=-DHAVE_ALLOCA_H \
        MAKEINFO=true \
        --prefix="${PREFIX}" \
        --build="${TRIPLE}" \
        --host="${TRIPLE}" \
        --target="${TRIPLE}" \
        --with-sysroot="${LIBC_PREFIX}" \
        --with-native-system-header-dir=/include \
        --with-gmp="${PKGDIR}/gmp-4.3.2" \
        --with-mpfr="${PKGDIR}/mpfr-2.4.2" \
        --with-mpc="${PKGDIR}/mpc-1.0.3" \
        --with-as="${PKGDIR}/binutils-2.30/bin/as" \
        --with-ld="${PKGDIR}/binutils-2.30/bin/ld" \
        --enable-languages=c,c++ \
        --enable-static \
        --disable-shared \
        --enable-threads=single \
        --disable-threads \
        --disable-libstdcxx-pch \
        --disable-build-with-cxx \
        --disable-bootstrap \
        --disable-multilib \
        --disable-decimal-float \
        --disable-lto \
        --disable-lto-plugin \
        --disable-plugin \
        --disable-libatomic \
        --disable-libcilkrts \
        --disable-libgomp \
        --disable-libitm \
        --disable-libmudflap \
        --disable-libquadmath \
        --disable-libsanitizer \
        --disable-libssp \
        --disable-libvtv
}

src_compile() {
    # CWD is _build/ (set by src_configure above)
    make "${MAKEJOBS}" MAKEINFO=true
}

src_install() {
    # CWD is _build/ (set by src_configure above)
    make install MAKEINFO=true
}
