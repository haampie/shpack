# SPDX-License-Identifier: MIT

description "Native aarch64 GCC 16.1.0 -- the final, shared compiler of the" \
            "bootstrap. Built by gcc-boot0-wrapped against glibc 2.43 +" \
            "binutils, --enable-shared, threads=posix, real C++ EH."
homepage "https://gcc.gnu.org/"
license "GPL-3.0-or-later"

# Separate recipe from gcc (4.7/9.5) and gcc-boot@16.1.0 (16.1.0, crippled): this is
# the shared, glibc-linked production GCC 16. Same source as gcc-boot@16.1.0; the
# difference is entirely in how it's built (wrapped boot0 + glibc + binutils).
version 16.1.0 sha256=50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79 \
    url=https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz

build_system autotools

# Built by gcc-boot0-wrapped against glibc 2.43, binutils (as/ld baked in),
# libstdcxx-boot1 (static libstdc++.a for the build tools it compiles).
# linux-headers: autoconf CPP sanity check (kernel headers are symlinked into
# glibc's include, so --with-native-system-header-dir=glibc covers both).
depends_on gcc-boot0-wrapped glibc binutils@2.46.0 libstdcxx-boot1 linux-headers \
    gmake sed grep gawk@3.0.4 diffutils findutils tar xz

# Same in-tree gmp/mpfr/mpc as gcc-boot@16.1.0 (GCC 16's prerequisite set).
resource when=16.1.0 \
    url=https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.bz2 \
    sha256=ac28211a7cfb609bae2e2c8d6058d66c8fe96434f740cf6fe2e47b000d1c20cb
resource when=16.1.0 \
    url=https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.bz2 \
    sha256=b9df93635b20e4089c29623b19420c4ac848a1b29df1cfd59f26cab0d2666aa0
resource when=16.1.0 \
    url=https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz \
    sha256=ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8

setup_build_environment() {
    # In-tree gmp's AC_PROG_LEX fatally runs flex's output probe if flex is on
    # PATH; flex is only used by gmp demos, so skip the probe.
    export ac_cv_prog_lex_root=lex.yy

    # The wrapped boot0 gcc has no default path to glibc's headers (gcc-boot@16.1.0
    # was --without-headers), so the top-level configure's conftest compile and
    # the C++ build tools (gengenrtl, ...) wouldn't find <stdio.h>/<new>.
    # --with-native-system-header-dir only affects the gcc being built, not these
    # host-side compiles. Mirror binutils's env. The in-tree libstdc++
    # compiles strip libstdcxx-boot1 back out via the Makefile.in reset (below).
    local glibc triple libstdcxx
    glibc=$(prefix_of glibc)
    triple=$(triple gnu)
    libstdcxx=$(prefix_of libstdcxx-boot1)
    export C_INCLUDE_PATH="$glibc/include"
    export CPLUS_INCLUDE_PATH="$libstdcxx/include:$libstdcxx/include/$triple:$glibc/include"
    export LIBRARY_PATH="$libstdcxx/lib64:$libstdcxx/lib:$glibc/lib"
}

ld_so_of() {
    case "$ARCH" in
        amd64)   printf ld-linux-x86-64.so.2 ;;
        aarch64) printf ld-linux-aarch64.so.1 ;;
    esac
}

