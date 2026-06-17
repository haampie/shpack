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

install() {
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    export CXX=$(prefix_of compiler-wrapper)/bin/g++
    # cmake's bundled cmlibuv calls glibc GNU extensions (accept4, dup3, pipe2,
    # sched_getaffinity, CPU_*) that the headers only expose under _GNU_SOURCE.
    # The bootstrap phase doesn't define it, and GCC 16 makes the resulting
    # implicit declarations a hard error -- so set it for the whole build.
    export CFLAGS="-D_GNU_SOURCE"
    export CXXFLAGS="-D_GNU_SOURCE"

    # cmake's generated Unix Makefiles hardcode `SHELL = /bin/sh`, and cmake
    # unsets MAKEFLAGS for its internal try_compile probes, so the builder's
    # SHELL=$sh override can't reach those sub-makes -- and the sandbox has no
    # host /bin/sh, so every probe dies with "/bin/sh: Permission denied".
    # Repoint cmake's baked shell at the store shell. This patches the source, so
    # it fixes the bootstrap cmake, the installed cmake, and thus clingo's build.
    sed -i "s|\"SHELL = /bin/sh|\"SHELL = $sh|" Source/cmLocalUnixMakefileGenerator3.cxx
    sed -i "s|\"/bin/sh\"|\"$sh\"|" Source/cmExecProgramCommand.cxx

    # ./bootstrap builds a minimal cmake with make, then the full cmake. Bundled
    # third-party libs keep this self-contained; OpenSSL (no perl/openssl in the
    # store) and the curses dialog are turned off. No --parallel: the inner make
    # inherits the dag.mk jobserver via MAKEFLAGS, so it shares the global -jN
    # rather than spawning its own -j$JOBS on top of it (JOBS x JOBS).
    "$sh" ./bootstrap \
        --prefix="$PREFIX" \
        --no-qt-gui \
        -- \
        -DCMAKE_USE_OPENSSL=OFF \
        -DBUILD_CursesDialog=OFF
    make $makejobs
    make install
}
