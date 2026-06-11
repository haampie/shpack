#!/bin/sh
# SPDX-FileCopyrightText: 2023 Samuel Tyler <samuel@samuelt.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

cat >> /steps/env <<'EOF'
DESTDIR=/tmp/destdir
MAKEJOBS=-j${JOBS}
export HOME=/tmp
export PATH=${PREFIX}/bin
export SOURCE_DATE_EPOCH=0
export SHELL=/usr/bin/dash
EOF

. /steps/env
