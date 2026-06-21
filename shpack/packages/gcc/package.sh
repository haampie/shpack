# SPDX-License-Identifier: MIT

description "Native aarch64 GCC 16.1.0 -- the final, shared compiler of the" \
            "bootstrap. Built by gcc-boot-wrapper against glibc 2.43 +" \
            "binutils, --enable-shared, threads=posix, real C++ EH."
homepage "https://gcc.gnu.org/"
license "GPL-3.0-or-later"

# The shared, glibc-linked production GCC 16. Same source as gcc-boot@16.1.0;
# the difference is how it's built (wrapped boot0 + glibc + binutils).
version 16.1.0 sha256=50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79 \
    url=https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz

build_system autotools

# Built by gcc-boot-wrapper against glibc 2.43, binutils (as/ld baked in),
# libstdcxx-boot1 (static libstdc++.a for the build tools). linux-headers:
# autoconf CPP sanity check (also symlinked into glibc's include).
depends_on gcc-boot-wrapper glibc binutils libstdcxx-boot1 linux-headers \
    zlib-ng@2.3.3-boot zstd@1.5.7-boot \
    gmake sed@4.9-musl grep@2.4-musl gawk@3.0.4 diffutils findutils tar@1.35-musl xz@5.2.5-musl
depends_on dash

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
    # gmp's AC_PROG_LEX fatally runs flex if on PATH; flex is only used by gmp
    # demos, so skip the probe.
    export ac_cv_prog_lex_root=lex.yy

    # The wrapped boot0 gcc has no default path to glibc's headers (it was
    # --without-headers), so host-side compiles (conftest, gengenrtl, ...) need
    # these on the include/library path. The in-tree libstdc++ compiles strip
    # libstdcxx-boot1 back out via the Makefile.in reset (below).
    local glibc triple libstdcxx zlib zstd
    glibc=$(prefix_of glibc)
    triple=$(triple gnu)
    libstdcxx=$(prefix_of libstdcxx-boot1)
    zlib=$(prefix_of zlib-ng)
    zstd=$(prefix_of zstd)
    # Static, glibc-linked zlib-ng/zstd (no .so -> static link into the compiler).
    export C_INCLUDE_PATH="$glibc/include:$zlib/include:$zstd/include"
    export CPLUS_INCLUDE_PATH="$libstdcxx/include:$libstdcxx/include/$triple:$glibc/include:$zlib/include:$zstd/include"
    export LIBRARY_PATH="$libstdcxx/lib64:$libstdcxx/lib:$glibc/lib:$zlib/lib:$zstd/lib"
}

ld_so_of() {
    case "$ARCH" in
        amd64)   printf ld-linux-x86-64.so.2 ;;
        aarch64) printf ld-linux-aarch64.so.1 ;;
    esac
}

edit() {
    local p
    # Relocate the flat-unpacked resources into the GCC tree as gmp/ mpfr/ mpc/.
    for p in gmp mpfr mpc; do
        mv "$stage_dir"/$p-*/ "./$p"
        cp -f config.sub config.guess "./$p/"
    done

    # `date > stamp-*` just touches a make stamp; `date` isn't in the seed
    # coreutils and a real date is non-reproducible.
    sed -i 's/date > stamp/touch stamp/g' libstdc++-v3/src/Makefile.in
}

configure() {
    local triple gcc glibc libstdcxx binutils zstd real_cc ld_so tflags
    triple=$(triple gnu)
    gcc=$(prefix_of gcc-boot-wrapper)
    glibc=$(prefix_of glibc)
    libstdcxx=$(prefix_of libstdcxx-boot1)
    binutils=$(prefix_of binutils)
    zstd=$(prefix_of zstd)
    ld_so=$(ld_so_of)
    # Flags for the freshly-built xgcc when it builds the target libs: point it
    # at glibc's loader + libs so its conftests link and run (see configure).
    tflags="-B$glibc/lib -L$glibc/lib -Wl,-rpath,$glibc/lib -Wl,--dynamic-linker=$glibc/lib/$ld_so"

    # GCC 16 makes implicit-function-declaration an error, failing gmp's
    # build-compiler probes (no CFLAGS). Wrap the boot0 gcc to demote it.
    real_cc="$gcc/bin/gcc"
    cat > "$stage_dir/cc-relaxed.sh" <<EOF
#!$sh
exec $real_cc "\$@" -Wno-error=implicit-function-declaration
EOF
    chmod 755 "$stage_dir/cc-relaxed.sh"

    # Strip libstdcxx-boot1 from CPLUS_INCLUDE_PATH for every libstdc++-v3 compile
    # (GCC bug 100017): its headers share include guards with the in-tree
    # libstdc++, so an in-tree #include_next would hit the boot1 wrapper and never
    # reach glibc's header. Reset to just glibc (kernel headers are symlinked in).
    local reset="CPLUS_INCLUDE_PATH = $glibc/include\nexport CPLUS_INCLUDE_PATH\n"
    local mk
    for mk in $(find libstdc++-v3 -name Makefile.in); do
        sed -i "s|^AM_CXXFLAGS = |${reset}AM_CXXFLAGS = |" "$mk"
    done
    # PCH rules use PCHFLAGS, not AM_CXXFLAGS. ^ avoids matching glibcxx_PCHFLAGS.
    sed -i "s|^PCHFLAGS = |${reset}PCHFLAGS = |" libstdc++-v3/include/Makefile.in

    # Target-lib loader via *_FOR_TARGET, not --with-sysroot. xgcc's baked default
    # loader /lib/ld-linux-... is missing in our chroot, so target conftests fail
    # "cannot run C compiled programs". --with-sysroot makes ld double-prepend the
    # sysroot to the absolute paths in glibc's libc.so linker script. Instead pass
    # the loader/libdir as $tflags to the target compiler only; the installed
    # driver's runtime paths come from the specs file (install).
    # CFLAGS/CXXFLAGS=-O2 drops DWARF from host objects (cc1, ...); *_FOR_TARGET
    # keep -g so the shipped libs stay debuggable.
    # file_prefix_map goes in CPPFLAGS, not CFLAGS/CXXFLAGS: genchecksum hashes
    # ALL_LINKERFLAGS (= ALL_CXXFLAGS) into cc1's checksum but not ALL_CPPFLAGS,
    # so the $stage_dir path reaches every compile without entering the hash.
    export CC="$stage_dir/cc-relaxed.sh"
    export CFLAGS="-O2"
    export CXXFLAGS="-O2"
    export CPPFLAGS="$file_prefix_map"
    export LDFLAGS="-L$libstdcxx/lib64 -L$libstdcxx/lib"
    export CFLAGS_FOR_TARGET="-g -O2 $tflags $file_prefix_map"
    export CXXFLAGS_FOR_TARGET="-g -O2 $tflags $file_prefix_map"
    export LDFLAGS_FOR_TARGET="$tflags"

    mkdir -p build
    cd build
    "$sh" ../configure \
        "CONFIG_SHELL=$sh" \
        "CXX=$gcc/bin/g++" \
        MAKEINFO=true \
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
        --with-system-zlib \
        --with-zstd-include="$zstd/include" \
        --with-zstd-lib="$zstd/lib" \
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

    # Write a specs file so plain gcc/g++ find glibc's startfiles + dynamic linker
    # and use binutils's as/ld -- no wrapper scripts or env vars needed.
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
    # Seed with the full -dumpspecs set so *cc1_cpu (-march=native autodetection)
    # survives; a partial specs file silently disables it. $(...) strips dumpspecs'
    # trailing blank line; re-emit exactly one (a double blank before '#' is
    # "specs file malformed").
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
