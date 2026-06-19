# SPDX-License-Identifier: MIT

description "XZ Utils -- real liblzma xz/unxz. Two builds from one recipe:" \
            "5.2.5-musl is the static musl xz the bootstrap uses for the big" \
            ".tar.xz extractions (linux 144M, gcc 102M/72M, glibc 20M) before" \
            "the final toolchain exists; 5.8.3 is the glibc xz built with the" \
            "final gcc 16, the user-facing (de)compressor."
homepage "https://tukaani.org/xz/"
license "0BSD AND LGPL-2.1-or-later AND GPL-2.0-or-later"

# 5.8.3 (2025): current stable, clear of the 5.6.0/5.6.1 backdoor; the glibc xz.
version 5.8.3 sha256=33bf69c0d6c698e83a68f77e6c1f465778e418ca0b3d59860d3ab446f4ac99a6 \
    url=https://github.com/tukaani-project/xz/releases/download/v5.8.3/xz-5.8.3.tar.bz2
# 5.2.5-musl (2021): pre-dates the backdoor, builds clean with GCC 4.7 on musl.
# Shipped as .tar.gz (seed gzip) so xz never decompresses its own source.
version 5.2.5-musl sha256=f6f4910fd033078738bd82bfba4f49219d03b17eb0794eb91efbae419f4aba10 \
    url=https://downloads.sourceforge.net/project/lzmautils/xz-5.2.5.tar.gz

build_system autotools

# 5.2.5-musl: GCC 4.7 against musl 1.1.24 (static). 5.8.3: the glibc xz, built
# with the final gcc 16 via compiler-wrapper.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake when=5.2.5-musl
depends_on compiler-wrapper gmake when=5.8.3

configure_args() {
    local triple
    # Explicit triple (no config.guess); the only common-flag diff.
    case "$version" in
        5.2.5-musl) triple=$(triple musl unknown) ;;
        5.8.3)      triple=$(triple gnu) ;;
    esac
    printf '%s\n' \
        CC=gcc \
        --build="$triple" \
        --host="$triple" \
        --disable-nls \
        --disable-doc
    # musl build: static-only liblzma + CLI (drop scripts/symbol-versions), and
    # CFLAGS=-O2 drops gcc-4.7's -g (would leak the build cwd as comp_dir). The
    # gcc 16 build keeps the shared liblzma and the default -g.
    case "$version" in
        5.2.5-musl)
            printf '%s\n' \
                CFLAGS=-O2 \
                --disable-shared \
                --enable-static \
                --disable-scripts \
                --disable-symbol-versions
            ;;
    esac
}
