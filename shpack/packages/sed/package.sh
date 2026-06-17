# SPDX-License-Identifier: MIT

description "GNU sed 4.9 -- a modern stream editor. The stage0 seed sed is" \
           "4.0.9 (2003), too old for 'sed -E' and other scripts the kernel" \
           "headers, glibc and gcc build machinery rely on."
homepage "https://www.gnu.org/software/sed/"
license "GPL-3.0-or-later"

version 4.9 sha256=6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181 \
    url=https://ftpmirror.gnu.org/sed/sed-4.9.tar.xz

build_system autotools

# Built by the chain's real GCC 4.7 against musl 1.1.24 (static, like the rest
# of the tool layer). Consumers (linux-headers, glibc, gcc 9+) put it ahead of
# the seed sed-4.0.9 via the dep PATH order.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake xz

configure_args() {
    local triple
    # config.guess cannot probe this environment (uname "unknown", no
    # /usr/bin/file), so pass an explicit triple, like the other tools.
    triple=$(triple musl unknown)
    printf '%s\n' \
        CC=gcc \
        --build="$triple" \
        --host="$triple" \
        --disable-nls
}
