#!/bin/sh

# SPDX-FileCopyrightText: 2021 Andrius Štikonas <andrius@stikonas.eu>
# SPDX-FileCopyrightText: 2021-22 Samuel Tyler <samuel@samuelt.me>
# SPDX-FileCopyrightText: 2021 Paul Dersey <pdersey@gmail.com>
# SPDX-FileCopyrightText: 2021 Melg Eight <public.melg8@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Set constant umask
umask 022

# Useful for perl extensions
get_perl_version() {
    perl -v | sed -n -re 's/.*[ (]v([0-9\.]*)[ )].*/\1/p'
}

# Common build steps
# Build function provides a few common stages with default implementation
# that can be overridden on per package basis in the build script.
# Every package installs into its own prefix ${PKGDIR}/<name-version>
# (a Spack-style store); after a successful install the package's bin dir is
# prepended to PATH so subsequent builds pick it up. Installed trees are not
# checksummed here; verification is post-hoc (see IDEAS.md).
# build takes three arguments:
# 1) name-version of the package
# 2) optionally specify build script. Default is pass1.sh
# 3) optionally specify directory to cd into
build() {
    pkg=$1
    script_name=${2:-pass1.sh}
    dirname=${3:-${pkg}}

    # Per-package install prefix, visible to the sourced build script's src_*
    # stages (configure --prefix, make install, dependency --with-* paths).
    PREFIX="${PKGDIR}/${pkg}"

    cd "${SRCDIR}/${pkg}" || (echo "Cannot cd into ${pkg}!"; kill $$)
    echo "${pkg}: beginning build using script ${script_name}"
    base_dir="${PWD}"
    if [ -e "${base_dir}/patches-$(basename "${script_name}" .sh)" ]; then
        patch_dir="${base_dir}/patches-$(basename "${script_name}" .sh)"
    else
        patch_dir="${base_dir}/patches"
    fi
    mk_dir="${base_dir}/mk"
    files_dir="${base_dir}/files"

    # Stage in ${TMPDIR}/<name-version> (Spack-style scratch dir), keeping the
    # recipe dir ${SRCDIR}/<name-version> read-only during the build.
    build_dir="${TMPDIR}/${pkg}"
    rm -rf "${build_dir}"
    mkdir "${build_dir}"
    cd "${build_dir}"

    build_script="${base_dir}/${script_name}"
    if test -e "${build_script}"; then
        # shellcheck source=/dev/null
        . "${build_script}"
    fi

    echo "${pkg}: getting sources."
    build_stage=src_get
    call $build_stage

    echo "${pkg}: unpacking source."
    build_stage=src_unpack
    call $build_stage
    unset EXTRA_DISTFILES

    cd "${dirname}" || (echo "Cannot cd into build/${dirname}!"; kill $$)

    echo "${pkg}: preparing source."
    build_stage=src_prepare
    call $build_stage

    echo "${pkg}: configuring source."
    build_stage=src_configure
    call $build_stage

    echo "${pkg}: compiling source."
    build_stage=src_compile
    call $build_stage

    echo "${pkg}: installing to ${PREFIX}."
    mkdir -p "${PREFIX}"
    build_stage=src_install
    call $build_stage

    echo "${pkg}: postprocess binaries."
    build_stage=src_postprocess
    call $build_stage

    echo "${pkg}: cleaning up."
    # Step out of the build tree before deleting it (rm refuses to operate
    # from a working directory it cannot return to).
    cd "${SRCDIR}"
    rm -rf "${build_dir}"

    # Make the new package available to subsequent builds.
    if [ -d "${PREFIX}/bin" ]; then
        export PATH="${PREFIX}/bin:${PATH}"
    fi

    echo "${pkg}: build successful"

    cd "${SRCDIR}"

    unset -f src_get src_unpack src_prepare src_configure src_compile src_install src_postprocess
    unset extract
}

