# SPDX-License-Identifier: MIT

description "GNU patch 2.8 -- applies unified/context diffs produced by diff." \
            "Built at the gcc-16 layer; the bootstrap seed patch is 2.5.9" \
            "(2002), this is the modern replacement."
homepage "https://savannah.gnu.org/projects/patch/"
license "GPL-3.0-or-later"

version 2.8 sha256=f87cee69eec2b4fcbf60a396b030ad6aa3415f192aa5f7ee84cad5e11f7f5ae3 \
    url=https://ftpmirror.gnu.org/patch/patch-2.8.tar.xz

build_system autotools

depends_on compiler-wrapper gmake

# Mirror Spack (build_directory = "spack-build"): keeps the build tree out of the
# source so a re-configure stays clean.
build_directory spack-build

configure_args() {
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        --build="$t" \
        --host="$t" \
        --disable-nls
}
