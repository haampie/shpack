# SPDX-License-Identifier: MIT

description "GCC bootstrap compilers (throwaway). 4.7 (Linaro, grown by tcc on" \
            "musl) bootstraps 9.5 (the bridge to modern GCC); 9.5 builds the" \
            "crippled 16.1.0 (--without-headers) that compiles glibc 2.43. The" \
            "shipped, glibc-linked GCC 16 is a separate recipe, packages/gcc."
homepage "https://gcc.gnu.org/"
license "GPL-3.0-or-later"

# 4.7-2013.11: Linaro snapshot (FSF 4.7 lacks native aarch64), grown by tcc.
version 4.7-2013.11 sha256=d0ea2c72ceb66d3851986840dd8962941824a2980a8aca2a800abb5b489acedf \
    url=https://launchpadlibrarian.net/156843777/gcc-linaro-4.7-2013.11.tar.bz2

# 9.5.0: mature C++17, old enough to build cleanly on musl. The bridge that
# builds modern GCC. Built by the chain's own 4.7 g++.
version 9.5.0 sha256=27769f64ef1d4cd5e2be8682c0c93f9887983e6cfd1a927ce5a0a2915a95cf8f \
    url=https://ftpmirror.gnu.org/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz

# 16.1.0 'crippled' (--without-headers): knows no target libc, just enough
# cc1/libgcc to compile glibc 2.43. First half of the musl->glibc transition.
version 16.1.0 sha256=50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79 \
    url=https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz

build_system autotools

# Build tools shared by all gcc versions.
depends_on gmake grep gawk@3.0.4 diffutils findutils

# 4.7-2013.11: grown by tcc against the kaem-external musl 1.1.24, with the
# external gmp/mpfr/mpc and binutils 2.30. (Pinned so newer siblings added for
# later stages -- musl 1.2.5, binutils 2.46, m4 1.4.19 -- don't perturb it.)
depends_on tcc musl@1.1.24 binutils@2.30 gmp@4.3.2 mpfr@2.4.2 mpc@1.0.3 \
    m4@1.4.7 when=4.7-2013.11

# 9.5.0: built by the chain's own 4.7 g++, modern musl 1.2.5 (the modern musl 1.2.5
# recipe -- a distinct name so it does not hijack bare `musl` for the whole
# lower chain) sysroot, kernel headers, binutils 2.30. gmp/mpfr/mpc are unpacked
# in-tree (resources below), not external deps -- 4.3.2/2.4.2 are too old.
depends_on gcc-boot@4.7-2013.11 musl@1.2.5 linux-headers binutils@2.30 m4@1.4.7 tar \
    when=9.5.0

# 16.1.0: built by the chain's own 9.5 g++, with binutils 2.46 supplying the
# as/ld it assembles/links with AND bakes into its specs. sed/tar: 16's pax
# tarball + modern configure. (gmake/grep/gawk/diffutils from the shared line.)
depends_on gcc-boot@9.5.0 binutils@2.46.0 sed tar when=16.1.0

# GCC 9.5's download_prerequisites set, unpacked in-tree as gmp/ mpfr/ mpc/ so
# configure auto-detects them (sidesteps the version/link probe). ISL omitted
# (Graphite only; --without-isl).
resource when=9.5.0 \
    url=https://ftpmirror.gnu.org/gmp/gmp-6.1.0.tar.bz2 \
    sha256=498449a994efeba527885c10405993427995d3f86b8768d8cdf8d9dd7c6b73e8
resource when=9.5.0 \
    url=https://ftpmirror.gnu.org/mpfr/mpfr-3.1.4.tar.bz2 \
    sha256=d3103a80cdad2407ed581f3618c4bed04e0c92d1cf771a65ead662cc397f7775
resource when=9.5.0 \
    url=https://ftpmirror.gnu.org/mpc/mpc-1.0.3.tar.gz \
    sha256=617decc6ea09889fb08ede330917a00b16809b8db88c29c31bfbb49cbf88ecc3

# GCC 16's download_prerequisites set (newer gmp/mpfr/mpc), in-tree.
resource when=16.1.0 \
    url=https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.bz2 \
    sha256=ac28211a7cfb609bae2e2c8d6058d66c8fe96434f740cf6fe2e47b000d1c20cb
resource when=16.1.0 \
    url=https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.bz2 \
    sha256=b9df93635b20e4089c29623b19420c4ac848a1b29df1cfd59f26cab0d2666aa0
resource when=16.1.0 \
    url=https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz \
    sha256=ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8

