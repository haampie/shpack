# SPDX-License-Identifier: MIT

description "Spack v1.1.0 -- the package manager, installed into the store and" \
            "wired to run on the shpack-built CPython with the shpack-built" \
            "clingo as its concretizer, so it never bootstraps prebuilt clingo." \
            "The 'builtin' package repo is overridden to the vendored" \
            "spack-packages, so 'spack spec' works offline."
homepage "https://spack.io/"
license "Apache-2.0 OR MIT"

version 1.1.0 sha256=518474f546e87723c43b80143d83a51c065a8d54333c8140da6f48bc7d9e50c1 \
    url=https://github.com/spack/spack/releases/download/v1.1.0/spack-1.1.0.tar.gz

build_system generic

# cpython runs it; clingo (on PYTHONPATH) is the concretizer so no bootstrap;
# spack-packages provides the 'builtin' recipe repo; gcc is the compiler Spack
# auto-detects from PATH so concretization has something to build against.
depends_on cpython clingo spack-packages gcc

install() {
    local py clingo_site pkgrepo dest gcc
    py=$(prefix_of cpython)
    gcc=$(prefix_of gcc)
    clingo_site=$(prefix_of clingo)/lib/python3.14/site-packages
    pkgrepo=$(prefix_of spack-packages)/repos/spack_repo/builtin
    dest=$PREFIX/lib/spack-1.1.0

    # Install the Spack tree (do_stage left us in spack-1.1.0/).
    mkdir -p "$dest"
    cp -a . "$dest/"

    # Override the 'builtin' repo (default is a git clone of spack-packages) with
    # the vendored local path. The string form of a repos.yaml entry is a local
    # repository path; this lives in Spack's instance scope ($spack/etc/spack),
    # which overrides the defaults scope.
    cat > "$dest/etc/spack/repos.yaml" <<EOF
repos:
  builtin: $pkgrepo
EOF

    # Launcher: our Python + clingo on PYTHONPATH so 'import clingo' succeeds and
    # Spack skips bootstrapping. SPACK_DISABLE_LOCAL_CONFIG keeps ~/.spack and
    # /etc/spack from interfering, so the run is hermetic against the store.
    mkdir -p "$PREFIX/bin"
    cat > "$PREFIX/bin/spack" <<EOF
#!$sh
export PATH=$gcc/bin:$py/bin:\$PATH
export PYTHONPATH=$clingo_site\${PYTHONPATH:+:\$PYTHONPATH}
export SPACK_DISABLE_LOCAL_CONFIG=true
exec $py/bin/python3 $dest/bin/spack "\$@"
EOF
    chmod 755 "$PREFIX/bin/spack"
}