# An inventive way to randomise with what we know we always have
randomize() {
    if command -v shuf >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        shuf -e ${1} | tr '\n' ' '
    else
        mkdir -p /tmp/random
        for item in ${1}; do
            touch --date=@${RANDOM} /tmp/random/"${item//\//~*~*}"
        done
        # cannot rely on find existing
        # shellcheck disable=SC2012
        ls -1 -t /tmp/random | sed 's:~\*~\*:/:g' | tr '\n' ' '
        rm -r /tmp/random
    fi
}

download_source_line() {
    upstream_url="${1}"
    checksum="${2}"
    fname="${3}"
    if ! [ -e "${fname}" ]; then
        for mirror in $(randomize "${MIRRORS}"); do
            # In qemu SimpleMirror is not running on the guest os, use qemu IP
            case "${QEMU}-${mirror}" in 'True-http://127.0.0.1'*)
                mirror="http://10.0.2.2${mirror#'http://127.0.0.1'}"
            esac
            mirror_url="${mirror}/${fname}"
            echo "${mirror_url}"
            curl --fail --retry 3 --location "${mirror_url}" --output "${fname}" || true && break
        done
        if ! [ -e "${fname}" ] && [ "${upstream_url}" != "_" ]; then
            curl --fail --retry 3 --location "${upstream_url}" --output "${fname}" || true
        fi
    fi
}

check_source_line() {
    url="${1}"
    checksum="${2}"
    fname="${3}"
    if ! [ -e "${fname}" ]; then
        echo "${fname} does not exist!"
        false
    fi
    echo "${checksum}  ${fname}" > "${fname}.sum"
    sha256sum -c "${fname}.sum"
    rm "${fname}.sum"
}

source_line_action() {
    action="$1"
    shift
    type="$1"
    shift
    case $type in
        "g" | "git")
            shift
            ;;
    esac
    url="${1}"
    checksum="${2}"
    fname="${3}"
    # Default to basename of url if not given
    fname="${fname:-$(basename "${url}")}"
    $action "$url" "$checksum" "$fname"
}

# Default get function that downloads source tarballs.
default_src_get() {
    # shellcheck disable=SC2153
    cd "${DISTFILES}"
    # shellcheck disable=SC2162
    while read line; do
        # This is intentional - we want to split out ${line} into separate arguments.
        # shellcheck disable=SC2086
        source_line_action download_source_line ${line}
    done < "${base_dir}/sources"
    # shellcheck disable=SC2162
    while read line; do
        # This is intentional - we want to split out ${line} into separate arguments.
        # shellcheck disable=SC2086
        source_line_action check_source_line ${line}
    done < "${base_dir}/sources"
    cd -
}

# Intelligently extracts a file based upon its filetype.
extract_file() {
    f="${3:-$(basename "${1}")}"
    # shellcheck disable=SC2154
    case "${noextract}" in
        *${f}*)
            cp "${DISTFILES}/${f}" .
            ;;
        *)
            case "${f}" in
                *.tar* | *.tgz)
                    # shellcheck disable=SC2153
                    if test -e "${PREFIX}/libexec/rmt"; then
                        # Again, we want to split out into words.
                        # shellcheck disable=SC2086
                        tar --no-same-owner -xf "${DISTFILES}/${f}" ${extract}
                    else
                        # shellcheck disable=SC2086
                        case "${f}" in
                        *.tar.gz) tar -xzf "${DISTFILES}/${f}" ${extract} ;;
                        *.tar.bz2)
                            # Initial bzip2 built against meslibc has broken pipes
                            bzip2 -dc "${DISTFILES}/${f}" | tar -xf - ${extract} ;;
                        *.tar.xz | *.tar.lzma)
                            if test -e "${PREFIX}/bin/xz"; then
                                tar -xf "${DISTFILES}/${f}" --use-compress-program=xz ${extract}
                            else
                                unxz --file "${DISTFILES}/${f}" | tar -xf - ${extract}
                            fi
                            ;;
                        esac
                    fi
                    ;;
                *)
                    cp "${DISTFILES}/${f}" .
                    ;;
            esac
            ;;
    esac
}

