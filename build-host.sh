#!/bin/sh
# SPDX-License-Identifier: MIT
#
# build-host.sh -- chroot-free, relocatable bootstrap to tcc 0.9.27 + musl 1.1.24,
# then `shpack install gcc`, all run NATIVELY on the host (no bwrap, chroot or
# sudo) for the host's own arch. Installs into a relocatable store ($PWD/store by
# default); the resulting ./store/tcc-0.9.27/bin/tcc runs standalone.
#
#   ./build-host.sh aarch64 [--store DIR] [--build DIR]
#
# Native build, so ARCH must match the host (no qemu). Run ./fetch-distfiles.sh
# first. Host hygiene without isolation: `env -i` plus a PATH containing only the
# store's tool dirs keeps host /usr/bin off every lookup, so bare-name tools
# resolve to our seed builds.

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

die() { echo "build-host.sh: $*" >&2; exit 1; }
abspath() { case "$1" in /*) printf '%s\n' "$1";; *) printf '%s/%s\n' "$PWD" "$1";; esac; }

usage="usage: $0 <amd64|aarch64> [--store DIR] [--build DIR]"
ARCH=""
STORE="$ROOT/store"
# One fixed tempdir (not mktemp) so a build is reproducible/resumable; per-user
# under $TMPDIR for multi-tenant hosts.
SCRATCH="${TMPDIR:-/tmp}/$(id -un)"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --store) STORE=$(abspath "$2"); shift 2 ;;
        --build) SCRATCH=$(abspath "$2"); shift 2 ;;
        amd64|aarch64) ARCH=$1; shift ;;
        *) die "$usage" ;;
    esac
done
[ -n "$ARCH" ] || die "$usage"

case "$ARCH" in
    amd64)   SEEDARCH=AMD64;   S0ARCH=AMD64;   TCC_ARCH_FLAG=-64 ;;
    aarch64) SEEDARCH=AArch64; S0ARCH=AArch64; TCC_ARCH_FLAG='-a aarch64' ;;
esac

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 1)}"

. "$ROOT/stage.sh"

# Token roots: real host paths (cf. build.sh's virtual /opt, /tmp/seed).
T_STORE="$STORE"               # @STORE@      -- relocatable install prefix
T_DISTFILES="$ROOT/distfiles"  # @DISTFILES@  -- host checkout, read in place
SEEDDIR="$SCRATCH/seed"
T_SEEDDIR="$SEEDDIR"           # @SEEDDIR@    -- on-disk seed working tree
T_BUILDDIR="$SCRATCH"          # @BUILDDIR@   -- kaem TMPDIR
T_SHPACK="$SCRATCH/shpack"     # @SHPACK@     -- staged kaem-phase shpack base
# /bin is not writable without root, so dash installs its `sh` into its own store
# bin; configure/make reach it via CONFIG_SHELL/SHELL, not a /bin/sh shebang.
T_SH_LINK_DIR="$STORE/dash-0.5.12/bin"   # @SH_LINK_DIR@
derive_paths "$T_STORE"

[ -d "$T_DISTFILES" ] || die "no distfiles at $T_DISTFILES -- run ./fetch-distfiles.sh first"

# Scratch under world-writable /tmp: mkdir then verify it is a real dir we own, so
# a planted symlink or foreign-owned dir can't redirect our writes.
mkdir -p "$SCRATCH"
[ -L "$SCRATCH" ] && die "$SCRATCH is a symlink -- refusing (use --build DIR)"
[ "$(stat -c %u "$SCRATCH" 2>/dev/null)" = "$(id -u)" ] || die "$SCRATCH is not owned by you -- refusing (use --build DIR)"

# Stage the shpack base (etc/config, externals, bootstrap/) every run: cheap, and
# it picks up recipe/config edits.
stage_shpack "$T_SHPACK"

# --- Phase 1: kaem base (tcc..dash), launched natively from the seed tree -------
# stage0 scripts are CWD-relative, so we cd into the seed tree. env -i + the
# seed-only PATH is the host hygiene; real /proc and /dev are used as-is.
rm -rf "$SEEDDIR" "$SCRATCH/build" "$SCRATCH/tcc_cc.sl64" "$STORE"
mkdir -p "$STORE"
stage_seed_tree "$SEEDDIR"
echo "build-host.sh: building the kaem base (tcc..dash) into $STORE ..."
cd "$SEEDDIR"
env -i \
    PATH="$T_SEED_PATH" \
    HOME="$SCRATCH" \
    TERM="${TERM:-dumb}" \
    "./bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed" "kaem.${ARCH}"
cd "$ROOT"

# stage0 doesn't propagate a nested kaem failure as its own exit status, so assert
# the deliverable (dash, which Phase 2 needs) rather than trusting $?.
[ -x "$STORE/dash-0.5.12/bin/sh" ] || die "kaem base failed: no $STORE/dash-0.5.12/bin/sh (see output above)"

# --- Phase 2: shpack concretizes + builds gcc natively over the kaem base -------
# Uses the live shpack/{bin,lib,packages} (recipe edits picked up without
# re-staging) but the staged, substituted etc/{config,externals}.
echo "build-host.sh: shell phase -- shpack install gcc (no sandbox) ..."
env -i \
    PATH="$T_BASEPATH" \
    HOME="$SCRATCH/home" \
    TERM="${TERM:-dumb}" \
    SHPACK_VAR="$SCRATCH/var" \
    SHPACK_CONFIG="$T_SHPACK/etc/config" \
    SHPACK_EXTERNALS="$T_SHPACK/etc/externals" \
    SHPACK_REPO="$ROOT/shpack/packages" \
    "$STORE/dash-0.5.12/bin/sh" "$ROOT/shpack/bin/shpack" install gcc

echo "build-host.sh: done. Installed gcc into $STORE"
