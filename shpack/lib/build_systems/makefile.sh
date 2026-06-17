# SPDX-License-Identifier: MIT
#
# makefile.sh -- build system for packages driven by a makefile, either
# upstream's or a replacement shipped in the package's files/ directory.
#
# Phases: edit build install. Hooks: build_targets, install_targets (extra
# words for the respective make invocation, one per line).
#
# make is always invoked with `-f Makefile`: some tarballs ship a
# GNUmakefile, which GNU make would otherwise prefer over a replacement
# Makefile installed by edit.

SHPACK_PHASES="edit build install"

# If the recipe ships files/Makefile, it replaces upstream's (the bootstrap
# pattern for packages whose own build system needs tools we don't have yet).
# Recipes needing more preparation override edit().
default_edit() {
    if [ -f "$package_dir/files/Makefile" ]; then
        cp "$package_dir/files/Makefile" ./Makefile
    fi
}

default_build() {
    with_hook_args build_targets make -f Makefile "SHELL=$sh" \
        $makejobs PREFIX="$PREFIX"
}

default_install() {
    IFS='
'
    set -f
    set -- $(hook_words install_targets)
    set +f
    unset IFS
    if [ $# -eq 0 ]; then set -- install; fi
    make -f Makefile "SHELL=$sh" PREFIX="$PREFIX" "$@"
}
