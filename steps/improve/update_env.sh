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
for dir in ${PKGDIR}/*/bin; do
    if [ -d "${dir}" ]; then
        PATH="${dir}:${PATH}"
    fi
done
export SOURCE_DATE_EPOCH=0
# dash now lives in its own store prefix (/opt/dash-0.5.12/bin, on PATH via the
# glob above); /bin/sh is the stable copy installed in its pass1.kaem.
export SHELL=/bin/sh
EOF

. /steps/env
