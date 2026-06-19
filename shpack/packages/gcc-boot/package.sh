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

# GCC forbids an in-tree build; configure/build/install all happen in _build/.
build_directory _build

# Build tools shared by all gcc versions.
depends_on gmake grep@2.4-musl gawk@3.0.4 diffutils findutils

# 4.7-2013.11: grown by tcc against the kaem-external musl 1.1.24, with the
# external gmp/mpfr/mpc and binutils 2.30. (Pinned so newer siblings added for
# later stages -- musl 1.2.5, binutils 2.46, m4 1.4.19 -- don't perturb it.)
depends_on tcc musl@1.1.24 binutils@2.30-musl gmp@4.3.2 mpfr@2.4.2 mpc@1.0.3 \
    m4@1.4.7 when=4.7-2013.11

# 9.5.0: built by the chain's own 4.7 g++, modern musl 1.2.5 (the modern musl 1.2.5
# recipe -- a distinct name so it does not hijack bare `musl` for the whole
# lower chain) sysroot, kernel headers, binutils 2.30. gmp/mpfr/mpc are unpacked
# in-tree (resources below), not external deps -- 4.3.2/2.4.2 are too old.
depends_on gcc-boot@4.7-2013.11 musl@1.2.5 linux-headers binutils@2.30-musl m4@1.4.7 tar@1.35-musl \
    xz@5.2.5-musl when=9.5.0

# 16.1.0: built by the chain's own 9.5 g++, with binutils 2.46 supplying the
# as/ld it assembles/links with AND bakes into its specs. sed/tar: 16's pax
# tarball + modern configure. (gmake/grep/gawk/diffutils from the shared line.)
depends_on gcc-boot@9.5.0 binutils@2.46.0-musl sed@4.9-musl tar@1.35-musl xz@5.2.5-musl when=16.1.0

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

edit() {
    local p
    case "$version" in
        9.5.0|16.1.0)
            # GAP 2: shpack unpacks the in-tree gmp/mpfr/mpc resources flat into
            # stage_dir; relocate them into the GCC tree as gmp/ mpfr/ mpc/ so
            # configure auto-detects them. cwd is the gcc source dir (gcc-* sorts
            # before g{mp}/mpfr/mpc-*, so do_stage picked it as source_dir).
            for p in gmp mpfr mpc; do
                mv "$stage_dir"/$p-*/ "./$p"
                # The bundled config.sub/guess predate the `musl` OS; overwrite
                # with GCC's top-level pair (knows musl/gnu). mpc ships them
                # read-only (mode 555); cp -f unlinks the dest and retries.
                cp -f config.sub config.guess "./$p/"
            done
            ;;
    esac
}

