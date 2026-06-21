# SPDX-License-Identifier: MIT

description "Mozilla CA certificate bundle (PEM), as published by the curl" \
            "project. Installed as etc/ssl/cert.pem for TLS clients that want a" \
            "trust store on disk. No compiled code -- just the .pem."
homepage "https://curl.se/docs/caextract.html"
license "MPL-2.0"

# A bare .pem, not an archive: builder.sh unpack() cp's it into the stage dir.
# The version is the bundle's release date.
version 2025-08-12 sha256=64dfd5b1026700e0a0a324964749da9adc69ae5e51e899bf16ff47d6fd0e9a5e \
    url=https://curl.se/ca/cacert-2025-08-12.pem

build_system generic

# No build step needs it, but every node declares its build shell (builder.sh).
depends_on dash

install() {
    mkdir -p "$PREFIX/etc/ssl"
    cp cacert-*.pem "$PREFIX/etc/ssl/cert.pem"
}
