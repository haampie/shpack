# SPDX-License-Identifier: MIT

description "musl libc 1.2.5 -- modern, pristine static libc, rebuilt by the" \
            "chain's real GCC 4.7 (sysroot for the gcc 9.5 bridge)"
homepage "https://musl.libc.org/"
license "MIT"

# musl 1.1.24 stays the kaem-phase external (built by tcc, used by gcc 4.7);
# this recipe adds the modern 1.2.5, built cleanly by gcc 4.7. gcc 4.7 pins
# musl@1.1.24 so adding 1.2.5 does not upgrade its proven build.
version 1.2.5 sha256=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4 \
    url=https://www.musl-libc.org/releases/musl-1.2.5.tar.gz

build_system generic

depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake linux-headers

setup_build_environment() {
    # musl builds -nostdinc but still needs the kernel uapi (asm/ syscall and
    # signal numbers, some linux/ headers); gcc 4.7 honors C_INCLUDE_PATH.
    export C_INCLUDE_PATH="$(prefix_of linux-headers)/include"
}

edit() {
    # system()/popen() execv a hardcoded "/bin/sh"; the sandbox has no host one,
    # so repoint at the store shell. Absolute path is fine: bootstrap-only libc,
    # never relocated. (The kaem-phase musl 1.1.24 carries the same change via
    # @STORE@ subst; the deliverable glibc is left alone.)
    replace_bin_sh src/process/system.c src/stdio/popen.c
}

install() {
    local triple ar ranlib
    triple=$(triple musl)
    ar=$(prefix_of binutils)/bin/ar
    ranlib=$(prefix_of binutils)/bin/ranlib

    # "./configure" (not "configure"): musl derives srcdir from ${0%/configure},
    # which is still "." when invoked as `$sh ./configure`.
    "$sh" ./configure \
        CC=gcc \
        --target="$triple" \
        --prefix="$PREFIX" \
        --syslibdir="$PREFIX/lib" \
        --disable-shared

    # gcc (…-unknown-linux-musl) and binutils (…-linux-musl) triples differ, so
    # pin AR/RANLIB rather than relying on musl's CROSS_COMPILE-derived names.
    make $makejobs "AR=$ar" "RANLIB=$ranlib"
    make install "AR=$ar" "RANLIB=$ranlib"

    test -f "$PREFIX/lib/libc.a" || die "musl: missing lib/libc.a"
    test -f "$PREFIX/lib/crt1.o" || die "musl: missing lib/crt1.o"

    # Merge the kernel uapi headers into the sysroot so any compile against it
    # finds linux/*, asm/* -- C_INCLUDE_PATH only covers C, but libstdc++'s
    # random.cc (C++) needs <linux/types.h>. A real toolchain sysroot carries
    # both libc and kernel headers; disjoint dirs, so no clash with musl's.
    cp -r "$(prefix_of linux-headers)/include/." "$PREFIX/include/"
}