setup_build_environment() {
    case "$version" in
        9.5.0|16.1.0)
            # In-tree gmp's AC_PROG_LEX fatally runs flex's output probe if flex
            # is on PATH; flex is only used by gmp demos, so skip the probe.
            export ac_cv_prog_lex_root=lex.yy
            ;;
    esac
    case "$version" in
        4.7-2013.11)
            # Target libgcc forces -g internally regardless of CFLAGS_FOR_TARGET,
            # so its comp_dir leaks the scratch path. xgcc here is gcc 4.7 (only
            # -fdebug-prefix-map, no -ffile-prefix-map). Env-pass (not a configure
            # arg) so the $stage_dir value stays out of gcc 4.7's own configargs.
            export CFLAGS_FOR_TARGET="-O2 $debug_prefix_map"
            export CXXFLAGS_FOR_TARGET="-O2 $debug_prefix_map"
            ;;
        9.5.0)
            # In-tree mpfr.h (mpfr/src) must be found while GCC compiles, before
            # the in-tree mpfr is installed into the build tree; plus the kernel
            # uapi. $PWD is the gcc source dir here (before the out-of-tree cd).
            export C_INCLUDE_PATH="$PWD/mpfr/src:$(prefix_of linux-headers)/include"
            # As 4.7, but xgcc is gcc 9.5 -- use the full -ffile-prefix-map for .c.
            # libgcc's .S stubs (avx_*, morestack, ...) leak their comp_dir via the
            # ASSEMBLER, though: gcc 9.5's driver does not translate -ffile-prefix-map
            # into the as --debug-prefix-map (gcc 16's does -- its libgcc is clean),
            # so add the older -fdebug-prefix-map, which it does forward (same root
            # cause as glibc's .S csu objects). Env-passed to keep $stage_dir out of
            # gcc 9.5's configargs.
            export CFLAGS_FOR_TARGET="-O2 $file_prefix_map $debug_prefix_map"
            export CXXFLAGS_FOR_TARGET="-O2 $file_prefix_map $debug_prefix_map"
            ;;
        16.1.0)
            # Force inhibit_libc (GCC honors a pre-set value). A native
            # --without-headers build would otherwise try to use a target libc;
            # true makes libgcc build the minimal no-libc set (mirrors cross).
            export inhibit_libc=true
            # Env-set so the $stage_dir inside $file_prefix_map stays out of
            # TOPLEVEL_CONFIGURE_ARGUMENTS. file_prefix_map in CPPFLAGS rather than
            # CFLAGS/CXXFLAGS: genchecksum hashes ALL_LINKERFLAGS (= ALL_CXXFLAGS,
            # which includes CXXFLAGS) into cc1's executable_checksum; ALL_CPPFLAGS
            # is excluded from that chain, so the scratch path never enters the hash.
            export CFLAGS="-O2"
            export CXXFLAGS="-O2"
            export CPPFLAGS="$file_prefix_map"
            export CFLAGS_FOR_TARGET="-O2 $file_prefix_map"
            export CXXFLAGS_FOR_TARGET="-O2 $file_prefix_map"
            ;;
    esac
}

# Out-of-tree (build_directory _build) via the standard autotools configure
# phase. A shared base -- the throwaway-compiler target-lib disables common to
# all three stages -- plus per-version deltas. --prefix and
# --disable-dependency-tracking are supplied by default_configure.
configure_args() {
    local triple gcc gxx
    case "$version" in
        4.7-2013.11) triple=$(triple musl unknown) ;;
        9.5.0)       triple=$(triple musl unknown) ;;
        16.1.0)      triple=$(triple gnu) ;;
    esac
    # Common to all stages: native build, C/C++ only, static, and none of the
    # optional target libraries (this is a throwaway compiler).
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
            # tcc-built C compiler, external gmp/mpfr/mpc + musl sysroot. C only
            # is built (--disable-build-with-cxx), but gcc/configure still runs a
            # fatal AC_PROG_CXXCPP probe; `tcc -E` satisfies it (tcc preprocesses
            # C++ fine; no C++ is actually compiled by the stage1 tools).
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
            # Built by the chain's own 4.7 g++ against the musl sysroot, in-tree
            # gmp/mpfr/mpc. -O2 (not the default -g -O2): a throwaway bridge
            # compiler, so DWARF on its ~2300 objects is pure cost. CFLAGS/CXXFLAGS
            # cover the host build (incl. in-tree gmp/mpfr/mpc, read at their
            # configure step); *_FOR_TARGET cover libgcc/libstdc++.
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
            # The crippled boot0: no target libc yet. --without-headers +
            # --with-native-system-header-dir=/nonexistent (never consulted under
            # inhibit_libc). --disable-fixincludes so it never scans host headers.
            # --disable-libstdc++-v3/--disable-libcc1: gcc-9 has only static musl,
            # no shared libstdc++.so. Just enough cc1/libgcc to compile glibc.
            gcc=$(prefix_of gcc-boot)/bin/gcc
            gxx=$(prefix_of gcc-boot)/bin/g++
            # CFLAGS*/CXXFLAGS* are exported in setup_build_environment (env, not
            # argv) to keep file_prefix_map's $stage_dir out of the configargs string.
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
            # glibc links against libgcc_eh; the crippled build only makes
            # libgcc.a, so alias it (the EH unwinder objects live in libgcc.a).
            triple=$(triple gnu)
            gcc_lib="$PREFIX/lib/gcc/$triple/16.1.0"
            if [ -f "$gcc_lib/libgcc.a" ] && [ ! -e "$gcc_lib/libgcc_eh.a" ]; then
                ln -s libgcc.a "$gcc_lib/libgcc_eh.a"
            fi
            ;;
    esac
}
