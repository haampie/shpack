# SPDX-License-Identifier: MIT

description "CMake 3.31.11 -- build-system generator. Build dependency of" \
            "clingo. Bootstrapped from source with its bundled libraries" \
            "(curl/zlib/expat/...), no system OpenSSL or ncurses dialog."
homepage "https://cmake.org/"
license "BSD-3-Clause"

version 3.31.11 sha256=c0a3b3f2912b2166f522d5010ffb6029d8454ee635f5ad7a3247e0be7f9a15c9 \
    url=https://github.com/Kitware/CMake/releases/download/v3.31.11/cmake-3.31.11.tar.gz

build_system generic

depends_on compiler-wrapper gmake

edit() {
    # cmake bakes `SHELL = /bin/sh` into generated Makefiles and unsets MAKEFLAGS
    # for try_compile probes, so SHELL=$sh can't reach them; the sandbox has no
    # /bin/sh. Patch the baked shell at the source so installed cmake inherits it.
    sed -i "s|\"SHELL = /bin/sh|\"SHELL = $sh|" Source/cmLocalUnixMakefileGenerator3.cxx
    sed -i "s|\"/bin/sh\"|\"$sh\"|" Source/cmExecProgramCommand.cxx
}

install() {
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    export CXX=$(prefix_of compiler-wrapper)/bin/g++
    # Bundled cmlibuv calls glibc GNU extensions (accept4, dup3, pipe2, CPU_*)
    # exposed only under _GNU_SOURCE; the bootstrap doesn't set it and GCC 16
    # makes the resulting implicit declarations a hard error.
    export CFLAGS="-D_GNU_SOURCE"
    export CXXFLAGS="-D_GNU_SOURCE"

    # Self-contained via bundled libs; OpenSSL and the curses dialog turned off.
    # No --parallel: the inner make inherits the dag.mk jobserver via MAKEFLAGS,
    # so it shares the global -jN instead of spawning its own -j$JOBS on top.
    "$sh" ./bootstrap \
        --prefix="$PREFIX" \
        --no-qt-gui \
        -- \
        -DCMAKE_USE_OPENSSL=OFF \
        -DBUILD_CursesDialog=OFF
    make $makejobs
    make install
}
