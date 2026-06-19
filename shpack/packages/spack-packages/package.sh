# SPDX-License-Identifier: MIT

description "spack-packages -- Spack's package recipe repository (the 'builtin'" \
            "namespace), split out of Spack proper since v1.0. A develop" \
            "snapshot (repo API v2.2) to match the Spack v1.2 snapshot. Pure" \
            "data (package.py files); nothing is compiled."
homepage "https://github.com/spack/spack-packages"
license "Apache-2.0 OR MIT"

# develop head (commit deb4f17, 2026-06-19), repo API v2.2, paired with the
# Spack v1.2 snapshot. Vendored locally so `spack spec` resolves packages with
# no git/network. GitHub commit archive -> stable checksum.
version 2026.06 \
    sha256=42bb4f044ea997b31cbb46d6b1f2101d296a28b82d4203444e9204530e555674 \
    url=https://github.com/spack/spack-packages/archive/deb4f17d93dbe012403614245334f7c73fcc086f.tar.gz \
    fname=spack-packages-deb4f17.tar.gz

build_system generic

# Modern tar: the GitHub tarball carries a pax_global_header the seed tar 1.12
# can't parse.
depends_on tar@1.35

install() {
    # Spack registers repos/spack_repo/builtin (contains repo.yaml); copy the
    # whole repos/ tree. Resolve the unpacked dir explicitly rather than trust cwd.
    local src
    cd "$stage_dir"
    src=$(set -- spack-packages-*/; printf '%s' "${1%/}")
    mkdir -p "$PREFIX"
    cp -a "$src/repos" "$PREFIX/repos"
}
