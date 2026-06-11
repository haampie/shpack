# SPDX-License-Identifier: GPL-3.0-or-later

src_prepare() {
    # libiberty's C_alloca conflicts with musl's alloca/__builtin_alloca.
    # Rename C_alloca -> alloca throughout libiberty (same fix as Guix).
    patch -Np1 < "${patch_dir}/0001-alloca.patch"
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
        --with-sysroot=/ \
        --with-native-system-header-dir=/usr/include \
        --with-gmp="${PREFIX}" \
        --with-mpfr="${PREFIX}" \
        --with-mpc="${PREFIX}" \
        --enable-languages=c \
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
    # CFLAGS_FOR_TARGET: tcc-compiled GCC miscompiles the tree-ccp pass,
    # causing ICEs on TImode and silent miscompilation of target code.
    make "${MAKEJOBS}" MAKEINFO=true "CFLAGS_FOR_TARGET=-O2 -fno-tree-ccp"
}

src_install() {
    # CWD is _build/ (set by src_configure above)
    make install MAKEINFO=true DESTDIR="${DESTDIR}"

    # Write a specs file so every cc1/cc1plus invocation gets -fno-tree-ccp,
    # protecting all consumers built by this GCC from the tcc codegen bug.
    # GCC reads `specs` from its libgcc directory automatically.
    libgcc=$(find "${DESTDIR}${PREFIX}/lib/gcc" -name 'libgcc.a' | head -1)
    libgcc_dir=$(dirname "${libgcc}")
    printf '*cc1_options:\n+ -fno-tree-ccp\n\n' > "${libgcc_dir}/specs"
}
