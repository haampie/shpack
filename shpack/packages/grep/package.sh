# SPDX-License-Identifier: MIT

description "GNU grep: pattern matching, the first shell-phase tool" \
            "(every GNU configure script needs it)"
homepage "https://www.gnu.org/software/grep/"
license "GPL-2.0-or-later"

version 2.4 sha256=a32032bab36208509466654df12f507600dfe0313feebbcd218c32a70bf72a16 \
    url=https://mirrors.kernel.org/gnu/grep/grep-2.4.tar.gz

build_system makefile

depends_on tcc musl
