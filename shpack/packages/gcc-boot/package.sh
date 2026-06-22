# SPDX-License-Identifier: MIT

description "GCC bootstrap compilers (throwaway). 4.7 (Linaro, grown by tcc on" \
            "musl) bootstraps 9.5 (the bridge to modern GCC); 9.5 builds the" \
            "crippled 16.1.0 (--without-headers) that compiles glibc 2.43. The" \
            "shipped, glibc-linked GCC 16 is a separate recipe, packages/gcc."
homepage "https://gcc.gnu.org/"
license "GPL-3.0-or-later"

# Newest first (the first-declared version is the default for a bare name);
# every consumer pins the stage it wants, so order is for convention only.

# 16.1.0 'crippled' (--without-headers): no target libc, just enough cc1/libgcc
# to compile glibc 2.43.
version 16.1.0 sha256=50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79 \
    url=https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz

# 9.5.0: mature C++17, builds cleanly on musl; the bridge to modern GCC, built
# by the chain's own 4.7 g++.
version 9.5.0 sha256=27769f64ef1d4cd5e2be8682c0c93f9887983e6cfd1a927ce5a0a2915a95cf8f \
    url=https://ftpmirror.gnu.org/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz

# 4.7-2013.11: Linaro snapshot (FSF 4.7 lacks native aarch64), grown by tcc.
version 4.7-2013.11 sha256=d0ea2c72ceb66d3851986840dd8962941824a2980a8aca2a800abb5b489acedf \
    url=https://launchpadlibrarian.net/156843777/gcc-linaro-4.7-2013.11.tar.bz2

build_system autotools

# GCC forbids an in-tree build; configure/build/install all happen in _build/.
build_directory _build

# Build tools shared by all gcc versions.
depends_on gmake grep@2.4-musl diffutils findutils

# 4.7-2013.11: grown by tcc against musl 1.1.24, external gmp/mpfr/mpc, binutils
# 2.30.
depends_on tcc musl@1.1.24 binutils@2.30-musl gmp mpfr mpc \
    m4 gawk@3.0.4 when=4.7-2013.11

# 9.5.0: built by the chain's own 4.7 g++; musl 1.2.5 sysroot, kernel headers,
# binutils 2.30. gmp/mpfr/mpc are in-tree resources (4.3.2/2.4.2 are too old).
depends_on gcc-boot@4.7-2013.11 musl@1.2.5 linux-headers binutils@2.30-musl m4@1.4.7 tar@1.35-musl \
    xz@5.2.5-musl gawk@3.0.4 when=9.5.0

# 16.1.0: built by the chain's own 9.5 g++; binutils 2.46 supplies the as/ld it
# assembles with and bakes into its specs. sed/tar for 16's pax tarball.
depends_on gcc-boot@9.5.0 binutils@2.46.0-musl sed@4.9-musl tar@1.35-musl xz@5.2.5-musl gawk@5.3.1 when=16.1.0
depends_on dash@0.5.12

# GCC 9.5's download_prerequisites set, in-tree as gmp/ mpfr/ mpc/ for
# auto-detection. ISL omitted (Graphite only; --without-isl).
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
# libiberty's C_alloca conflicts with musl's alloca; rename it (same fix as Guix).
patch 0001-alloca.patch when=4.7-2013.11
# Work around a tcc 0.9.27 AArch64 spill-slot collision that miscompiles a nested
# struct-return call in set_lattice_value, crashing the tcc-built cc1 in tree-ccp.
# See bugs/tcc-aarch64-nested-struct-return-spill.md.
patch 0002-tree-ssa-ccp-spill.patch when=4.7-2013.11
# os_defines.h uses __GLIBC_PREREQ(2,15), undefined on musl; guard it.
patch 0003-libstdcxx-musl-glibc-prereq.patch when=4.7-2013.11
# gnu-linux ctype uses glibc-internal masks absent on musl; swap in the portable
# config/os/generic ctype (same as Alpine / musl-cross-make).
patch 0004-libstdcxx-generic-ctype.patch when=4.7-2013.11
# 9.5 needs no patches (its libstdc++ already handles musl). Add reactively only.

