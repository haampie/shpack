#!/bin/sh
# SPDX-License-Identifier: MIT
#
# run-local.sh -- bootstrap and run shpack DIRECTLY on the host, with NO ROOT
# CHANGE: no bwrap, chroot or sudo. Installs into a local store ($PWD/store by
# default; --store DIR to override); the resulting ./store/tcc-0.9.27/bin/tcc runs
# standalone. Contrast
# run-rootfs.sh, which bind-mounts a rootfs/ at /. This is not "unsandboxed":
# shpack still wraps every package build in its self-bootstrapped landlock
# sandbox (etc/config's SANDBOX=) -- what is dropped here is only the chroot.
# Host hygiene for the outer driver is env -i plus a PATH containing only the
# store's tool dirs, so host /usr stays off every lookup.
#
#   ./run-local.sh                     # provision if needed, then shpack install gcc
#   ./run-local.sh shpack install xz   # run a command over the existing base
#   ./run-local.sh --arch aarch64      # build for aarch64 (see the emulation note below)
#   ./run-local.sh --base-only         # provision the base, run nothing
#   ./run-local.sh --clean             # force a fresh re-provision (wipes the store)
#   ./run-local.sh --store DIR --build DIR ...
#
# Idempotent: it (re)provisions the kaem base -- stage the stage0 seeds + run the
# kaem chain up to dash -- only when the base is missing or its provision stamp
# (arch + config + seeds, see stage.sh) no longer matches; otherwise it skips
# straight to running the command over the existing store, where only out-of-date
# dag.mk nodes rebuild. Run ./fetch-distfiles.sh first.
#
# aarch64 builds natively on an aarch64 host. On x86_64 it runs only under
# qemu-user emulation (the qemu-aarch64 binfmt `F` handler) -- a dependency on an
# untrusted binary, so it is a testing convenience, not a real bootstrap. We do
# not cross-compile.

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

