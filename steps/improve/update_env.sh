#!/bin/sh
# SPDX-FileCopyrightText: 2023 Samuel Tyler <samuel@samuelt.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

cat >> /steps/env <<'EOF'
# Shell-phase packages install into per-package prefixes under PKGDIR (a
# Spack-style store); src_install writes straight to the final prefix (no
# DESTDIR staging) and helpers.sh build() prepends each new
# ${PKGDIR}/<pkg>/bin to PATH. The loop below recomposes PATH from the store
# when this file is (re)sourced, so a freshly generated script sees every
# installed package.
PKGDIR=/opt
MAKEJOBS=-j${JOBS}
export HOME=/tmp
export PATH=${PREFIX}/bin
# Recompose PATH from the store. Real shell-phase packages take priority (each
# prepended, so the newest of a duplicate wins). The stage0 SEED prefixes
# (mescc-tools*, M2-Mesoplanet, tcc_cc, stack_c) are the irreducible base layer
# and must sit at the BOTTOM: the real coreutils/etc. built here have to shadow
# the same-named seed tools (the seed rm/cp/... don't grok GNU flags). Patterns
# are version-agnostic; keep them in sync with build.sh's SEED_PATH.
SEEDPATH=
for dir in ${PKGDIR}/*/bin; do
    [ -d "${dir}" ] || continue
    case "${dir}" in
        ${PKGDIR}/mescc-tools-*/bin|${PKGDIR}/mescc-tools-extra-*/bin|${PKGDIR}/M2-Mesoplanet-*/bin|${PKGDIR}/tcc_cc/bin|${PKGDIR}/stack_c/bin)
            SEEDPATH="${SEEDPATH}:${dir}" ;;
        *)
            PATH="${dir}:${PATH}" ;;
    esac
done
PATH="${PATH}${SEEDPATH}"
export SOURCE_DATE_EPOCH=0
# dash now lives in its own store prefix (/opt/dash-0.5.12/bin, on PATH via the
# glob above); /bin/sh is the stable copy installed in its pass1.kaem.
export SHELL=/bin/sh
EOF

. /steps/env