edit() {
    local p
    case "$version" in
        4.7-2013.11)
            # Blank libgcc's hardcoded -g: 4.7's -fdebug-prefix-map misses the
            # include-fixed path it leaks into .debug_*, and a make-var override
            # can't reach the libgcc sub-make (gcc forwards only FLAGS_TO_PASS).
            sed -i 's/^LIBGCC2_DEBUG_CFLAGS = -g$/LIBGCC2_DEBUG_CFLAGS =/' \
                libgcc/Makefile.in
            ;;
        9.5.0|16.1.0)
            # Relocate the flat-unpacked gmp/mpfr/mpc resources into the GCC tree
            # for auto-detection. cwd is the gcc source dir (it sorts first).
            for p in gmp mpfr mpc; do
                mv "$stage_dir"/$p-*/ "./$p"
                # The bundled config.sub/guess predate musl; overwrite with GCC's
                # pair. mpc ships them read-only (555); cp -f unlinks and retries.
                cp -f config.sub config.guess "./$p/"
            done
            ;;
    esac
}

setup_build_environment() {
    case "$version" in
        9.5.0|16.1.0)
            # gmp's AC_PROG_LEX fatally runs flex if on PATH; flex is only used by
            # gmp demos, so skip the probe.
            export ac_cv_prog_lex_root=lex.yy
            ;;
    esac
    case "$version" in
        4.7-2013.11)
            # edit() drops libgcc's -g; debug_prefix_map still covers any other
            # target debug. Env-passed to keep $stage_dir out of gcc 4.7's configargs.
            export CFLAGS_FOR_TARGET="-O2 $debug_prefix_map"
            export CXXFLAGS_FOR_TARGET="-O2 $debug_prefix_map"
            ;;
        9.5.0)
            # In-tree mpfr.h (mpfr/src) must be found while GCC compiles, plus the
            # kernel uapi. $PWD is the gcc source dir (before the out-of-tree cd).
            export C_INCLUDE_PATH="$PWD/mpfr/src:$(prefix_of linux-headers)/include"
            # -ffile-prefix-map for .c, but gcc 9.5's driver doesn't forward it to
            # the assembler, so libgcc's .S stubs leak comp_dir -- add the older
            # -fdebug-prefix-map, which it does forward. Env-passed.
            export CFLAGS_FOR_TARGET="-O2 $file_prefix_map $debug_prefix_map"
            export CXXFLAGS_FOR_TARGET="-O2 $file_prefix_map $debug_prefix_map"
            ;;
        16.1.0)
            # Force inhibit_libc: a native --without-headers build would otherwise
            # use a target libc; true makes libgcc build the minimal no-libc set.
            export inhibit_libc=true
            # Env-set to keep $stage_dir out of TOPLEVEL_CONFIGURE_ARGUMENTS.
            # file_prefix_map goes in CPPFLAGS, not CFLAGS/CXXFLAGS: genchecksum
            # hashes ALL_LINKERFLAGS (= ALL_CXXFLAGS) into cc1's checksum but not
            # ALL_CPPFLAGS, so the scratch path never enters the hash.
            export CFLAGS="-O2"
            export CXXFLAGS="-O2"
            export CPPFLAGS="$file_prefix_map"
            export CFLAGS_FOR_TARGET="-O2 $file_prefix_map"
            export CXXFLAGS_FOR_TARGET="-O2 $file_prefix_map"
            ;;
    esac
}

