# SPDX-License-Identifier: MIT

description "GNU awk (configure scripts and gcc's Makefiles script with it)"
homepage "https://www.gnu.org/software/gawk/"
license "GPL-2.0-or-later"

version 3.0.4 sha256=5cc35def1ff4375a8b9a98c2ff79e95e80987d24f0d42fdbb7b7039b3ddb3fb0 \
    url=https://mirrors.kernel.org/gnu/gawk/gawk-3.0.4.tar.gz

build_system makefile

depends_on tcc musl grep
