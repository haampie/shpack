# SPDX-License-Identifier: MIT

description "OpenSSL 3.6.1 -- TLS/crypto library. Provides CPython's _ssl, which" \
            "Spack imports unconditionally (spack.util.web -> ssl), so it's" \
            "required even for offline 'spack spec'."
homepage "https://www.openssl.org/"
license "Apache-2.0"

version 3.6.1 sha256=b1bfedcd5b289ff22aee87c9d600f515767ebf45f77168cb6d64f231f518a82e \
    url=https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz

build_system generic

# perl drives Configure and the build generators; zlib for the (dynamically
# loaded) compression support. compiler-wrapper supplies gcc + zlib -I/-L/-rpath.
depends_on compiler-wrapper perl zlib gmake

install() {
    local m
    case "$ARCH" in amd64) m=x86_64 ;; aarch64) m=aarch64 ;; esac
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    export PATH="$(prefix_of perl)/bin:$PATH"

    # Explicit target ("linux-$m") so Configure never guesses via uname/config.
    # --libdir=lib keeps libssl/libcrypto in lib/ (not lib64/) where the wrapper's
    # -L and CPython's --with-openssl probe look. The -Wl,-rpath makes the two
    # libs and their consumers resolve each other from the store with no
    # LD_LIBRARY_PATH. zlib enables the optional compression backend.
    "$(prefix_of perl)/bin/perl" ./Configure "linux-$m" \
        --prefix="$PREFIX" \
        --openssldir="$PREFIX/ssl" \
        --libdir=lib \
        shared zlib \
        "-Wl,-rpath,$PREFIX/lib"

    make $makejobs
    # install_sw: libraries + headers + the openssl tool, skipping the man pages
    # (which need pod2man and a doc toolchain we don't ship).
    make install_sw
}