# Shared base (the throwaway-compiler target-lib disables) + per-version deltas.
# --prefix and --disable-dependency-tracking come from default_configure.
configure_args() {
    local triple gcc gxx
    case "$version" in
        4.7-2013.11) triple=$(triple musl unknown) ;;
        9.5.0)       triple=$(triple musl unknown) ;;
        16.1.0)      triple=$(triple gnu) ;;
    esac
    # Common: native build, C/C++ only, static, no optional target libraries.
    printf '%s\n' \
        MAKEINFO=true \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --enable-languages=c,c++ \
        --disable-shared \
        --disable-bootstrap \
        --disable-multilib \
        --disable-decimal-float \
        --disable-lto \
        --disable-lto-plugin \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libitm \
        --disable-libquadmath \
        --disable-libsanitizer \
        --disable-libssp \
        --disable-libvtv
    case "$version" in
        4.7-2013.11)
            # tcc, external gmp/mpfr/mpc + musl sysroot. C only is built, but
            # configure still runs a fatal AC_PROG_CXXCPP probe; `tcc -E` satisfies
            # it (no C++ is actually compiled by the stage1 tools).
            printf '%s\n' \
                CC=tcc \
                CC_FOR_BUILD=tcc \
                CXX=tcc \
                'CXXCPP=tcc -E' \
                CFLAGS=-DHAVE_ALLOCA_H \
                --with-sysroot="$(prefix_of musl)" \
                --with-native-system-header-dir=/include \
                --with-gmp="$(prefix_of gmp)" \
                --with-mpfr="$(prefix_of mpfr)" \
                --with-mpc="$(prefix_of mpc)" \
                --with-as="$(prefix_of binutils)/bin/as" \
                --with-ld="$(prefix_of binutils)/bin/ld" \
                --enable-static \
                --enable-threads=single \
                --disable-threads \
                --disable-libstdcxx-pch \
                --disable-build-with-cxx \
                --disable-plugin \
                --disable-libcilkrts \
                --disable-libmudflap
            ;;
        9.5.0)
            # 4.7 g++, musl sysroot, in-tree gmp/mpfr/mpc. -O2 (not -g -O2): a
            # throwaway bridge, so DWARF on its ~2300 objects is pure cost.
            # CFLAGS/CXXFLAGS cover the host build; *_FOR_TARGET cover libgcc/libstdc++.
            gcc=$(prefix_of gcc-boot)/bin/gcc
            gxx=$(prefix_of gcc-boot)/bin/g++
            printf '%s\n' \
                CC="$gcc" \
                CXX="$gxx" \
                CC_FOR_BUILD="$gcc" \
                CXX_FOR_BUILD="$gxx" \
                CFLAGS=-O2 \
                CXXFLAGS=-O2 \
                --with-sysroot="$(prefix_of musl)" \
                --with-native-system-header-dir=/include \
                --without-isl \
                --enable-static \
                --disable-libstdcxx-pch \
                --disable-plugin \
                --disable-libcilkrts \
                --disable-libmudflap
            ;;
        16.1.0)
            # Crippled boot0: no target libc. --without-headers, header-dir
            # /nonexistent (never consulted under inhibit_libc), --disable-fixincludes
            # so it never scans host headers. No libstdc++-v3/libcc1 (gcc-9 has only
            # static musl). Just enough cc1/libgcc to compile glibc.
            gcc=$(prefix_of gcc-boot)/bin/gcc
            gxx=$(prefix_of gcc-boot)/bin/g++
            # CFLAGS*/CXXFLAGS* set in setup_build_environment to keep
            # file_prefix_map's $stage_dir out of the configargs string.
            printf '%s\n' \
                CC="$gcc" \
                CXX="$gxx" \
                --without-headers \
                --disable-fixincludes \
                --with-native-system-header-dir=/nonexistent \
                --disable-libstdc++-v3 \
                --disable-libcc1 \
                --without-isl \
                --disable-threads \
                --disable-nls
            ;;
    esac
}

build_args() {
    printf '%s\n' MAKEINFO=true
}

install() {
    local triple gcc_lib
    make install MAKEINFO=true
    case "$version" in
        16.1.0)
            # glibc links libgcc_eh; the crippled build only makes libgcc.a (which
            # holds the EH objects), so alias it.
            triple=$(triple gnu)
            gcc_lib="$PREFIX/lib/gcc/$triple/16.1.0"
            if [ -f "$gcc_lib/libgcc.a" ] && [ ! -e "$gcc_lib/libgcc_eh.a" ]; then
                ln -s libgcc.a "$gcc_lib/libgcc_eh.a"
            fi
            ;;
    esac
}