# --- 4.7 patches (do not apply to the 9.5 source tree) -------------------------
# libiberty's C_alloca conflicts with musl's alloca/__builtin_alloca; rename
# C_alloca -> alloca throughout (same fix as Guix).
patch 0001-alloca.patch when=4.7-2013.11
# Work around a tcc 0.9.27 AArch64 spill-slot collision that miscompiles a
# nested 16-byte-struct-return call in set_lattice_value, crashing the
# tcc-built cc1 in the tree-ccp pass (libgcc2.c __cmpti2). Splitting the call
# into a temporary avoids it. See bugs/tcc-aarch64-nested-struct-return-spill.md.
patch 0002-tree-ssa-ccp-spill.patch when=4.7-2013.11
# libstdc++'s gnu-linux os_defines.h uses __GLIBC_PREREQ(2,15), undefined on
# musl; guard it so the gets() check evaluates false.
patch 0003-libstdcxx-musl-glibc-prereq.patch when=4.7-2013.11
# gnu-linux ctype uses glibc-internal mask names and __ctype_b_loc(), absent
# on musl; swap in the portable config/os/generic ctype (same approach as
# Alpine / musl-cross-make).
patch 0004-libstdcxx-generic-ctype.patch when=4.7-2013.11
# GCC 9.5 needs no patches: its libstdc++ already handles musl/__GLIBC_PREREQ,
# and the 4.7-era alloca/ctype fixes do not apply. Add reactively only.

triple_of() {
    case "$ARCH" in
        amd64)   printf x86_64-linux-gnu ;;
        aarch64) printf aarch64-linux-gnu ;;
    esac
}

setup_build_environment() {
    case "$version" in
        16.1.0)
            # In-tree gmp's AC_PROG_LEX fatally runs flex's output probe if flex
            # is on PATH; flex is only used by gmp demos, so skip the probe.
            export ac_cv_prog_lex_root=lex.yy
            # Force inhibit_libc (GCC honors a pre-set value). A native
            # --without-headers build would otherwise try to use a target libc;
            # true makes libgcc build the minimal no-libc set (mirrors cross).
            export inhibit_libc=true
            ;;
    esac
}

# GCC requires an out-of-tree build dir: configure in _build/ and stay there
# (phases share one shell, so the cd persists into build/install).
configure() {
    case "$version" in
        4.7-2013.11) configure_47 ;;
        9.5.0)       configure_95 ;;
        16.1.0)      configure_boot0 ;;
    esac
}

configure_47() {
    case "$ARCH" in
        amd64)   triple=x86_64-unknown-linux-musl ;;
        aarch64) triple=aarch64-unknown-linux-musl ;;
    esac
    mkdir -p _build
    cd _build
    # C only is built (--disable-build-with-cxx), but gcc/configure still
    # runs a fatal AC_PROG_CXXCPP probe; `tcc -E` satisfies it (tcc cannot
    # compile C++ but preprocesses it fine; no C++ is actually compiled by
    # the stage1 tools).
    ../configure \
        CC=tcc \
        CC_FOR_BUILD=tcc \
        CXX=tcc \
        "CXXCPP=tcc -E" \
        CFLAGS=-DHAVE_ALLOCA_H \
        MAKEINFO=true \
        --prefix="$PREFIX" \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --with-sysroot="$(prefix_of musl)" \
        --with-native-system-header-dir=/include \
        --with-gmp="$(prefix_of gmp)" \
        --with-mpfr="$(prefix_of mpfr)" \
        --with-mpc="$(prefix_of mpc)" \
        --with-as="$(prefix_of binutils)/bin/as" \
        --with-ld="$(prefix_of binutils)/bin/ld" \
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

