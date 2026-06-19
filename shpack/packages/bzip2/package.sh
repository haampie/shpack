# SPDX-License-Identifier: MIT

description "bzip2 1.0.8 -- a block-sorting file compressor: the bzip2/bunzip2" \
            "CLI plus the shared libbz2. Built at the gcc-16 layer."
homepage "https://sourceware.org/bzip2/"
license "bzip2-1.0.6"

version 1.0.8 sha256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269 \
    url=https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz

build_system generic

# compiler-wrapper pulls in gcc 16 + glibc loader/rpath. Pure-make build (two
# hand-written Makefiles), no configure, no /bin/sh hardcoding.
depends_on compiler-wrapper gmake

edit() {
    # Both Makefiles hardcode CC=gcc; repoint at the wrapper gcc (= gcc 16).
    local cc
    cc=$(prefix_of compiler-wrapper)/bin/gcc
    sed -i "s|^CC=gcc|CC=$cc|" Makefile Makefile-libbz2_so
}

install() {
    # Shared lib first: Makefile-libbz2_so builds libbz2.so.1.0.8 + bzip2-shared.
    make -f Makefile-libbz2_so "SHELL=$sh" $makejobs
    # Then the static lib, the CLI, and man pages; install lays out bin/lib/include.
    make "SHELL=$sh" $makejobs
    make "SHELL=$sh" PREFIX="$PREFIX" install

    # Overlay the dynamic build: the shared bzip2 over the static one, the
    # versioned .so, and the classic symlink chain.
    command install -m 755 bzip2-shared "$PREFIX/bin/bzip2"
    command install -m 755 libbz2.so.1.0.8 "$PREFIX/lib/libbz2.so.1.0.8"
    ( cd "$PREFIX/lib" &&
      for l in libbz2.so libbz2.so.1 libbz2.so.1.0; do ln -sf libbz2.so.1.0.8 "$l"; done )
    # bunzip2/bzcat are copies of the static bzip2; repoint them at the new one.
    ( cd "$PREFIX/bin" && rm -f bunzip2 bzcat && ln -s bzip2 bunzip2 && ln -s bzip2 bzcat )
}
