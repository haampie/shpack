# SPDX-License-Identifier: MIT
#
# builder.sh -- build one concretized node in its own process.
#
# Invoked from a dag.mk recipe as `shpack build-one <id>` with PATH already
# composed from the node's dependency closure. The pipeline is:
#
#   fetch    verify (and if curl exists, download) the distfiles
#   stage    unpack into $VAR/stage/<id>, cd into the source directory
#   patch    apply the recipe's declared patches
#   <phases> the build system's phases (e.g. configure build install),
#            each overridable by a hook function in the recipe
#   finalize write $PREFIX/.shpack metadata: spec, deps, manifest, recipe
#
# Globals exposed to recipe hooks: name, version, id, PREFIX, package_dir,
# stage_dir, ARCH, JOBS, MAKEJOBS, and the helper prefix_of.

# is_function NAME -> true if NAME is a shell function (dash: "NAME is a
# shell function"; bash: "NAME is a function").
is_function() {
    case $(type "$1" 2>/dev/null) in
        *function*) return 0 ;;
    esac
    return 1
}

# hook_words NAME -- expand an argument-hook function to its output, or
# nothing if the recipe does not define it.
hook_words() {
    if is_function "$1"; then "$1"; fi
}

# with_hook_args HOOK CMD [ARG...] -- run CMD with the fixed args followed by
# the hook's output, one argument per output LINE (so hook-provided arguments
# may contain spaces, e.g. `AR=tcc -ar`).
with_hook_args() {
    local hook
    hook=$1
    shift
    IFS='
'
    set -f
    set -- "$@" $(hook_words "$hook")
    set +f
    unset IFS
    "$@"
}

# prefix_of NAME -> the store prefix of a dependency (direct or transitive).
prefix_of() {
    local d
    for d in $(cat "$SPEC/deps") $(cat "$SPEC/closure"); do
        if [ "$(cat "$VAR/spec/$d/name")" = "$1" ]; then
            cat "$VAR/spec/$d/prefix"
            return 0
        fi
    done
    die "prefix_of: '$1' is not in the dependency closure of $id"
}

# triple [LIBC] [VENDOR] -> the target triple for $ARCH, e.g. x86_64-linux-gnu.
# LIBC is gnu (default) or musl; VENDOR is omitted by default, pass `unknown`
# for the -unknown- form the older config.sub vintages in the early chain
# expect. Covers all four triples the recipes use:
#   triple gnu          x86_64-linux-gnu          (glibc cap)
#   triple musl         x86_64-linux-musl         (bison/gawk5/python)
#   triple musl unknown x86_64-unknown-linux-musl (tcc/gcc4.7 tool layer)
#   triple gnu unknown  x86_64-unknown-linux-gnu  (math libs, findutils)
triple() {
    local cpu libc vendor
    libc=${1:-gnu}
    vendor=${2:+$2-}
    case "$ARCH" in
        amd64)   cpu=x86_64 ;;
        aarch64) cpu=aarch64 ;;
    esac
    printf '%s\n' "$cpu-${vendor}linux-$libc"
}

# download URL DEST -- best effort, mirrors first; only meaningful once curl
# exists (QEMU/network builds). The chroot bootstrap prestages distfiles.
download() {
    local m
    if ! command -v curl >/dev/null 2>&1; then
        die "distfile $2 is missing and there is no curl to fetch it"
    fi
    for m in ${MIRRORS:-}; do
        if curl --fail --retry 3 --location "$m/${2##*/}" --output "$2"; then
            return 0
        fi
    done
    if [ "$1" != - ]; then
        curl --fail --retry 3 --location "$1" --output "$2"
    fi
}

do_fetch() {
    local sha fname url
    while read -r sha fname url; do
        if [ ! -f "$DISTFILES/$fname" ]; then
            download "$url" "$DISTFILES/$fname"
        fi
        printf '%s  %s\n' "$sha" "$DISTFILES/$fname" > "$stage_dir/.fetch.sum"
        sha256sum -c "$stage_dir/.fetch.sum"
        rm -f "$stage_dir/.fetch.sum"
    done < "$SPEC/sources"
}

# unpack FILE -- extract an archive into the current directory. Compressors
# are piped so this works from the earliest bootstrap tar onward.
unpack() {
    case $1 in
        *.tar.gz|*.tgz)      gzip -dc "$1" | tar -xf - ;;
        *.tar.bz2)           bzip2 -dc "$1" | tar -xf - ;;
        *.tar.xz|*.tar.lzma) unxz < "$1" | tar -xf - ;;
        *.tar)               tar -xf "$1" ;;
        *)                   cp "$1" . ;;
    esac
}

do_stage() {
    local sha fname url d
    cd "$stage_dir"
    while read -r sha fname url; do
        unpack "$DISTFILES/$fname"
    done < "$SPEC/sources"
    # The source directory is the single directory the (first) tarball
    # created; sourceless packages build in the stage dir itself.
    source_dir=$stage_dir
    for d in *; do
        if [ -d "$d" ]; then
            source_dir=$stage_dir/$d
            break
        fi
    done
    cd "$source_dir"
}

