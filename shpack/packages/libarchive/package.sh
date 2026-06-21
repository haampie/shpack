# SPDX-License-Identifier: MIT

description "libarchive 3.8.7 -- multi-format archive/compression library. Static" \
            "libarchive only; zlib/bzip2/xz/zstd/openssl filters, no CLI tools."
homepage "https://www.libarchive.org/"
license "BSD-2-Clause"

version 3.8.7 sha256=4b787cca6697a95c7725e45293c973c208cbdc71ae2279f30ef09f52472b9166 \
    url=https://github.com/libarchive/libarchive/releases/download/v3.8.7/libarchive-3.8.7.tar.gz

build_system autotools

depends_on compiler-wrapper gmake zlib-ng bzip2 xz zstd openssl
depends_on dash

configure_args() {
    # zlib/bzip2/lzma/zstd/openssl filters on, everything else off, no tools.
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        --build="$t" \
        --host="$t" \
        --enable-static \
        --disable-shared \
        --disable-bsdtar \
        --disable-bsdcpio \
        --disable-bsdcat \
        --disable-bsdunzip \
        --disable-acl \
        --disable-xattr \
        --with-zlib \
        --with-bz2lib \
        --with-lzma \
        --with-zstd \
        --with-openssl \
        --without-xml2 \
        --without-expat \
        --without-lz4 \
        --without-lzo2 \
        --without-nettle \
        --without-mbedtls \
        --without-iconv
}