# Default unpacking function that unpacks all sources.
default_src_unpack() {
    # Handle the first one differently
    first_line=$(head -n 1 "${base_dir}/sources")
    # Again, we want to split out into words.
    # shellcheck disable=SC2086
    source_line_action extract_file ${first_line}
    # This assumes there is only one directory in the tarball
    # Get the dirname "smartly"
    if ! [ -e "${dirname}" ]; then
        for i in *; do
            if [ -d "${i}" ]; then
                dirname="${i}"
                break
            fi
        done
    fi
    if ! [ -e "${dirname}" ]; then
        # there are no directories extracted
        dirname=.
    fi
    # shellcheck disable=SC2162
    tail -n +2 "${base_dir}/sources" | while read line; do
        # shellcheck disable=SC2086
        source_line_action extract_file ${line}
    done
}

# Default function to prepare source code.
# It applies all patches from patch_dir (at the moment only -p0 patches are supported).
# Patches are applied from the parent directory.
# Then it copies our custom makefile and any other custom files from files directory.
default_src_prepare() {
    if test -d "${patch_dir}"; then
        if ls "${patch_dir}"/*.patch >/dev/null 2>&1; then
            for p in "${patch_dir}"/*.patch; do
                echo "Applying patch: ${p}"
                patch -d.. -Np0 < "${p}"
            done
        fi
    fi

    makefile="${mk_dir}/main.mk"
    if test -e "${makefile}"; then
        cp "${makefile}" Makefile
    fi

    if test -d "${files_dir}"; then
        cp --no-preserve=mode "${files_dir}"/* "${PWD}/"
    fi
}

# Default function for configuring source.
default_src_configure() {
    :
}

# Default function for compiling source. It simply runs make without any parameters.
default_src_compile() {
    make "${MAKEJOBS}" -f Makefile PREFIX="${PREFIX}"
}

# Default installing function. PREFIX should be set by run.sh script.
# Note that upstream makefiles might ignore PREFIX and have to be configured in configure stage.
default_src_install() {
    make -f Makefile install PREFIX="${PREFIX}"
}

# Helper function for permissions
_do_strip() {
    # POSIX way to grab the last positional parameter (dash has no ${@: -1}).
    local f
    for f in "$@"; do :; done
    if ! [ -w "${f}" ]; then
        local perms
        perms="$(stat -c %a "${f}")"
        chmod u+w "${f}"
    fi
    strip "$@"
    if [ -n "${perms}" ]; then
        chmod "${perms}" "${f}"
    fi
}

# Default function for postprocessing binaries.
default_src_postprocess() {
    if (command -v find && command -v file && command -v strip) >/dev/null 2>&1; then
        # Logic largely taken from void linux 06-strip-and-debug-pkgs.sh
        # shellcheck disable=SC2162
        find "${PREFIX}" -type f | while read f; do
            case "$(file -bi "${f}")" in
                application/x-executable*) _do_strip "${f}" ;;
                application/x-sharedlib*|application/x-pie-executable*)
                    machine_set="$(file -b "${f}")"
                    case "${machine_set}" in
                        *no\ machine*) ;; # don't strip ELF container-only
                        *) _do_strip --strip-unneeded "${f}" ;;
                    esac
                    ;;
                application/x-archive*) _do_strip --strip-debug "${f}" ;;
            esac
        done
    fi
}

# Check if a shell function exists. dash has no `type -t`; for a function,
# `command -v name` echoes the bare name (an external would be a /path, and the
# build-stage names checked here are never builtins).
fn_exists() {
    [ "$(command -v "$1" 2>/dev/null)" = "$1" ]
}

# Call package specific function or default implementation.
call() {
    if fn_exists "$1"; then
        $1
    else
        default_"${1}"
    fi
}

# Call default build stage function
default() {
    "default_${build_stage}"
}
