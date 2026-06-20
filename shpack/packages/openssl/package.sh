# SPDX-License-Identifier: MIT

description "OpenSSL 3.6.1 -- TLS/crypto library. Provides CPython's _ssl, which" \
            "Spack imports unconditionally (spack.util.web -> ssl), so it's" \
            "required even for offline 'spack spec'."
homepage "https://www.openssl.org/"
license "Apache-2.0"

version 3.6.1 sha256=b1bfedcd5b289ff22aee87c9d600f515767ebf45f77168cb6d64f231f518a82e \
    url=https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz

build_system generic

# perl drives Configure and the build generators; zlib-ng for compression.
# ca-certificates is the Mozilla bundle dropped into OPENSSLDIR (see install) so
# the default trust store works with no SSL_CERT_FILE.
depends_on compiler-wrapper perl zlib-ng gmake ca-certificates

install() {
    local m
    case "$ARCH" in amd64) m=x86_64 ;; aarch64) m=aarch64 ;; esac
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    export PATH="$(prefix_of perl)/bin:$PATH"

    # Explicit target ("linux-$m") so Configure never guesses via uname/config.
    # --libdir=lib keeps the libs in lib/ where the wrapper's -L looks; -Wl,-rpath
    # lets them resolve from the store with no LD_LIBRARY_PATH.
    "$(prefix_of perl)/bin/perl" ./Configure "linux-$m" \
        --prefix="$PREFIX" \
        --openssldir="$PREFIX/ssl" \
        --libdir=lib \
        shared zlib \
        "-Wl,-rpath,$PREFIX/lib"

    make $makejobs
    # install_sw: libs + headers + tool, skipping man pages (need a doc toolchain).
    make install_sw

    # Drop the bundle at OPENSSLDIR/cert.pem (X509_get_default_cert_file()) so TLS
    # clients verify without SSL_CERT_FILE. install_sw skips the ssl/ dir, so
    # create it first.
    mkdir -p "$PREFIX/ssl"
    cp "$(prefix_of ca-certificates)/etc/ssl/cert.pem" "$PREFIX/ssl/cert.pem"
}
