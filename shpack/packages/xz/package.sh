# SPDX-License-Identifier: MIT

description "XZ Utils -- real liblzma xz/unxz. Two builds from one recipe:" \
            "5.2.5-musl is the static musl xz the bootstrap uses for the big" \
            ".tar.xz extractions (linux 144M, gcc 102M/72M, glibc 20M) before" \
            "the final toolchain exists; 5.8.3 is the glibc xz built with the" \
            "final gcc 16, the user-facing (de)compressor."
homepage "https://tukaani.org/xz/"
license "0BSD AND LGPL-2.1-or-later AND GPL-2.0-or-later"

# 5.8.3 (2025): current stable, well clear of the 5.6.0/5.6.1 backdoor. Built
# with gcc 16 against glibc, the modern user-facing xz.
version 5.8.3 sha256=33bf69c0d6c698e83a68f77e6c1f465778e418ca0b3d59860d3ab446f4ac99a6 \
    url=https://github.com/tukaani-project/xz/releases/download/v5.8.3/xz-5.8.3.tar.bz2
# 5.2.5-musl (2021): pre-dates the backdoor, portable C99, builds clean with the
# chain's GCC 4.7 on musl. Shipped as .tar.gz (extracted by the seed gzip) so xz
# never has to decompress its own source with the slow stage0 unxz.
version 5.2.5-musl sha256=f6f4910fd033078738bd82bfba4f49219d03b17eb0794eb91efbae419f4aba10 \
    url=https://downloads.sourceforge.net/project/lzmautils/xz-5.2.5.tar.gz

build_system autotools

# 5.2.5-musl: the chain's real GCC 4.7 against musl 1.1.24 (static, like sed/tar).
# Consumers put xz/bin/unxz ahead of the seed unxz via the dep PATH order
# (compose_path), so builder.sh unpack() picks it up. 5.8.3: the glibc xz, built
# with the final gcc 16 via compiler-wrapper.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake when=5.2.5-musl
depends_on compiler-wrapper gmake when=5.8.3

configure_args() {
    local triple
    # config.guess cannot probe this environment (uname "unknown", no
    # /usr/bin/file), so pass an explicit triple; it is the only common-flag diff.
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
    # Delta: the musl build is static-only liblzma + just the CLI (no rpath,
    # matches the tool layer; drop scripts/symbol-versions), and gcc-4.7's -g
    # would leak the build cwd as comp_dir so CFLAGS=-O2 drops it. The gcc 16
    # build keeps the shared liblzma (rpath injected) and the default -g.
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
