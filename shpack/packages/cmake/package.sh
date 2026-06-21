# SPDX-License-Identifier: MIT

description "CMake 3.31.11 -- build-system generator. Bootstrapped from source" \
            "against store libraries (curl/openssl/libarchive/...); only the" \
            "bundled cppdap (cmake-only build) stays vendored. No ncurses dialog."
homepage "https://cmake.org/"
license "BSD-3-Clause"

version 3.31.11 sha256=c0a3b3f2912b2166f522d5010ffb6029d8454ee635f5ad7a3247e0be7f9a15c9 \
    url=https://github.com/Kitware/CMake/releases/download/v3.31.11/cmake-3.31.11.tar.gz

build_system generic

depends_on compiler-wrapper gmake openssl curl \
           zlib-ng expat bzip2 xz zstd nghttp2 \
           libarchive libuv librhash jsoncpp

edit() {
    # cmake hardcodes /bin/sh (the SHELL of generated makefiles, and its
    # cmExecProgramCommand); the sandbox has none.
    replace_bin_sh Source/cmLocalUnixMakefileGenerator3.cxx Source/cmExecProgramCommand.cxx
}

install() {
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    export CXX=$(prefix_of compiler-wrapper)/bin/g++
    # Vendored cppdap needs _GNU_SOURCE under GCC 16.
    export CFLAGS="-D_GNU_SOURCE"
    export CXXFLAGS="-D_GNU_SOURCE"
    # find_package() searches CMAKE_PREFIX_PATH, not the wrapper's -I/-L.
    export CMAKE_PREFIX_PATH="$(prefix_of openssl):$(prefix_of curl):$(prefix_of zlib-ng):$(prefix_of expat):$(prefix_of bzip2):$(prefix_of xz):$(prefix_of zstd):$(prefix_of nghttp2):$(prefix_of libarchive):$(prefix_of libuv):$(prefix_of librhash):$(prefix_of jsoncpp)"

    # Private deps of static libarchive.a; FindLibArchive links only the .a.
    local archive_private="-lcrypto -llzma -lzstd -lbz2 -lz"
    # --bootstrap-system-*: else the wrapper's -I leaks system headers into the
    #   bundled libs the mini-cmake compiles.
    # RPATH_USE_LINK_PATH: survive CMake's install-time RPATH rewrite.
    "$sh" ./bootstrap \
        --prefix="$PREFIX" \
        --no-qt-gui \
        --system-libs \
        --system-curl \
        --no-system-cppdap \
        --bootstrap-system-libuv \
        --bootstrap-system-jsoncpp \
        --bootstrap-system-librhash \
        -- \
        -DCMAKE_USE_OPENSSL=ON \
        -DBUILD_CursesDialog=OFF \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DCMAKE_C_STANDARD_LIBRARIES="$archive_private" \
        -DCMAKE_CXX_STANDARD_LIBRARIES="$archive_private"
    make $makejobs
    make install
}
