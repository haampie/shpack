# SPDX-License-Identifier: MIT

description "XZ Utils 5.2.5 -- real liblzma xz/unxz. Replaces the stage0" \
            "mescc-tools-extra unxz (a plain ~2400-line LZMA2 decoder built by" \
            "the unoptimized M2-Planet chain) for the big .tar.xz extractions" \
            "(linux 144M, gcc 102M/72M, glibc 20M), which sit on the critical" \
            "path right before each package configures."
homepage "https://tukaani.org/xz/"
license "0BSD AND LGPL-2.1-or-later AND GPL-2.0-or-later"

# 5.2.5 (2021): pre-dates the 5.6.0/5.6.1 backdoor, portable C99, builds clean
# with the chain's GCC 4.7 on musl. Shipped as .tar.gz (extracted by the seed
# gzip) so xz never has to decompress its own source with the slow stage0 unxz.
version 5.2.5 sha256=f6f4910fd033078738bd82bfba4f49219d03b17eb0794eb91efbae419f4aba10 \
    url=https://downloads.sourceforge.net/project/lzmautils/xz-5.2.5.tar.gz

build_system autotools

# Built by the chain's real GCC 4.7 against musl 1.1.24 (static, like sed/tar).
# Every big .tar.xz is unpacked after GCC 4.7 is ready, so an -O2 xz is available
# before the first heavy extraction. Consumers put xz/bin/unxz ahead of the seed
# unxz via the dep PATH order (compose_path), so builder.sh unpack() picks it up.
depends_on gcc-boot@4.7-2013.11 binutils@2.30-musl gmake

configure_args() {
    # config.guess cannot probe this environment (uname "unknown", no
    # /usr/bin/file), so pass an explicit triple, like the other tools.
    triple=$(triple musl unknown)
    # Static-only liblzma (no rpath, matches the tool layer); we only need the
    # xz/unxz CLI. Drop NLS (no gettext) and the shell wrappers/docs we never use.
    printf '%s\n' \
        CC=gcc \
        --build="$triple" \
        --host="$triple" \
        --disable-shared \
        --enable-static \
        --disable-nls \
        --disable-doc \
        --disable-scripts \
        --disable-symbol-versions
}