configure_95() {
    case "$ARCH" in
        amd64)   triple=x86_64-unknown-linux-musl ;;
        aarch64) triple=aarch64-unknown-linux-musl ;;
    esac
    gcc=$(prefix_of gcc-boot)/bin/gcc
    gxx=$(prefix_of gcc-boot)/bin/g++

    # GAP 2: shpack unpacks resources flat into stage_dir; relocate them into
    # the GCC tree as gmp/ mpfr/ mpc/ for the in-tree build. cwd is the gcc
    # source dir; gcc-* sorts before g{mp,mpfr}/mpc-*, so it is source_dir.
    local p
    for p in gmp mpfr mpc; do
        mv "$stage_dir"/$p-*/ "./$p"
        # The bundled config.sub/config.guess predate the `musl` OS; GCC 9.5's
        # top-level pair knows it -- overwrite to be safe. mpc-1.0.3 ships these
        # read-only (mode 555); cp -f unlinks the destination and retries.
        cp -f config.sub config.guess "./$p/"
    done

    # In-tree mpfr.h (mpfr/src) must be found while GCC compiles, before the
    # in-tree mpfr is installed into the build tree; plus the kernel uapi.
    export C_INCLUDE_PATH="$PWD/mpfr/src:$(prefix_of linux-headers)/include"
    # In-tree gmp's AC_PROG_LEX fatally runs flex's output probe when flex is on
    # PATH; preseed the cache var to skip it (flex is only used by gmp demos).
    export ac_cv_prog_lex_root=lex.yy

    mkdir -p _build
    cd _build
    # -O2 (not the configure default -g -O2): this is a throwaway bridge
    # compiler, so DWARF on its ~2300 objects (gcc proper, libgcc, libstdc++,
    # in-tree gmp/mpfr/mpc) is pure cost. CFLAGS/CXXFLAGS cover the host build
    # (incl. in-tree gmp/mpfr/mpc, which read them at their configure step);
    # *_FOR_TARGET cover libgcc/libstdc++. LIBCFLAGS etc. derive from these.
    ../configure \
        CC="$gcc" \
        CXX="$gxx" \
        CC_FOR_BUILD="$gcc" \
        CXX_FOR_BUILD="$gxx" \
        CFLAGS=-O2 \
        CXXFLAGS=-O2 \
        CFLAGS_FOR_TARGET=-O2 \
        CXXFLAGS_FOR_TARGET=-O2 \
        MAKEINFO=true \
        --prefix="$PREFIX" \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --with-sysroot="$(prefix_of musl)" \
        --with-native-system-header-dir=/include \
        --without-isl \
        --enable-languages=c,c++ \
        --enable-static \
        --disable-shared \
        --disable-bootstrap \
        --disable-multilib \
        --disable-libstdcxx-pch \
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

configure_boot0() {
    local triple gcc gxx p
    triple=$(triple_of)
    gcc=$(prefix_of gcc-boot)/bin/gcc
    gxx=$(prefix_of gcc-boot)/bin/g++

    # Relocate the flat-unpacked resources into the GCC tree as gmp/ mpfr/ mpc/.
    # cwd is the gcc source dir (gcc-* sorts before g{mp}/mpfr/mpc-*).
    for p in gmp mpfr mpc; do
        mv "$stage_dir"/$p-*/ "./$p"
        # Overwrite the bundled config.sub/guess with GCC 16's current pair
        # (knows musl/gnu). mpc ships them read-only; cp -f unlinks and retries.
        cp -f config.sub config.guess "./$p/"
    done

    mkdir -p build
    cd build
    # No target libc yet: --without-headers + --with-native-system-header-dir at
    # the conventional non-existent /nonexistent sentinel (never consulted under
    # inhibit_libc). --disable-fixincludes so it never scans host headers.
    # --disable-libstdc++-v3 / --disable-libcc1: gcc-9 has only static musl, no
    # shared libstdc++.so. --disable-lto(-plugin): liblto_plugin.so can't link
    # against non-PIC static musl. Just enough cc1/libgcc to compile glibc.
    # CFLAGS/CXXFLAGS=-O2 (not configure's default -g -O2): a throwaway bridge
    # compiler, so DWARF on cc1/cc1plus + libgcc is pure cost. *_FOR_TARGET
    # covers libgcc.
    ../configure \
        CONFIG_SHELL=/bin/sh \
        CC="$gcc" \
        CXX="$gxx" \
        MAKEINFO=true \
        CFLAGS=-O2 \
        CXXFLAGS=-O2 \
        CFLAGS_FOR_TARGET=-O2 \
        CXXFLAGS_FOR_TARGET=-O2 \
        --prefix="$PREFIX" \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --without-headers \
        --disable-fixincludes \
        --with-native-system-header-dir=/nonexistent \
        --disable-shared \
        --enable-languages=c,c++ \
        --disable-libstdc++-v3 \
        --disable-libcc1 \
        --disable-lto \
        --disable-lto-plugin \
        --without-isl \
        --disable-bootstrap \
        --disable-multilib \
        --disable-decimal-float \
        --disable-threads \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libitm \
        --disable-libsanitizer \
        --disable-libvtv \
        --disable-libssp \
        --disable-libquadmath \
        --disable-nls
}

build_args() {
    printf '%s\n' MAKEINFO=true
}

install() {
    local triple gcc_lib
    make install MAKEINFO=true
    case "$version" in
        16.1.0)
            # glibc links against libgcc_eh; the crippled build only makes
            # libgcc.a, so alias it (the EH unwinder objects live in libgcc.a).
            triple=$(triple_of)
            gcc_lib="$PREFIX/lib/gcc/$triple/16.1.0"
            if [ -f "$gcc_lib/libgcc.a" ] && [ ! -e "$gcc_lib/libgcc_eh.a" ]; then
                ln -s libgcc.a "$gcc_lib/libgcc_eh.a"
            fi
            ;;
    esac
}
