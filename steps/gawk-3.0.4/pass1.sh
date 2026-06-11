# SPDX-FileCopyrightText: 2021 Andrius Štikonas <andrius@stikonas.eu>
# SPDX-FileCopyrightText: 2022 Samuel Tyler <samuel@samuelt.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

src_prepare() {
    default
    # awktab.c is pre-generated in the tarball; touch it so make doesn't
    # try to regenerate it via bison (which isn't available yet).
    touch awktab.c
}
