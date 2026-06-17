# SPDX-License-Identifier: MIT
#
# generic.sh -- build system for packages with a bespoke build: the recipe
# must define install() itself (and may do everything there).

SHPACK_PHASES="edit install"

# edit -- optional programmatic source mutation before install (e.g. the
# replace_bin_sh repoint). No-op by default.
default_edit() { :; }

default_install() {
    die "$name: build_system generic requires the recipe to define install()"
}
