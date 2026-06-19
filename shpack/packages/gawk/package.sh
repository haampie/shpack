# SPDX-License-Identifier: MIT

description "GNU awk. 3.0.4 is the tiny tcc-built awk that scripts the early" \
            "chain's configure/Makefiles; 5.3.1 is the modern awk the glibc cap" \
            "needs (glibc 2.43's configure rejects 3.0.4 as too old, < 3.1.2);" \
            "5.3.2 is the glibc awk built with the final gcc 16, user-facing."
homepage "https://www.gnu.org/software/gawk/"
license "GPL-2.0-or-later"

# 3.0.4: grown by tcc against musl 1.1.24, driven by a replacement files/Makefile
# (its own configure needs tools we lack this early).
version 3.0.4 sha256=5cc35def1ff4375a8b9a98c2ff79e95e80987d24f0d42fdbb7b7039b3ddb3fb0 \
    url=https://mirrors.kernel.org/gnu/gawk/gawk-3.0.4.tar.gz

# 5.3.1: built by the gcc-9.5 bridge against static musl 1.2.5; the modern awk
# the glibc cap needs (glibc 2.43's configure rejects 3.0.4 as too old).
version 5.3.1 sha256=694db764812a6236423d4ff40ceb7b6c4c441301b72ad502bb5c27e00cd56f78 \
    url=https://ftp.gnu.org/gnu/gawk/gawk-5.3.1.tar.xz

# 5.3.2: built with the final gcc 16 against glibc -- the user-facing awk.
version 5.3.2 sha256=f8c3486509de705192138b00ef2c00bbbdd0e84c30d5c07d23fc73a9dc4cc9cc \
    url=https://ftpmirror.gnu.org/gawk/gawk-5.3.2.tar.xz

# 3.0.4 builds from a shipped Makefile; 5.3.1/5.3.2 are autotools and differ only
# in configure_args (below).
build_system makefile  when=3.0.4
build_system autotools when=5.3.1
build_system autotools when=5.3.2

# Shared: grep (both configure/build scripts use it).
depends_on grep@2.4-musl
# 3.0.4: tcc + musl 1.1.24, seed make on PATH (no gmake dep).
depends_on tcc musl@1.1.24 when=3.0.4
# 5.3.1: gcc 9.5 + binutils 2.30. Modern sed/tar: 5.3.1's configure needs sed -E
# and its tarball is xz.
depends_on gcc-boot@9.5.0 binutils@2.30-musl gmake sed@4.9-musl tar@1.35-musl xz@5.2.5-musl \
    when=5.3.1
# 5.3.2: gcc 16 via compiler-wrapper, with the glibc sed/tar/xz build tools.
depends_on compiler-wrapper gmake sed@4.9 tar@1.35 xz@5.8.3 when=5.3.2

edit() {
    # 3.0.4 builds from the shipped files/Makefile; only copy it for that build.
    [ "$version" = 3.0.4 ] && cp "$package_dir/files/Makefile" ./Makefile
    # gawk's system()/getline/print-to-cmd execl a hardcoded "/bin/sh", which the
    # musl patch can't reach and the sandbox denies. Repoint at the store shell
    # (glibc's gen-sorted.awk does system("test -d ...") during the build).
    replace_bin_sh builtin.c io.c
}

# 5.3.1/5.3.2. Both disable loadable .so extensions (unused; for 5.3.1 they also
# can't link the non-PIC static musl libc.a) and NLS/mpfr/libsigsegv. They differ
# only in compiler/CFLAGS: 5.3.1 uses the gcc-9.5 bridge with CFLAGS=-O2 to drop
# the default -g (would leak the build cwd as comp_dir); 5.3.2 uses gcc 16.
configure_args() {
    local triple
    if [ "$version" = 5.3.1 ]; then
        triple=$(triple musl)
        printf '%s\n' "CC=$(prefix_of gcc-boot)/bin/gcc" CFLAGS=-O2
    else
        triple=$(triple gnu)
        printf '%s\n' CC=gcc
    fi
    printf '%s\n' MAKEINFO=true "--build=$triple" "--host=$triple" \
        --disable-nls --disable-mpfr --disable-extensions \
        --without-libsigsegv-prefix
}
