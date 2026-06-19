# SPDX-License-Identifier: MIT

description "Spack v1.2.0 (releases/v1.2 snapshot) -- the package manager," \
            "installed into the store and" \
            "wired to run on the shpack-built CPython with the shpack-built" \
            "clingo as its concretizer, so it never bootstraps prebuilt clingo." \
            "The 'builtin' package repo is overridden to the vendored" \
            "spack-packages, so 'spack spec' works offline."
homepage "https://spack.io/"
license "Apache-2.0 OR MIT"

# releases/v1.2 head (commit 3d24b94, 2026-06-11); __version__ is 1.2.0.dev0.
# GitHub commit archive -> stable checksum.
version 1.2.0 sha256=3efca6d5892930ee998a81c5917747765f107ffb0f9de9a03209159726df3b8f \
    url=https://github.com/spack/spack/archive/3d24b94ef3d15a4864794f98807a7fcc17b83f48.tar.gz \
    fname=spack-1.2.0.tar.gz

build_system generic

# cpython runs it; clingo (on PYTHONPATH) is the concretizer; spack-packages is
# the 'builtin' repo; gcc is the compiler Spack auto-detects. The rest are the
# gcc-16/glibc userland (Spack otherwise assumes the host's), put on the launcher
# PATH. The glibc tar/xz/grep/sed/gawk are pinned (the -musl ones are bootstrap).
depends_on cpython clingo spack-packages gcc
depends_on coreutils grep@3.11 sed@4.9 gawk@5.3.2
depends_on tar@1.35 xz@5.8.3 bzip2@1.0.8 gzip patch unzip zstd git

install() {
    local py clingo_site pkgrepo dest gcc tools t
    py=$(prefix_of cpython)
    gcc=$(prefix_of gcc)
    clingo_site=$(prefix_of clingo)/lib/python3.14/site-packages
    pkgrepo=$(prefix_of spack-packages)/repos/spack_repo/builtin
    dest=$PREFIX/lib/spack-$version

    # Colon-terminated bin/ list of the gcc-16-built userland for the launcher PATH.
    tools=
    for t in coreutils grep sed gawk tar xz bzip2 gzip patch unzip zstd git; do
        tools=$tools$(prefix_of "$t")/bin:
    done

    mkdir -p "$dest"
    cp -a . "$dest/"

    # Override the 'builtin' repo (default: a git clone) with the vendored path.
    # The instance scope ($spack/etc/spack) overrides the defaults scope.
    cat > "$dest/etc/spack/repos.yaml" <<EOF
repos:
  builtin: $pkgrepo
EOF

    # Launcher: our Python + clingo on PYTHONPATH so Spack skips bootstrapping.
    # SPACK_DISABLE_LOCAL_CONFIG is deliberately unset -- it would drop every local
    # scope at once, making SPACK_USER_CONFIG_PATH a no-op. The tradeoff is the run
    # isn't hermetic against host Spack config, which is the price of overridability.
    mkdir -p "$PREFIX/bin"
    cat > "$PREFIX/bin/spack" <<EOF
#!$sh
export PATH=$gcc/bin:$tools$py/bin:\$PATH
export PYTHONPATH=$clingo_site\${PYTHONPATH:+:\$PYTHONPATH}
exec $py/bin/python3 $dest/bin/spack "\$@"
EOF
    chmod 755 "$PREFIX/bin/spack"
}
