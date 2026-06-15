# SPDX-License-Identifier: MIT

description "Thin wrapper making crippled gcc-16-boot0 target glibc 2.43:" \
            "gcc/g++ scripts that inject glibc's startfiles, loader and rpath." \
            "Sourceless shim."
homepage "https://gcc.gnu.org/"
license "GPL-3.0-or-later"

# Sourceless: no url/sha256 -> nothing to fetch, builds in the stage dir.
version 16.1.0

build_system generic

depends_on gcc-boot@16.1.0 glibc binutils@2.46.0

install() {
    local gcc glibc binutils ld_so prog real tool
    gcc=$(prefix_of gcc-boot)
    glibc=$(prefix_of glibc)
    binutils=$(prefix_of binutils)

    case "$ARCH" in
        amd64)   ld_so="$glibc/lib/ld-linux-x86-64.so.2" ;;
        aarch64) ld_so="$glibc/lib/ld-linux-aarch64.so.1" ;;
    esac

    mkdir -p "$PREFIX/bin"

    # gcc/g++ wrappers: -B finds crt1.o/crti.o/crtn.o from the new libc;
    # -dynamic-linker points executables at glibc's loader; -rpath finds
    # libc.so.6 at run time.
    for prog in gcc g++; do
        real="$gcc/bin/$prog"
        {
            printf '#!/bin/sh\n'
            printf 'exec %s -B%s/lib -Wl,-dynamic-linker -Wl,%s -Wl,-rpath -Wl,%s/lib "$@"\n' \
                "$real" "$glibc" "$ld_so" "$glibc"
        } > "$PREFIX/bin/$prog"
        chmod 755 "$PREFIX/bin/$prog"
    done

    # Plain-named binutils tools so configure/make find as/ld/ar etc.
    for tool in ar as ld nm objcopy objdump ranlib readelf strip; do
        [ -e "$binutils/bin/$tool" ] || continue
        [ -e "$PREFIX/bin/$tool" ] || ln -s "$binutils/bin/$tool" "$PREFIX/bin/$tool"
    done
}
