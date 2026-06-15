#!/bin/sh
# SPDX-License-Identifier: MIT
#
# run.sh -- the launcher. Runs a command over the provisioned base rootfs (built
# by ./build.sh <arch>), with shpack's package manager bind-mounted live from
# the host so recipe edits take effect WITHOUT a re-provision.
#
#   ./run.sh                       # interactive shell in the sandbox (default)
#   ./run.sh shpack install gcc    # build the toolchain
#   ./run.sh shpack install xz     # build/refresh one package
#   ./run.sh shpack find           # any shpack subcommand
#
# Reuses the existing store (rootfs/opt/*): already-built nodes are skipped via
# their dag.mk stamps, and only the requested package (and any out-of-date deps)
# rebuild. The store (/opt) and shpack state (/tmp/shpack) are the persistent,
# writable "volume"; shpack/{bin,lib,packages} and distfiles are mounted
# read-only from the host checkout (so edits there are live, and the 500M+ of
# distfiles is never copied).
#
# Rootless bwrap (see sandbox.sh): no sudo. The store and state are shared on
# disk, so run one build at a time -- two concurrent runs would corrupt each
# other.

set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
. "$ROOT/sandbox.sh"

[ -d rootfs/opt ] && [ -f rootfs/shpack/etc/config ] || {
    echo "run.sh: no provisioned base -- run ./build.sh <amd64|aarch64> first" >&2
    exit 1; }

# PATH floor handed to shpack: the BASEPATH the kaem phase baked into the config
# (kaem-phase /opt prefixes newest-first, then the seed dirs).
BP=$(sed -n 's/^BASEPATH=//p' rootfs/shpack/etc/config | head -1)

# No command -> an interactive shell in the sandbox. `shpack` resolves via PATH
# (/shpack/bin, set below).
[ "$#" -gt 0 ] || set -- /bin/sh

# NOTE: /opt and /tmp/shpack live inside rootfs and are shared on disk (only the
# build scratch tmpfs is per-namespace), so run one build at a time -- two
# concurrent launches would corrupt each other's store/stamps.

# Bind the package manager + distfiles read-only from the host checkout. Only
# /shpack/{bin,lib,packages} are mounted; /shpack/{etc,bootstrap} come from the
# baked base, so the substituted etc/config is preserved. shpack writes only
# under /tmp/shpack and the /opt store, never under /shpack, so read-only is safe.
# --clearenv so the host shell's environment never reaches a build.
sandbox "$ROOT/rootfs" \
    --clearenv \
    --setenv PATH "/shpack/bin:$BP" \
    --setenv HOME /tmp \
    --setenv TERM "${TERM:-dumb}" \
    --ro-bind "$ROOT/shpack/bin"      /shpack/bin \
    --ro-bind "$ROOT/shpack/lib"      /shpack/lib \
    --ro-bind "$ROOT/shpack/packages" /shpack/packages \
    --ro-bind "$ROOT/distfiles"       /external/distfiles \
    --chdir /shpack \
    "$@"
