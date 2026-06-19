# SPDX-License-Identifier: MIT

description "spack-packages -- Spack's package recipe repository (the 'builtin'" \
            "namespace), split out of Spack proper since v1.0. Pinned to the" \
            "releases/v2025.11 branch that Spack 1.1 defaults to. Pure data" \
            "(package.py files); nothing is compiled."
homepage "https://github.com/spack/spack-packages"
license "Apache-2.0 OR MIT"

# Commit at the head of releases/v2025.11 (the branch Spack 1.1's default
# repos.yaml clones). Vendored locally so `spack spec` resolves packages with no
# git/network. GitHub commit archive -> stable checksum.
version 2025.11 \
    sha256=aeda9424b679cbbbc338bc55fd93a95b9c2eb24a010d4ea701f0d60c416f4e28 \
    url=https://github.com/spack/spack-packages/archive/119680aeee8ea802c6111b7167583bddef97e82f.tar.gz \
    fname=spack-packages-119680ae.tar.gz

build_system generic

# Modern tar: the GitHub tarball carries a pax_global_header the seed tar 1.12
# can't parse. tar is otherwise the only tool this data-only package needs.
depends_on tar@1.35

install() {
    # The repo root Spack registers is repos/spack_repo/builtin (contains
    # repo.yaml); copy the whole repos/ tree (incl. the spack_repo namespace
    # package). Resolve the unpacked dir explicitly rather than trusting cwd.
    local src
    cd "$stage_dir"
    src=$(set -- spack-packages-*/; printf '%s' "${1%/}")
    mkdir -p "$PREFIX"
    cp -a "$src/repos" "$PREFIX/repos"
}
