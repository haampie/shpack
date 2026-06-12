# SPDX-License-Identifier: MIT
#
# autotools.sh -- build system for packages with a pregenerated ./configure.
# (There is no autoconf in the bootstrap; tarballs must ship configure.)
#
# Phases: configure build install. Hooks: configure_args, build_args,
# install_targets -- one argument per output line, so arguments may contain
# spaces (`AR=tcc -ar`). configure also accepts VAR=value lines (CC=tcc).

SHPACK_PHASES="configure build install"

default_configure() {
    with_hook_args configure_args ./configure --prefix="$PREFIX"
}

default_build() {
    with_hook_args build_args make $MAKEJOBS
}

default_install() {
    IFS='
'
    set -f
    set -- $(hook_words install_targets)
    set +f
    unset IFS
    if [ $# -eq 0 ]; then set -- install; fi
    make "$@"
}
