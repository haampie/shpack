# SPDX-License-Identifier: MIT
#
# autotools.sh -- build system for packages with a pregenerated ./configure.
# (There is no autoconf in the bootstrap; tarballs must ship configure.)
#
# Phases: configure build install. Hooks: configure_args, build_args,
# install_targets.

SHPACK_PHASES="configure build install"

default_configure() {
    ./configure --prefix="$PREFIX" $(hook_words configure_args)
}

default_build() {
    make $MAKEJOBS $(hook_words build_args)
}

default_install() {
    set -- $(hook_words install_targets)
    if [ $# -eq 0 ]; then set -- install; fi
    make "$@"
}