do_patch() {
    local line file kv level cond_arch cond_when
    if [ ! -f "$VAR/recipe/$name/patches" ]; then return 0; fi
    while read -r line; do
        set -- $line
        file=$1
        shift
        level=1 cond_arch= cond_when=
        for kv in "$@"; do
            case $kv in
                arch=*)  cond_arch=${kv#*=} ;;
                level=*) level=${kv#*=} ;;
                when=*)  cond_when=${kv#*=} ;;
                *) die "patch $file: unknown argument '$kv'" ;;
            esac
        done
        if [ -n "$cond_arch" ] && [ "$cond_arch" != "$ARCH" ]; then continue; fi
        if [ -n "$cond_when" ] && [ "$cond_when" != "$version" ]; then continue; fi
        echo "==> $id: applying $file"
        command patch -p"$level" < "$package_dir/patches/$file"
    done < "$VAR/recipe/$name/patches"
}

do_finalize() {
    local d
    mkdir -p "$PREFIX/.shpack"
    {
        printf 'name %s\n' "$name"
        printf 'version %s\n' "$version"
        printf 'hash %s\n' "$hash"
        printf 'arch %s\n' "$ARCH"
    } > "$PREFIX/.shpack/spec"
    : > "$PREFIX/.shpack/deps"
    for d in $(cat "$SPEC/deps"); do
        printf '%s-%s\n' "$d" "$(cat "$VAR/spec/$d/hash")" \
            >> "$PREFIX/.shpack/deps"
    done
    cp "$SPEC/manifest" "$PREFIX/.shpack/manifest"
    cp "$package_dir/package.sh" "$PREFIX/.shpack/package.sh"
    cd /
    rm -rf "$stage_dir"
}

cmd_build_one() {
    local phase bs
    if [ $# -ne 1 ]; then die "usage: shpack build-one <id>"; fi
    id=$1
    SPEC=$VAR/spec/$id
    [ -f "$SPEC/kind" ] || die "unknown node '$id' (run shpack concretize)"
    [ "$(cat "$SPEC/kind")" = built ] || die "node '$id' is external"
    name=$(cat "$SPEC/name")
    version=$(cat "$SPEC/version")
    hash=$(cat "$SPEC/hash")
    PREFIX=$(cat "$SPEC/prefix")
    if [ -f "$PREFIX/.shpack/spec" ]; then
        echo "$id is already installed in $PREFIX"
        return 0
    fi

    package_dir=$REPO/$name
    recipe_load "$name"
    recipe_disarm

    bs=generic
    if [ -f "$VAR/recipe/$name/build_system" ]; then
        bs=$(cat "$VAR/recipe/$name/build_system")
    fi
    [ -f "$SHPACK_LIB/build_systems/$bs.sh" ] \
        || die "$name: unknown build system '$bs'"
    . "$SHPACK_LIB/build_systems/$bs.sh"

    # Empty so the inner make inherits the dag.mk jobserver from MAKEFLAGS;
    # an explicit -j would override it and oversubscribe JOBS x JOBS.
    # 'parallel false' needs -j1 to serialize against that jobserver.
    MAKEJOBS=
    if [ -f "$VAR/recipe/$name/parallel" ] \
        && [ "$(cat "$VAR/recipe/$name/parallel")" = false ]; then
        MAKEJOBS=-j1
    fi
    # HOME under the build's own scratch ($VAR, itself under $TMPDIR on the
    # host): some configure/test steps write dotfiles, and a build must not
    # depend on or pollute a real home. CONFIG_SHELL/SHELL: the explicit build
    # shell (etc/config), so nothing relies on a /bin/sh shebang.
    BUILD_HOME=$VAR/home
    mkdir -p "$BUILD_HOME"
    # SHELL via MAKEFLAGS so it reaches recursive sub-makes and overrides even a
    # baked-in `SHELL = /bin/sh` (kernel headers, musl, gawk@3.0.4); otherwise a
    # sub-make falls back to host /bin/sh, which the sandbox denies. Append to
    # preserve the dag.mk jobserver flags already here.
    MAKEFLAGS="${MAKEFLAGS:-} SHELL=$CONFIG_SHELL"
    export PREFIX ARCH JOBS MAKEJOBS MAKEFLAGS SOURCE_DATE_EPOCH=0 \
        HOME="$BUILD_HOME" CONFIG_SHELL SHELL PATH

    stage_dir=$VAR/stage/$id
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"
    spec_sources "$name" "$version" > "$SPEC/sources"

    echo "==> $id: fetch"
    do_fetch
    echo "==> $id: stage"
    do_stage
    do_patch

    # Repoint #!/bin/sh shebangs (build helpers like install-sh, config.guess are
    # exec'd directly) at the store shell, since the sandbox has no host /bin/sh.
    # Whole $stage_dir, not just $source_dir: a `resource` (gcc's in-tree gmp/
    # mpfr/mpc) sits as a sibling until setup_build_environment relocates it.
    if [ -n "${PATCH_SHEBANGS:-}" ]; then
        echo "==> $id: patch-shebangs"
        "$PATCH_SHEBANGS" "$CONFIG_SHELL" "$stage_dir"
    fi

    if is_function setup_build_environment; then
        setup_build_environment
    fi

    mkdir -p "$PREFIX"
    for phase in $SHPACK_PHASES; do
        echo "==> $id: $phase"
        if is_function "$phase"; then
            "$phase"
        else
            "default_$phase"
        fi
    done

    echo "==> $id: finalize"
    do_finalize
    echo "==> $id: installed in $PREFIX"
}
