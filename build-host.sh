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
SCRATCH="/tmp/$(id -un)"          # Spack multi-tenant pattern: per-user, NOT mktemp
while [ "$#" -gt 0 ]; do
    case "$1" in
        --store) STORE=$(abspath "$2"); shift 2 ;;
        --build) SCRATCH=$(abspath "$2"); shift 2 ;;
        amd64|aarch64) ARCH=$1; shift ;;
        *) die "usage: $0 <aarch64> [--store DIR] [--build DIR]" ;;
    esac
done
[ -n "$ARCH" ] || die "usage: $0 <aarch64> [--store DIR] [--build DIR]"
[ "$ARCH" = aarch64 ] || die "only aarch64 is supported here (host is $(uname -m); no qemu path)"
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
derive_paths "$T_STORE"

[ -d "$T_DISTFILES" ] || die "no distfiles at $T_DISTFILES -- run ./fetch-distfiles.sh first"

# --- Symlink-safe scratch (under world-writable /tmp): Spack's pattern --------
# mkdir then verify it is a real directory we own, so a pre-placed symlink or a
# dir planted by another user can't redirect our writes.
mkdir -p "$SCRATCH"
[ -L "$SCRATCH" ] && die "$SCRATCH is a symlink -- refusing (use --build DIR)"
[ -d "$SCRATCH" ] || die "$SCRATCH is not a directory"
[ "$(stat -c %u "$SCRATCH")" = "$(id -u)" ] || die "$SCRATCH is not owned by you -- refusing (use --build DIR)"

# Wipe only the subdirs we manage (never the whole $SCRATCH, which may be shared,
# nor anything outside it). The store is wiped for a clean, reproducible build.
rm -rf "$SEEDDIR" "$T_SHPACK" "$SCRATCH/build" "$SCRATCH/tcc_cc.sl64" "$STORE"
mkdir -p "$STORE"

# --- Stage (shared with build.sh) --------------------------------------------
stage_seed_tree "$SEEDDIR"
stage_shpack "$T_SHPACK" truncate    # truncate the chain at the tcc+musl sentinel

# --- Launch natively: no chroot, no bwrap, no sudo ---------------------------
# The stage0 scripts are CWD-relative, so we cd into the seed tree (the guarantee
# chroot used to give via chdir("/")). env -i + the seed-only PATH is the host
# hygiene; real /proc and /dev are used as-is.
echo "build-host.sh: bootstrapping tcc+musl into $STORE (no sandbox) ..."
cd "$SEEDDIR"
env -i \
    PATH="$T_SEED_PATH" \
    HOME="$SCRATCH" \
    TERM="${TERM:-dumb}" \
    "./bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed" "kaem.${ARCH}"

# The stage0 seed chain doesn't reliably propagate a nested kaem failure as its
# own exit status, so assert the deliverables exist rather than trusting $?.
cd "$ROOT"
[ -x "$STORE/tcc-0.9.27/bin/tcc" ] || die "bootstrap failed: no $STORE/tcc-0.9.27/bin/tcc (see output above)"
[ -f "$STORE/musl-1.1.24/lib/libc.a" ] || die "bootstrap failed: no $STORE/musl-1.1.24/lib/libc.a (see output above)"

cat <<EOF

build-host.sh: done. tcc + musl are in the relocatable store:
  $STORE/tcc-0.9.27/bin/tcc
  $STORE/musl-1.1.24/lib/libc.a
Smoke test:
  printf 'int main(){return 42;}\\n' > /tmp/t.c
  $STORE/tcc-0.9.27/bin/tcc /tmp/t.c -o /tmp/t && /tmp/t; echo \$?   # expect 42
EOF
