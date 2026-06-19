# SPDX-License-Identifier: MIT

description "GNU awk. 3.0.4 is the tiny tcc-built awk that scripts the early" \
            "chain's configure/Makefiles; 5.3.1 is the modern awk the glibc cap" \
            "needs (glibc 2.43's configure rejects 3.0.4 as too old, < 3.1.2);" \
            "5.3.2 is the glibc awk built with the final gcc 16, user-facing."
homepage "https://www.gnu.org/software/gawk/"
license "GPL-2.0-or-later"

# 3.0.4: grown by tcc against the kaem-external musl 1.1.24, driven by a
# replacement files/Makefile (its own configure needs tools we lack this early).
version 3.0.4 sha256=5cc35def1ff4375a8b9a98c2ff79e95e80987d24f0d42fdbb7b7039b3ddb3fb0 \
    url=https://mirrors.kernel.org/gnu/gawk/gawk-3.0.4.tar.gz

# 5.3.1: built by the gcc-9.5 bridge against static musl 1.2.5. Lower-chain
# consumers pin gawk@3.0.4, so this newer version never hijacks them (the glibc
# cap asks for gawk@5.3.1 explicitly).
version 5.3.1 sha256=694db764812a6236423d4ff40ceb7b6c4c441301b72ad502bb5c27e00cd56f78 \
    url=https://ftp.gnu.org/gnu/gawk/gawk-5.3.1.tar.xz

# 5.3.2: built with the final gcc 16 against glibc -- the user-facing awk.
version 5.3.2 sha256=f8c3486509de705192138b00ef2c00bbbdd0e84c30d5c07d23fc73a9dc4cc9cc \
    url=https://ftpmirror.gnu.org/gawk/gawk-5.3.2.tar.xz

# 3.0.4 builds from a shipped Makefile (no configure); 5.3.1/5.3.2 are autotools.
# The two build systems diverge, and `build_system` cannot vary per version, so
# use `generic` and branch install() on $version.
build_system generic

# Shared: grep (both configure/build scripts use it); the tcc-built 2.4-musl is
# fine as a build tool for every version.
depends_on grep@2.4-musl
# 3.0.4: tcc + kaem-external musl 1.1.24, seed make on PATH (no gmake dep).
depends_on tcc musl@1.1.24 when=3.0.4
# 5.3.1: gcc 9.5 + binutils 2.30 (as/ld on PATH). Modern sed/tar: 5.3.1's
# configure needs sed -E and its tarball is xz.
depends_on gcc-boot@9.5.0 binutils@2.30-musl gmake sed@4.9-musl tar@1.35-musl xz@5.2.5-musl \
    when=5.3.1
# 5.3.2: gcc 16 via compiler-wrapper, with the glibc sed/tar/xz build tools.
depends_on compiler-wrapper gmake sed@4.9 tar@1.35 xz@5.8.3 when=5.3.2

edit() {
    # gawk's system()/`| getline`/`print | "cmd"` execl a hardcoded "/bin/sh"
    # (builtin.c, io.c), bypassing libc, so the musl patch can't reach it. The
    # sandbox has no host /bin/sh -- repoint at the store shell. (glibc's
    # gen-sorted.awk does system("test -d ..."); without this the build descends
    # into no subdirs and links an empty libc.)
    replace_bin_sh builtin.c io.c
}

install() {
    local triple
    case "$version" in
        3.0.4)
            # Replicate the old `makefile` build system: a replacement Makefile
            # (files/Makefile) drives the tcc build (PREFIX-parameterized).
            cp "$package_dir/files/Makefile" ./Makefile
            make -f Makefile $makejobs PREFIX="$PREFIX"
            make -f Makefile PREFIX="$PREFIX" install
            ;;
        5.3.1)
            triple=$(triple musl)
            # --disable-extensions: gawk's loadable .so extensions can't link
            # against the non-PIC static musl 1.2.5 libc.a (R_AARCH64 reloc
            # errors); the interpreter doesn't need them and glibc just runs gawk.
            # CFLAGS=-O2 drops the autotools default -g: a never-debugged build
            # tool whose -g would leak the build cwd as comp_dir (see builder.sh).
            "$sh" ./configure \
                "CONFIG_SHELL=$sh" \
                "CC=$(prefix_of gcc-boot)/bin/gcc" \
                CFLAGS=-O2 \
                MAKEINFO=true \
                --build="$triple" \
                --host="$triple" \
                --prefix="$PREFIX" \
                --disable-nls \
                --disable-mpfr \
                --disable-extensions \
                --without-libsigsegv-prefix
            make $makejobs
            make install
            ;;
        5.3.2)
            # gcc 16 via the wrapper. glibc could load .so extensions, but the
            # interpreter doesn't need them here, so keep the build lean. -g is
            # reproducible at this layer, so no CFLAGS=-O2.
            triple=$(triple gnu)
            "$sh" ./configure \
                "CONFIG_SHELL=$sh" \
                CC=gcc \
                MAKEINFO=true \
                --build="$triple" \
                --host="$triple" \
                --prefix="$PREFIX" \
                --disable-nls \
                --disable-mpfr \
                --disable-extensions \
                --without-libsigsegv-prefix
            make $makejobs
            make install
            ;;
    esac
}
