# SPDX-License-Identifier: MIT

description "OpenSSL 3.6.1 -- TLS/crypto library. Provides CPython's _ssl, which" \
            "Spack imports unconditionally (spack.util.web -> ssl), so it's" \
            "required even for offline 'spack spec'."
homepage "https://www.openssl.org/"
license "Apache-2.0"

version 3.6.1 sha256=b1bfedcd5b289ff22aee87c9d600f515767ebf45f77168cb6d64f231f518a82e \
    url=https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz

build_system generic

# perl drives Configure and the build generators; zlib-ng (drop-in zlib) for the
# (dynamically loaded) compression support. compiler-wrapper supplies gcc + the
# zlib -I/-L/-rpath. ca-certificates is the Mozilla bundle we drop into OPENSSLDIR
# (see install) so the compiled-in default trust store works with no SSL_CERT_FILE.
depends_on compiler-wrapper perl zlib-ng gmake ca-certificates

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

    # Drop the Mozilla bundle at OPENSSLDIR/cert.pem -- the path baked in as
    # X509_get_default_cert_file(). install_sw creates ssl/ but no cert.pem, so
    # without this every TLS client on this libcrypto (CPython's _ssl, the
    # openssl tool) fails verification unless SSL_CERT_FILE is set. Copying it
    # here makes the default trust store work with no env var. install_sw skips
    # the ssl/ config dir (that is install_ssldirs), so create it first.
    mkdir -p "$PREFIX/ssl"
    cp "$(prefix_of ca-certificates)/etc/ssl/cert.pem" "$PREFIX/ssl/cert.pem"
}
