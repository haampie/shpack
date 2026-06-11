#!/bin/sh
# SPDX-FileCopyrightText: 2023 Samuel Tyler <samuel@samuelt.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

mkdir -p /external/repo

# dash already installs itself as /bin/sh (see dash-0.5.12/pass1.kaem), so no
# /bin/sh symlink is needed here anymore.
