# SPDX-License-Identifier: MIT
#
# makefile.sh -- build system for packages driven by a makefile, either
# upstream's or a replacement shipped in the package's files/ directory.
#
# Phases: edit build install. Hooks: build_targets, install_targets (extra
# words for the respective make invocation).

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
    make $MAKEJOBS PREFIX="$PREFIX" $(hook_words build_targets)
}

default_install() {
    set -- $(hook_words install_targets)
    if [ $# -eq 0 ]; then set -- install; fi
    make PREFIX="$PREFIX" "$@"
}
