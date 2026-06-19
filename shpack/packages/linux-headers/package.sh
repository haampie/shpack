# SPDX-License-Identifier: MIT

description "Linux kernel uapi headers (asm/, asm-generic/, linux/, ...)," \
            "sanitized with 'make headers_install' -- no kernel compile"
homepage "https://www.kernel.org/"
license "GPL-2.0-only"

version 6.9.1 sha256=01b414ba98fd189ecd544435caf3860ae2a790e3ec48f5aa70fdf42dc4c5c04a \
    url=https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.9.1.tar.xz

build_system generic

# Built by the chain's GCC 4.7 (HOSTCC compiles scripts/basic/fixdep and
# scripts/unifdef). make = gmake (musl-linked, drives the jobserver).
depends_on gcc-boot@4.7-2013.11 gmake sed@4.9-musl xz@5.2.5-musl

install() {
    local karch
    # Linux ARCH uses its own arch names: aarch64 -> arm64 (selects the arm64
    # asm/ uapi), amd64 -> x86_64.
    case "$ARCH" in
        amd64)   karch=x86_64 ;;
        aarch64) karch=arm64 ;;
    esac
    # 'headers' runs the copy+unifdef pass (strips __KERNEL__ blocks,
    # __force/__user) into usr/include -- no .config needed, the stage is a fresh
    # tree. Uses `headers` + manual copy rather than `headers_install`.
    make headers ARCH="$karch" HOSTCC=gcc
    mkdir -p "$PREFIX/include"
    cp -r usr/include/. "$PREFIX/include/"
}
