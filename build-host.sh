#!/bin/sh
# SPDX-License-Identifier: MIT
#
# build-host.sh -- chroot-free, relocatable bootstrap to tcc 0.9.27 + musl
# 1.1.24, the Spack-style counterpart to build.sh.
#
#   ./build-host.sh aarch64
#   ./build-host.sh aarch64 --store /path/to/store --build /path/to/scratch
#
# Unlike build.sh (which binds a rootfs at / with bwrap and installs the store at
# the hardcoded /opt), this runs the stage0+kaem chain NATIVELY on the host with
# no namespace and no sudo, installing into a relocatable store ($PWD/store by
# default). You can then run e.g. ./store/tcc-0.9.27/bin/tcc directly -- tcc bakes
# the store's musl crt-prefix / sysinclude in, so it finds its libc with no chroot.
#
# How it stays clean without isolation:
#   * The store, seed tree, kaem TMPDIR and shpack base are all real host paths
#     under --store / --build; the @TOKEN@s in the kaem scripts are set to those.
#   * `env -i` plus a PATH containing ONLY the store's seed-tool dirs keeps host
#     /usr/bin off every lookup, so bare-name tools resolve to our seed builds and
#     nothing execs from the host toolchain. (A landlock policy could later enforce
#     this; it is not needed to reach tcc+musl -- the chain is configure-free and
#     never invokes /bin/sh before dash, which we stop short of.)
#   * The chain is truncated at the tcc+musl sentinel in 0.kaem, so it never runs
#     dash's `cp dash /bin/sh` -- the only step that would write outside the store.
#
# Host must be aarch64 (the seeds run natively; no qemu). Run ./fetch-distfiles.sh
# first to populate distfiles/.

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