configure() {
    local triple gcc glibc libstdcxx binutils p real_cc ld_so tflags
    triple=$(triple gnu)
    gcc=$(prefix_of gcc-boot0-wrapped)
    glibc=$(prefix_of glibc)
    libstdcxx=$(prefix_of libstdcxx-boot1)
    binutils=$(prefix_of binutils)
    ld_so=$(ld_so_of)
    # Flags handed to the freshly-built xgcc when it builds the TARGET libs
    # (libgcc, libatomic, libstdc++): point it at glibc's loader + libs so its
    # configure conftests link and run. See the comment at the configure call.
    tflags="-B$glibc/lib -L$glibc/lib -Wl,-rpath,$glibc/lib -Wl,--dynamic-linker=$glibc/lib/$ld_so"

    # Relocate the flat-unpacked resources into the GCC tree as gmp/ mpfr/ mpc/.
    for p in gmp mpfr mpc; do
        mv "$stage_dir"/$p-*/ "./$p"
        cp -f config.sub config.guess "./$p/"
    done

    # GCC 16 makes implicit-function-declaration an error. The in-tree gmp's
    # build-compiler probes (main(){exit(0);}) compile with no CFLAGS and would
    # fail. Wrap the wrapped-boot0 gcc to demote that error.
    real_cc="$gcc/bin/gcc"
    cat > "$stage_dir/cc-relaxed.sh" <<EOF
#!/bin/sh
exec $real_cc "\$@" -Wno-error=implicit-function-declaration
EOF
    chmod 755 "$stage_dir/cc-relaxed.sh"

    # Strip the external libstdcxx-boot1 from CPLUS_INCLUDE_PATH for EVERY
    # libstdc++-v3 C++ compile (GCC bug 100017): its headers share include
    # guards with the in-tree libstdc++ being built, so an in-tree
    # #include_next would hit the boot1 wrapper and never reach glibc's real
    # header. Reset CPLUS_INCLUDE_PATH to just glibc; the kernel headers are
    # symlinked into glibc/include and --with-native-system-header-dir=glibc
    # keeps libc headers available.
    local reset="CPLUS_INCLUDE_PATH = $glibc/include\nexport CPLUS_INCLUDE_PATH\n"
    local mk
    for mk in $(find libstdc++-v3 -name Makefile.in); do
        sed -i "s|^AM_CXXFLAGS = |${reset}AM_CXXFLAGS = |" "$mk"
    done
    # PCH rules use PCHFLAGS, not AM_CXXFLAGS. Anchor with ^ so it doesn't also
    # match glibcxx_PCHFLAGS.
    sed -i "s|^PCHFLAGS = |${reset}PCHFLAGS = |" libstdc++-v3/include/Makefile.in

    # libstdc++'s convenience-archive rules `date > stamp-*` just touch a make
    # stamp; `date` isn't in the seed coreutils and a real date is non-reproducible.
    sed -i 's/date > stamp/touch stamp/g' libstdc++-v3/src/Makefile.in

    # Target-lib loader, via *_FOR_TARGET (NOT --with-sysroot). The reference
    # builds the target libs (libgcc, libatomic, libstdc++) on a host whose
    # /lib/ld-linux-*.so exists, so the freshly-built xgcc's configure conftests
    # link+run against the host loader. Our chroot has no host glibc, so xgcc's
    # baked default loader /lib/ld-linux-... is missing and target conftests fail
    # "cannot run C compiled programs". --with-sysroot=$glibc fixes that but then
    # ld double-prepends the sysroot to the ABSOLUTE paths inside glibc's libc.so
    # linker script (GROUP ( $glibc/lib/libc.so.6 ... )) and can't find libc.
    # Instead pass the loader/libdir as $tflags to the target compiler only: the
    # absolute libc.so paths resolve normally and conftests get the right interp.
    # The installed driver's runtime paths are pinned by the specs file (install).
    # CFLAGS/CXXFLAGS=-O2 (not configure's default -g -O2) drops DWARF from the
    # HOST objects only (cc1/cc1plus/gcc/g++); *_FOR_TARGET below keep -g so the
    # shipped libs stay debuggable. This is the bootstrap's longest stage.
    mkdir -p build
    cd build
    ../configure \
        CONFIG_SHELL=/bin/sh \
        "CC=$stage_dir/cc-relaxed.sh" \
        "CXX=$gcc/bin/g++" \
        MAKEINFO=true \
        CFLAGS=-O2 \
        CXXFLAGS=-O2 \
        "LDFLAGS=-L$libstdcxx/lib64 -L$libstdcxx/lib" \
        "CFLAGS_FOR_TARGET=-g -O2 $tflags" \
        "CXXFLAGS_FOR_TARGET=-g -O2 $tflags" \
        "LDFLAGS_FOR_TARGET=$tflags" \
        --prefix="$PREFIX" \
        --build="$triple" \
        --host="$triple" \
        --target="$triple" \
        --with-native-system-header-dir="$glibc/include" \
        --with-as="$binutils/bin/as" \
        --with-ld="$binutils/bin/ld" \
        --enable-shared \
        --enable-languages=c,c++ \
        --enable-threads=posix \
        --enable-__cxa_atexit \
        --disable-bootstrap \
        --disable-dependency-tracking \
        --disable-multilib \
        --disable-werror \
        --disable-nls \
        --without-isl \
        --without-zstd \
        --disable-plugin
}

build_args() {
    printf '%s\n' MAKEINFO=true
}

install() {
    local triple glibc binutils ld_so specs_dir rpath_dir gcc_exe
    triple=$(triple gnu)
    glibc=$(prefix_of glibc)
    binutils=$(prefix_of binutils)
    ld_so=$(ld_so_of)

    make install MAKEINFO=true

    # Write a specs file into the installed GCC so plain gcc/g++ find glibc's
    # startfiles + dynamic linker and use binutils's as/ld -- no wrapper
    # scripts or env vars needed downstream.
    if [ -n "$(ls "$PREFIX"/lib64/libgcc_s.* 2>/dev/null)" ]; then
        rpath_dir="$PREFIX/lib64"
    elif [ -n "$(ls "$PREFIX"/lib/libgcc_s.* 2>/dev/null)" ]; then
        rpath_dir="$PREFIX/lib"
    else
        die "no libgcc_s.* found in lib/lib64"
    fi

    gcc_exe="$PREFIX/bin/gcc"
    specs_dir="$PREFIX/lib/gcc/$triple/16.1.0"
    mkdir -p "$specs_dir"
    # Seed with the FULL built-in spec set (-dumpspecs) so the *cc1_cpu section
    # (-mcpu/-march=native autodetection) is preserved; a partial prefix specs
    # file silently disables it. Capture via $(...) to strip dumpspecs' trailing
    # blank line, then re-emit exactly ONE blank line before the '#': GCC's specs
    # parser rejects a double blank line before a comment ("specs file malformed").
    local builtin_specs
    builtin_specs=$("$gcc_exe" -dumpspecs)
    {
        printf '%s\n' "$builtin_specs"
        cat <<EOF

# Generated by shpack: glibc loader/startfiles + binutils

*startfile_prefix_spec:
$glibc/lib/

*link:
+ %{!static:%{!static-pie:--dynamic-linker $glibc/lib/$ld_so}}

*link_libgcc:
+ -rpath $glibc/lib -L$rpath_dir -rpath $rpath_dir

*self_spec:
+ -B$binutils/bin/
EOF
    } > "$specs_dir/specs"
}