die() { echo "run-local.sh: $*" >&2; exit 1; }
abspath() { case "$1" in /*) printf '%s\n' "$1";; *) printf '%s/%s\n' "$PWD" "$1";; esac; }

usage="usage: $0 [--arch amd64|aarch64] [--clean] [--base-only] [--store DIR] [--build DIR] [cmd...]"
ARCH=""
STORE="$ROOT/store"
# One fixed tempdir (not mktemp) so a build is reproducible/resumable; per-user
# under $TMPDIR for multi-tenant hosts.
SCRATCH="${TMPDIR:-/tmp}/$(id -un)"
CLEAN=0
BASE_ONLY=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch)      [ "$#" -ge 2 ] || die "$usage"; ARCH=$2; shift 2 ;;
        --store)     [ "$#" -ge 2 ] || die "$usage"; STORE=$(abspath "$2"); shift 2 ;;
        --build)     [ "$#" -ge 2 ] || die "$usage"; SCRATCH=$(abspath "$2"); shift 2 ;;
        --clean)     CLEAN=1; shift ;;
        --base-only) BASE_ONLY=1; shift ;;
        --)          shift; break ;;
        -*)          die "$usage" ;;
        *)           break ;;          # first non-flag begins the command
    esac
done

# ARCH defaults to the host; accept the uname spellings and normalise. Building
# for a foreign arch works here too (no chroot required), but only by running its
# binaries under qemu-user emulation -- see the emulation note in the header.
[ -n "$ARCH" ] || ARCH=$(uname -m)
case "$ARCH" in
    amd64|x86_64)  ARCH=amd64;   SEEDARCH=AMD64;   S0ARCH=AMD64;   TCC_ARCH_FLAG=-64 ;;
    aarch64|arm64) ARCH=aarch64; SEEDARCH=AArch64; S0ARCH=AArch64; TCC_ARCH_FLAG='-a aarch64' ;;
    *) die "unsupported arch: $ARCH (want amd64 or aarch64)" ;;
esac

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 1)}"

. "$ROOT/stage.sh"

# Token roots: real host paths (cf. run-rootfs.sh's virtual /opt, /tmp/seed).
T_STORE="$STORE"               # @STORE@      -- local install prefix root
T_DISTFILES="$ROOT/distfiles"  # @DISTFILES@  -- host checkout, read in place
SEEDDIR="$SCRATCH/seed"
T_SEEDDIR="$SEEDDIR"           # @SEEDDIR@    -- on-disk seed working tree
T_BUILDDIR="$SCRATCH"          # @BUILDDIR@   -- kaem TMPDIR
T_SHPACK="$SCRATCH/shpack"     # @SHPACK@     -- staged kaem-phase shpack base
derive_paths "$T_STORE"

[ -d "$T_DISTFILES" ] || die "no distfiles at $T_DISTFILES -- run ./fetch-distfiles.sh first"

# Scratch under world-writable /tmp: mkdir then verify it is a real dir we own, so
# a planted symlink or foreign-owned dir can't redirect our writes.
mkdir -p "$SCRATCH"
[ -L "$SCRATCH" ] && die "$SCRATCH is a symlink -- refusing (use --build DIR)"
[ "$(stat -c %u "$SCRATCH" 2>/dev/null)" = "$(id -u)" ] || die "$SCRATCH is not owned by you -- refusing (use --build DIR)"

# Stage the shpack base (etc/config, externals, bootstrap/) every run: cheap, and
# it picks up recipe/config edits. The expensive, store-mutating kaem build below
# is what the provision stamp gates.
stage_shpack "$T_SHPACK"

# --- Provision (idempotent) ---------------------------------------------------
# The provision stamp records arch + config + seed fingerprint (stage.sh). When it
# still matches we keep the store and skip the kaem build (this is what makes
# native iteration possible); otherwise wipe and rebuild. The shell-phase state
# ($SCRATCH/var) is wiped with the store: a fresh store would otherwise inherit
# stale dag.mk stamps marking gone prefixes up-to-date.
STAMP="$STORE/.provisioned"
want=$(provision_stamp)
if [ "$CLEAN" = 1 ] || [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$want" ]; then
    echo "run-local.sh: provisioning the kaem base into $STORE for $ARCH ..."
    # stage0 scripts are CWD-relative, so we cd into the seed tree. env -i + the
    # seed-only PATH is the host hygiene; real /proc and /dev are used as-is.
    rm -rf "$SEEDDIR" "$SCRATCH/build" "$SCRATCH/tcc_cc.sl64" "$SCRATCH/var" "$STORE"
    mkdir -p "$STORE"
    stage_seed_tree "$SEEDDIR"
    cd "$SEEDDIR"
    env -i \
        PATH="$T_SEED_PATH" \
        HOME="$SCRATCH" \
        TERM="${TERM:-dumb}" \
        "./bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed" "kaem.${ARCH}"
    cd "$ROOT"
    # stage0 doesn't propagate a nested kaem failure as its own exit status, so
    # assert the deliverable (dash, which the shell phase needs) rather than $?.
    [ -x "$STORE/dash-0.5.12/bin/sh" ] \
        || die "kaem base failed: no $STORE/dash-0.5.12/bin/sh (see output above)"
    printf '%s\n' "$want" > "$STAMP"
else
    echo "run-local.sh: base present ($ARCH) in $STORE -- skipping provision (--clean to rebuild)"
fi

# The `shpack` launcher wrapper: a store-resident shim (store dash shebang +
# body) that execs the live driver, so `shpack` resolves via BASEPATH without
# ever hitting the host /bin/sh. Regenerated each run (cheap; points at the live
# checkout). Written after provisioning so it survives a --clean store wipe.
stage_driver_wrapper "$STORE/shpack-driver/bin" \
    "$STORE/dash-0.5.12/bin/sh" "$ROOT/shpack/bin"

[ "$BASE_ONLY" = 1 ] && exit 0

# --- Launch -------------------------------------------------------------------
# Default to building the toolchain; otherwise run the given command. `shpack`
# resolves via the wrapper on BASEPATH (shpack-driver/bin), so `shpack install
# xz`, `sh`, coreutils, etc. all work under env -i with the shell-phase PATH.
[ "$#" -gt 0 ] || set -- shpack install gcc

# Uses the live shpack/{bin,lib,packages} (recipe edits picked up without
# re-staging) but the staged, substituted etc/{config,externals}.
exec env -i \
    PATH="$T_BASEPATH" \
    HOME="$SCRATCH/home" \
    TERM="${TERM:-dumb}" \
    SHPACK_VAR="$SCRATCH/var" \
    SHPACK_CONFIG="$T_SHPACK/etc/config" \
    SHPACK_EXTERNALS="$T_SHPACK/etc/externals" \
    SHPACK_REPO="$ROOT/shpack/packages" \
    "$@"
