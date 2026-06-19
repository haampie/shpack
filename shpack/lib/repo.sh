# SPDX-License-Identifier: MIT
#
# repo.sh -- recipe loading.
#
# A package is a directory $REPO/<name> containing package.sh (the recipe)
# plus optional patches/ and files/ subdirectories. The recipe is a POSIX
# shell fragment with two kinds of content:
#
#   * directive calls (below), declaring metadata: versions and their source
#     checksums, dependencies, patches, the build system;
#   * optional hook functions overriding build-system defaults at build time:
#     full phases (configure, build, install, edit) or argument hooks
#     (configure_args, build_args, build_targets, install_targets,
#     setup_build_environment).
#
# Directives do not interpret anything; they record their arguments into
# per-package state files under $VAR/recipe/<name>/, which concretization and
# the builder then read. Loading a recipe twice resets its state.

SHPACK_DIRECTIVES="description homepage license version resource depends_on patch build_system parallel build_directory"

description()  { printf '%s\n' "$*" > "$RECIPE_STATE/description"; }
homepage()     { printf '%s\n' "$*" > "$RECIPE_STATE/homepage"; }
license()      { printf '%s\n' "$*" > "$RECIPE_STATE/license"; }
# build_system NAME [when=VER]
# The build system (generic|makefile|autotools). Repeatable with when=VER to
# vary by version (same convention as depends_on); '-' (no when=) matches all
# versions. Stored one line per call as: WHEN NAME. builder.sh takes the first
# matching line.
build_system() {
    local kv when
    when=-
    for kv in "$@"; do
        case $kv in when=*) when=${kv#*=} ;; esac
    done
    printf '%s %s\n' "$when" "$1" >> "$RECIPE_STATE/build_system"
}

# parallel false -- this package's make must not run with -j.
parallel()     { printf '%s\n' "$1" > "$RECIPE_STATE/parallel"; }

# build_directory DIR -- configure/build out-of-tree in DIR (relative to the
# source tree), for build systems (autotools) that forbid an in-tree build,
# e.g. gcc/glibc. The build system creates DIR, cd's into it, and runs the
# source tree's configure from there; later phases inherit the cd.
build_directory() { printf '%s\n' "$1" > "$RECIPE_STATE/build_directory"; }

# version VER [sha256=HEX] [url=URL] [fname=NAME]
# Declares a buildable version and its source tarball. Repeatable; a bare
# dependency on the package resolves to the newest declared version. A
# version without sha256 has no sources (nothing fetched, empty stage).
# Stored as one line: VER SHA FNAME URL ('-' for absent fields).
version() {
    local ver kv sha url fname
    ver=$1
    shift
    sha=- url=- fname=-
    for kv in "$@"; do
        case $kv in
            sha256=*) sha=${kv#*=} ;;
            url=*)    url=${kv#*=} ;;
            fname=*)  fname=${kv#*=} ;;
            *) die "version $ver: unknown argument '$kv'" ;;
        esac
    done
    if [ "$fname" = - ] && [ "$url" != - ]; then
        fname=${url##*/}
    fi
    printf '%s %s %s %s\n' "$ver" "$sha" "$fname" "$url" \
        >> "$RECIPE_STATE/versions"
}

# resource sha256=HEX [url=URL] [fname=NAME] [when=VER]
# An additional distfile, fetched and unpacked into the stage alongside the
# main source. when=VER limits it to one version (default: all versions).
# Stored as one line: WHEN SHA FNAME URL.
resource() {
    local kv sha url fname when
    sha=- url=- fname=- when=-
    for kv in "$@"; do
        case $kv in
            sha256=*) sha=${kv#*=} ;;
            url=*)    url=${kv#*=} ;;
            fname=*)  fname=${kv#*=} ;;
            when=*)   when=${kv#*=} ;;
            *) die "resource: unknown argument '$kv'" ;;
        esac
    done
    if [ "$fname" = - ] && [ "$url" != - ]; then
        fname=${url##*/}
    fi
    if [ "$sha" = - ]; then
        die "resource: sha256= is required"
    fi
    printf '%s %s %s %s\n' "$when" "$sha" "$fname" "$url" \
        >> "$RECIPE_STATE/resources"
}

# depends_on SPEC... [when=VER]
# Direct build dependencies (name or name@version). An optional when=VER
# limits every spec in this call to one declared version of THIS package
# (default: all versions); same exact-match convention as patch/resource.
# Stored one line per spec as: WHEN SPEC ('-' when unconditional).
depends_on() {
    local kv when spec
    when=-
    for kv in "$@"; do
        case $kv in
            when=*) when=${kv#*=} ;;
        esac
    done
    for spec in "$@"; do
        case $spec in
            when=*) continue ;;
        esac
        printf '%s %s\n' "$when" "$spec" >> "$RECIPE_STATE/deps"
    done
}

# patch FILE [arch=ARCH] [level=N] [when=VER]
# Apply patches/FILE during the patch stage, -pN (default -p1), optionally
# only for one target arch or recipe version.
patch() {
    printf '%s\n' "$*" >> "$RECIPE_STATE/patches"
}

# recipe_load NAME -- evaluate $REPO/NAME/package.sh, capturing directives
# into $VAR/recipe/NAME. Concretization calls this in a subshell (hook
# definitions are discarded with it); the builder calls it in-process to keep
# the hooks, then disarms the directives.
recipe_load() {
    RECIPE_STATE=$VAR/recipe/$1
    [ -f "$REPO/$1/package.sh" ] || die "no recipe $REPO/$1/package.sh"
    rm -rf "$RECIPE_STATE"
    mkdir -p "$RECIPE_STATE"
    . "$REPO/$1/package.sh"
}

# recipe_meta NAME -- make sure NAME's directive state is loaded (subshell
# load, hooks discarded). Returns 1 if there is no such recipe.
recipe_meta() {
    if [ -f "$VAR/recipe/$1/.loaded" ]; then return 0; fi
    if [ ! -f "$REPO/$1/package.sh" ]; then return 1; fi
    ( recipe_load "$1" )
    touch "$VAR/recipe/$1/.loaded"
}

# recipe_disarm -- undefine the directive functions, so that a build-time
# recipe load cannot shadow real commands (notably patch(1)) afterwards.
recipe_disarm() {
    unset -f $SHPACK_DIRECTIVES
}

# spec_sources NAME VER -> "SHA FNAME URL" lines for the version's main
# source plus all matching resources. Versions without sources print nothing.
spec_sources() {
    local rs v sha fname url when
    rs=$VAR/recipe/$1
    if [ -f "$rs/versions" ]; then
        while read -r v sha fname url; do
            if [ "$v" = "$2" ] && [ "$sha" != - ]; then
                printf '%s %s %s\n' "$sha" "$fname" "$url"
            fi
        done < "$rs/versions"
    fi
    if [ -f "$rs/resources" ]; then
        while read -r when sha fname url; do
            if [ "$when" = - ] || [ "$when" = "$2" ]; then
                printf '%s %s %s\n' "$sha" "$fname" "$url"
            fi
        done < "$rs/resources"
    fi
}