die() { echo "build-host.sh: $*" >&2; exit 1; }
abspath() { case "$1" in /*) printf '%s\n' "$1";; *) printf '%s/%s\n' "$PWD" "$1";; esac; }

ARCH=""
STORE="$ROOT/store"
# The one effective tempdir for the entire build: kaem TMPDIR, the seed tree,
# the staged shpack base, the shell phase's HOME and SHPACK_VAR all live under
# it. Honour the POSIX $TMPDIR (default /tmp), per-user (Spack multi-tenant
# pattern), NOT mktemp -- a fixed path so a build is reproducible/resumable.
SCRATCH="${TMPDIR:-/tmp}/$(id -un)"
PHASE=all                          # all | base | shell  (see usage below)
SPECS=""                           # shell-phase targets; default gcc
usage="usage: $0 <aarch64> [--store DIR] [--build DIR] [--base|--shell] [spec...]
  --base   stop after the kaem base (tcc..dash); wipes and rebuilds the store
  --shell  skip the kaem base, run only the shell phase over the existing store
  default  do both; build the given specs (default: gcc)"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --store) STORE=$(abspath "$2"); shift 2 ;;
        --build) SCRATCH=$(abspath "$2"); shift 2 ;;
        --base)  PHASE=base; shift ;;
        --shell) PHASE=shell; shift ;;
        amd64|aarch64) ARCH=$1; shift ;;
        --*) die "$usage" ;;
        *) SPECS="$SPECS $1"; shift ;;     # trailing specs for the shell phase
    esac
done
[ -n "$SPECS" ] || SPECS=gcc
[ -n "$ARCH" ] || die "$usage"
[ "$ARCH" = aarch64 ] || die "only aarch64 is supported here (host is $(uname -m); no qemu path).
$usage"
[ "$(uname -m)" = aarch64 ] || die "host is $(uname -m), not aarch64 -- the seeds run natively, no qemu"

case "$ARCH" in
    aarch64)
        SEEDARCH=AArch64
        S0ARCH=AArch64
        TCC_ARCH_FLAG='-a aarch64'
        ;;
esac

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 1)}"

. "$ROOT/stage.sh"

# --- Token roots: real host paths (cf. build.sh's virtual /opt, /tmp/seed) ----
T_STORE="$STORE"               # @STORE@      -- relocatable install prefix
T_DISTFILES="$ROOT/distfiles"  # @DISTFILES@  -- host checkout, read in place
SEEDDIR="$SCRATCH/seed"        # on-disk seed working tree ...
T_SEEDDIR="$SEEDDIR"           # @SEEDDIR@    -- ... and the token that names it
T_BUILDDIR="$SCRATCH"          # @BUILDDIR@   -- kaem TMPDIR (builds -> $SCRATCH/build/*)
T_SHPACK="$SCRATCH/shpack"     # @SHPACK@     -- staged kaem-phase shpack base
# /bin is not writable without root, so dash installs its `sh` into its own
# store bin; configure/make reach it via CONFIG_SHELL/SHELL (see etc/config.in),
# not via a /bin/sh shebang.
T_SH_LINK_DIR="$STORE/dash-0.5.12/bin"   # @SH_LINK_DIR@
derive_paths "$T_STORE"

[ -d "$T_DISTFILES" ] || die "no distfiles at $T_DISTFILES -- run ./fetch-distfiles.sh first"

# --- Symlink-safe scratch (under world-writable /tmp): Spack's pattern --------
# mkdir then verify it is a real directory we own, so a pre-placed symlink or a
# dir planted by another user can't redirect our writes.
mkdir -p "$SCRATCH"
[ -L "$SCRATCH" ] && die "$SCRATCH is a symlink -- refusing (use --build DIR)"
[ -d "$SCRATCH" ] || die "$SCRATCH is not a directory"
[ "$(stat -c %u "$SCRATCH")" = "$(id -u)" ] || die "$SCRATCH is not owned by you -- refusing (use --build DIR)"

# stage the shpack base (etc/config, externals, bootstrap/) every run: cheap, and
# it picks up recipe/config edits. The live shpack/{bin,lib,packages} are used
# directly for the shell phase, so edits there are live with no re-stage.
stage_shpack "$T_SHPACK"

# ============================================================================
# Phase 1: kaem base (tcc..dash) -- runs unless --shell
# ============================================================================
if [ "$PHASE" != shell ]; then
    # Wipe only the subdirs we manage (never the whole $SCRATCH, which may be
    # shared, nor anything outside it). The store is wiped for a clean build.
    rm -rf "$SEEDDIR" "$SCRATCH/build" "$SCRATCH/tcc_cc.sl64" "$STORE"
    mkdir -p "$STORE"
    stage_seed_tree "$SEEDDIR"

    # --- Launch natively: no chroot, no bwrap, no sudo -----------------------
    # The stage0 scripts are CWD-relative, so we cd into the seed tree (the
    # guarantee chroot used to give via chdir("/")). env -i + the seed-only PATH
    # is the host hygiene; real /proc and /dev are used as-is.
    echo "build-host.sh: building the kaem base (tcc..dash) into $STORE ..."
    cd "$SEEDDIR"
    env -i \
        PATH="$T_SEED_PATH" \
        HOME="$SCRATCH" \
        TERM="${TERM:-dumb}" \
        "./bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed" "kaem.${ARCH}"
    cd "$ROOT"

    # The stage0 seed chain doesn't reliably propagate a nested kaem failure as
    # its own exit status, so assert the deliverables exist rather than $?.
    [ -x "$STORE/tcc-0.9.27/bin/tcc" ]   || die "kaem base failed: no $STORE/tcc-0.9.27/bin/tcc (see output above)"
    [ -f "$STORE/musl-1.1.24/lib/libc.a" ] || die "kaem base failed: no $STORE/musl-1.1.24/lib/libc.a (see output above)"
    [ -x "$STORE/dash-0.5.12/bin/sh" ]   || die "kaem base failed: no $STORE/dash-0.5.12/bin/sh (see output above)"
    echo "build-host.sh: kaem base ready (dash is the first shell)."
fi

if [ "$PHASE" = base ]; then
    echo "build-host.sh: --base done; store at $STORE"
    exit 0
fi

# ============================================================================
# Phase 2: shell phase -- shpack concretizes + builds the requested specs,
# natively, over the kaem base. Uses the LIVE shpack/{bin,lib,packages} (so lib
# and recipe edits are picked up without re-staging) but the staged, substituted
# etc/{config,externals}. SHPACK_VAR lives under the one build tempdir.
# ============================================================================
[ -x "$STORE/dash-0.5.12/bin/sh" ] || die "no kaem base in $STORE (run without --shell first)"
SH="$STORE/dash-0.5.12/bin/sh"
echo "build-host.sh: shell phase -- shpack install$SPECS (no sandbox) ..."
cd "$ROOT"
# shellcheck disable=SC2086  # $SPECS is an intentional word list
env -i \
    PATH="$T_BASEPATH" \
    HOME="$SCRATCH/home" \
    TERM="${TERM:-dumb}" \
    SHPACK_VAR="$SCRATCH/var" \
    SHPACK_CONFIG="$T_SHPACK/etc/config" \
    SHPACK_EXTERNALS="$T_SHPACK/etc/externals" \
    SHPACK_REPO="$ROOT/shpack/packages" \
    "$SH" "$ROOT/shpack/bin/shpack" install $SPECS

echo "build-host.sh: done. Installed:$SPECS into $STORE"
