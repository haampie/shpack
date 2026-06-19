# SPDX-License-Identifier: MIT

description "GNU sed 4.9 -- a modern stream editor. The stage0 seed sed is" \
           "4.0.9 (2003), too old for 'sed -E' and other scripts the kernel" \
           "headers, glibc and gcc build machinery rely on. Two builds from one" \
           "recipe: 4.9-musl is the static musl sed the bootstrap chain uses;" \
           "4.9 is the glibc sed built with the final gcc 16, the user-facing one."
homepage "https://www.gnu.org/software/sed/"
license "GPL-3.0-or-later"

version 4.9 sha256=6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181 \
    url=https://ftpmirror.gnu.org/sed/sed-4.9.tar.xz
version 4.9-musl sha256=6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181 \
    url=https://ftpmirror.gnu.org/sed/sed-4.9.tar.xz

build_system autotools

# 4.9-musl: GCC 4.7 against musl 1.1.24 (static). 4.9: the glibc sed, built with
# the final gcc 16 via compiler-wrapper. Each pulls the matching xz for its source.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake xz@5.2.5-musl when=4.9-musl
depends_on compiler-wrapper gmake xz@5.8.3 when=4.9

configure_args() {
    local triple
    # Explicit triple (no config.guess); the only common-flag diff.
    case "$version" in
        4.9-musl) triple=$(triple musl unknown) ;;
        4.9)      triple=$(triple gnu) ;;
    esac
    printf '%s\n' \
        CC=gcc \
        --build="$triple" \
        --host="$triple" \
        --disable-nls
    # gcc 4.7 has no -ffile-prefix-map, so CFLAGS=-O2 drops the default -g (would
    # leak the build cwd as comp_dir). gcc 16's -g is reproducible.
    case "$version" in 4.9-musl) printf '%s\n' CFLAGS=-O2 ;; esac
}
