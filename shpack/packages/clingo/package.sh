# SPDX-License-Identifier: MIT

description "clingo (potassco) @spack branch -- the ASP grounder/solver Spack" \
            "uses as its concretizer. Built with the CPython C-API bindings (no" \
            "cffi/libffi), the same configuration as Spack's clingo-bootstrap@spack."
homepage "https://potassco.org/clingo/"
license "MIT"

# The @spack git commit, which builds pyclingo without cffi. GitHub archives omit
# submodule contents, so clasp and its nested libpotassco come as resources,
# relocated in edit().
version 5.5.0-spack \
    sha256=7818eef2296c17ad38a57a77f7925c8df41744c4e736ab81042df95c1330f43b \
    url=https://github.com/potassco/clingo/archive/2a025667090d71b2c9dce60fe924feb6bde8f667.tar.gz \
    fname=clingo-2a025667.tar.gz
resource sha256=ab2ac6601292619f94831065ee5c009f3168e14be52a65df7b9abdc20a1fc33f \
    url=https://github.com/potassco/clasp/archive/b089aa1509511ab403c0b9abd0d13eb9e873af44.tar.gz \
    fname=clasp-b089aa15.tar.gz
resource sha256=41eb8b7d87ecea48392de4ada455cda179cbd62fd63496355dea87e1e44b599f \
    url=https://github.com/potassco/libpotassco/archive/2f9fb7ca2c202f1b47643aa414054f2f4f9c1821.tar.gz \
    fname=libpotassco-2f9fb7ca.tar.gz

build_system generic

# bison/re2c generate the gringo parser/lexer; cmake drives the build; cpython
# provides headers + libpython for the bindings.
depends_on compiler-wrapper cpython re2c cmake bison
depends_on dash

edit() {
    local src
    # do_stage cd'd into whichever flat dir sorted first; work from stage_dir.
    cd "$stage_dir"
    src=$(set -- clingo-*/; printf '%s' "${1%/}")

    # Reconstruct the submodule tree the @spack commit pins.
    rm -rf "$src/clasp"
    mv clasp-*/ "$src/clasp"
    rm -rf "$src/clasp/libpotassco"
    mv libpotassco-*/ "$src/clasp/libpotassco"

    cd "$src"

    # Drop PyEval_ThreadsInitialized/PyEval_InitThreads (removed in Python 3.9).
    sed -i 's/if (!PyEval_ThreadsInitialized()) { PyEval_InitThreads(); }//' \
        libpyclingo/pyclingo.cc
    # Doxygen can't be disabled via a -D; neutralize the lookup (as Spack does).
    sed -i 's/find_package(Doxygen)/message("Doxygen disabled")/' \
        clasp/CMakeLists.txt clasp/libpotassco/CMakeLists.txt
}

install() {
    local py suffix
    py=$(prefix_of cpython)

    export CC=$(prefix_of compiler-wrapper)/bin/cc
    export CXX=$(prefix_of compiler-wrapper)/bin/c++
    export PATH="$(prefix_of cmake)/bin:$(prefix_of re2c)/bin:$(prefix_of bison)/bin:$PATH"

    # Pass PYCLINGO_INSTALL_DIR + PYCLINGO_SUFFIX (EXT_SUFFIX) so cmake never falls
    # back to cmake/python-site.py, which imports distutils (gone in Python 3.12+).
    suffix=$("$py/bin/python3" -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")

    mkdir -p build
    cd build
    # PY_SHARED=OFF: a self-contained _clingo*.so in clingo's own site-packages.
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCLINGO_BUILD_WITH_PYTHON=ON \
        -DCLINGO_REQUIRE_PYTHON=ON \
        -DCLINGO_BUILD_PY_SHARED=OFF \
        -DCLINGO_BUILD_APPS=OFF \
        -DCLINGO_BUILD_TESTS=OFF \
        -DCLASP_BUILD_WITH_THREADS=ON \
        -DPYCLINGO_USER_INSTALL=OFF \
        -DPYCLINGO_USE_INSTALL_PREFIX=ON \
        "-DPYCLINGO_INSTALL_DIR=$PREFIX/lib/python3.14/site-packages" \
        "-DPYCLINGO_SUFFIX=$suffix" \
        "-DPython_ROOT_DIR=$py" \
        "-DPython_EXECUTABLE=$py/bin/python3" \
        "-DPython3_EXECUTABLE=$py/bin/python3"
    make $makejobs
    make install
}
