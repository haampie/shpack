# SPDX-License-Identifier: MIT
#
# autotools.sh -- build system for packages with a pregenerated ./configure.
# (There is no autoconf in the bootstrap; tarballs must ship configure.)
#
# Phases: configure build install. Hooks: configure_args, build_args,
# install_targets -- one argument per output line, so arguments may contain
# spaces (`AR=tcc -ar`). configure also accepts VAR=value lines (CC=tcc).

SHPACK_PHASES="edit configure build install"

# edit -- programmatic source mutation before configure (the canonical home for
# what would otherwise be ad-hoc sed in setup_build_environment/install: the
# replace_bin_sh repoint, in-tree resource relocation, ...). No-op by default.
default_edit() { :; }

default_configure() {
    # build_directory DIR: configure out-of-tree (gcc/glibc forbid in-tree).
    # mkdir + cd into DIR and run the source tree's configure from there; the
    # cd persists into the build/install phases (they share this shell).
    local cfg bd rel
    cfg=./configure
    if [ -f "$VAR/recipe/$name/build_directory" ]; then
        bd=$(cat "$VAR/recipe/$name/build_directory")
        mkdir -p "$bd"
        cd "$bd"
        # Run configure by a RELATIVE path back to the source tree, not an
        # absolute one. GCC bakes its invocation ($0) into the compiler as
        # TOPLEVEL_CONFIGURE_ARGUMENTS (`gcc -v`), and sets srcdir from it, so an
        # absolute scratch path would leak into configargs AND every __FILE__.
        # `..` per path component of the (source-relative) build dir: `_build`
        # -> `../configure`; `a/b` -> `../../configure`.
        rel=$(echo "$bd" | sed 's#[^/][^/]*#..#g')
        cfg=$rel/configure
    fi
    # Invoke configure through CONFIG_SHELL explicitly rather than relying on
    # its #!/bin/sh shebang (there is no writable /bin/sh on the host). Passing
    # CONFIG_SHELL= and SHELL= makes configure use the same shell for the
    # makefiles it writes and for any sub-configures it recurses into.
    # --disable-dependency-tracking: these are one-shot builds that never
    # incrementally rebuild, so automake's .deps/depcomp machinery is pure
    # overhead (an extra preprocessor pass per object on compilers without fast
    # -MD, e.g. tcc). Autoconf configure that isn't automake just ignores it.
    with_hook_args configure_args "$sh" "$cfg" --prefix="$PREFIX" \
        --disable-dependency-tracking \
        "CONFIG_SHELL=$sh" "SHELL=$sh"
}

default_build() {
    with_hook_args build_args make "SHELL=$sh" $makejobs
}

default_install() {
    IFS='
'
    set -f
    set -- $(hook_words install_targets)
    set +f
    unset IFS
    if [ $# -eq 0 ]; then set -- install; fi
    make "SHELL=$sh" "$@"
}
