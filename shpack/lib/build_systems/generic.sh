# SPDX-License-Identifier: MIT
#
# generic.sh -- build system for packages with a bespoke build: the recipe
# must define install() itself (and may do everything there).

SHPACK_PHASES="install"

default_install() {
    die "$name: build_system generic requires the recipe to define install()"
}
