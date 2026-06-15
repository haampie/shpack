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
    # build_directory DIR: configure out-of-tree (gcc/glibc forbid in-tree).
    # mkdir + cd into DIR and run the source tree's configure from there; the
    # cd persists into the build/install phases (they share this shell).
    local cfg
    cfg=./configure
    if [ -f "$VAR/recipe/$name/build_directory" ]; then
        mkdir -p "$(cat "$VAR/recipe/$name/build_directory")"
        cd "$(cat "$VAR/recipe/$name/build_directory")"
        cfg=$source_dir/configure
    fi
    # --disable-dependency-tracking: these are one-shot builds that never
    # incrementally rebuild, so automake's .deps/depcomp machinery is pure
    # overhead (an extra preprocessor pass per object on compilers without fast
    # -MD, e.g. tcc). Autoconf configure that isn't automake just ignores it.
    with_hook_args configure_args "$cfg" --prefix="$PREFIX" \
        --disable-dependency-tracking
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
