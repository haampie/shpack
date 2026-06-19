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
# auto-detects from PATH so concretization has something to build against. The
# rest are the gcc-16/glibc userland Spack otherwise assumes from the host
# (coreutils/grep/sed/gawk + the archiver/VCS tools); they go on the launcher
# PATH so Spack fetches, unpacks and runs build scripts with this toolchain. The
# glibc builds of tar/xz/grep/sed/gawk are pinned (the -musl ones are bootstrap).
depends_on cpython clingo spack-packages gcc
depends_on coreutils grep@3.11 sed@4.9 gawk@5.3.2
depends_on tar@1.35 xz@5.8.3 bzip2@1.0.8 gzip patch unzip zstd git

install() {
    local py clingo_site pkgrepo dest gcc tools t
    py=$(prefix_of cpython)
    gcc=$(prefix_of gcc)
    clingo_site=$(prefix_of clingo)/lib/python3.14/site-packages
    pkgrepo=$(prefix_of spack-packages)/repos/spack_repo/builtin
    dest=$PREFIX/lib/spack-1.1.0

    # Colon-terminated bin/ list of the gcc-16-built userland, for the launcher
    # PATH so Spack uses these and not whatever the host happens to have.
    tools=
    for t in coreutils grep sed gawk tar xz bzip2 gzip patch unzip zstd git; do
        tools=$tools$(prefix_of "$t")/bin:
    done

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
export PATH=$gcc/bin:$tools$py/bin:\$PATH
export PYTHONPATH=$clingo_site\${PYTHONPATH:+:\$PYTHONPATH}
export SPACK_DISABLE_LOCAL_CONFIG=true
exec $py/bin/python3 $dest/bin/spack "\$@"
EOF
    chmod 755 "$PREFIX/bin/spack"
}
