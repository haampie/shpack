#!/bin/sh

# Build the bootstrap rootfs for one target arch and run it under chroot.
#
#   ./build.sh amd64
#   ./build.sh aarch64
#
# Stages a fresh rootfs/ from the stage0-posix submodule (binary seeds +
# bootstrap scripts), adds the MES-replacement-specific seeds and sources,
# then runs kaem inside a chroot to execute the full bootstrap sequence.
#
# No host compilation is required: nothing under vendor/mes-replacement/ is
# compiled here. The committed files vendor/mes-replacement/tcc_cc.<arch>.sl64
# are the only MES-replacement-specific seeds (stack_c is compiled from C source
# by M2-Planet inside the chroot); everything else comes from the
# vendor/stage0-posix submodule (binary seeds + bring-up chain).
#
# aarch64 note: aarch64 binaries only run inside the chroot, so on an x86_64
# host register the qemu-aarch64 binfmt handler with the F (fix-binary) flag
# (qemu-user-static) before running this script.

set -ex

ARCH="$1"
# ARCH is the mescc-tools/M2libc/answers arch name AND the chroot ${ARCH} token
# (amd64, aarch64) - kept identical so the step scripts' single ${ARCH} resolves
# everywhere. Only the stage0-posix/bootstrap-seeds directory uses an uppercase
# spelling, mapped separately via S0ARCH/SEEDARCH.
case "$ARCH" in
    amd64)
        SEEDARCH=AMD64          # bootstrap-seeds/POSIX/<SEEDARCH> + stage0-posix dir
        S0ARCH=AMD64
        TCC_ARCH_FLAG=-64       # tcc_cc target-selection flag
        ;;
    aarch64)
        SEEDARCH=AArch64
        S0ARCH=AArch64
        TCC_ARCH_FLAG='-a aarch64'
        ;;
    *)
        echo "usage: $0 <amd64|aarch64>" >&2
        exit 1
        ;;
esac

# The absolute roots baked into the staged kaem scripts (the @TOKEN@ values).
# The sandboxed build keeps live-bootstrap's layout: store at /opt, distfiles
# bind-mounted at /external/distfiles, the seed tree at /tmp/seed, kaem TMPDIR at
# /tmp, shpack at /shpack -- all virtual paths inside the bound rootfs. The
# chroot-free build-host.sh overrides these with real host paths. derive_paths
# fills T_SEED_PATH (seed-tool dirs) and T_BASEPATH (shell-phase PATH floor) from
# the store, so a relocated store relocates both. (stage.sh, sourced below,
# defines derive_paths/subst/stage_*; the version numbers in T_SEED_PATH must
# match the staged stage0-posix submodules.)
T_STORE=/opt
T_DISTFILES=/external/distfiles
T_SEEDDIR=/tmp/seed
T_BUILDDIR=/tmp
T_SHPACK=/shpack
T_SH_LINK_DIR=/bin            # dash installs /bin/sh inside the chroot

# Parallelism for the shell-phase package builds (make -j${JOBS}). The kaem phase
# (tcc/musl) is serial regardless. Defaults to the host core count; override with
# JOBS=N ./build.sh ...
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 1)}"

# Shared rootless-bwrap launcher (also used by run.sh). It RAM-backs the
# throwaway per-package build scratch (/tmp/shpack/stage) on tmpfs unconditionally:
# the gcc/glibc stages churn thousands of short-lived .o's deleted at install, so
# skipping that disk I/O is always worth it (logs/stamps and the /opt store stay
# on disk).
. "$(dirname "$0")/sandbox.sh"

# Shared staging (subst/derive_paths/stage_seed_tree/stage_shpack), used by both
# this launcher and build-host.sh. derive_paths fills T_SEED_PATH/T_BASEPATH from
# the store root set above.
. "$(dirname "$0")/stage.sh"
derive_paths "$T_STORE"

# Delete existing rootfs
rm -rf rootfs

# --- Seed working tree ---------------------------------------------------
# The stage0-posix bring-up scripts are CWD-relative (./AArch64/..., ./M2libc/...)
# and the seed interpreters (kaem-optional-seed, kaem-0) have no `cd`, so the
# whole seed tree must sit at the launch CWD. We launch from /tmp/seed (the
# runner sets the working directory there -- bwrap --chdir, or unshare --wd for
# the chroot path), which keeps the rootfs root clean: only the persistent store
# (/opt), shpack and distfiles live at root. Everything the seed phase touches --
# the stage0 tree, our C sources, the per-arch check assets -- stages under
# /tmp/seed and is throwaway once the seed tools are installed into /opt.
# (live-bootstrap launches the same seed as init at /, so its root carries this
# same stage0 clutter; relocating the CWD is what lets us avoid it.)
mkdir -p rootfs
SEEDROOT=rootfs/tmp/seed

# Stage the stage0-posix seed working tree (binary seeds, M2libc/mescc-tools,
# our tcc_cc/stack_c sources, the substituted after.kaem + check-tools.kaem) and
# update the staged answers' kaem hash. Shared with build-host.sh; see stage.sh.
stage_seed_tree "${SEEDROOT}"

mkdir -p rootfs/usr
mkdir -p rootfs/usr/bin
mkdir -p rootfs/tmp

# --- shpack: bake only the kaem-phase base, not the package manager ------
# Provisioning bakes only what the kaem phase needs: bootstrap/ (the static
# kaem-phase chain) plus the substituted config/externals. The full chain runs
# (no truncate), ending by handing off to shpack. bootstrap/ also holds the glue
# kaem scripts (check-tools.kaem, stage0-hook.kaem); they go unused under
# rootfs/shpack/bootstrap/ -- the live copies are the subst outputs in the seed
# tree (rootfs/.../after.kaem, .../check-tools.kaem).
#
# shpack/{bin,lib,packages} are deliberately NOT baked: the launcher (run.sh)
# bind-mounts them live over this base, so recipe edits take effect without a
# re-provision. etc/config IS baked (its @ARCH@/@BASEPATH@ tokens are host- and
# arch-specific; changing them requires a re-provision anyway).
stage_shpack rootfs/shpack

# distfiles are bind-mounted read-only at run time (here and in run.sh), never
# copied into rootfs -- this is just the mountpoint. Run ./fetch-distfiles.sh
# first to populate the host distfiles/ (sources are not committed).
mkdir -p rootfs/external/distfiles

# --- Provision: run the kaem chain over the seed tree --------------------
# The seed tree lives at /tmp/seed and its scripts are CWD-relative, so we land
# the sandbox there with --chdir. Rootless bwrap (see sandbox.sh) needs
# unprivileged user namespaces; on Ubuntu these are AppArmor-gated and bwrap
# ships a profile that permits them. distfiles are bind-mounted read-only: the
# kaem bootstrap scripts read their source tarballs from /external/distfiles.
# aarch64 relies on the qemu-aarch64 binfmt handler being registered with the F
# flag, so it fires inside the namespace.
SEED=/tmp/seed/bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed

sandbox "$PWD/rootfs" \
    --ro-bind "$PWD/distfiles" /external/distfiles \
    --chdir /tmp/seed \
    "$SEED" kaem.${ARCH}

# The base is ready: dash + the kaem-phase /opt tools exist, so shpack is
# runnable over this rootfs. Unless asked to stop at the base, chain the
# launcher for the default target so `./build.sh <arch>` still yields a full
# gcc in one command. PROVISION_ONLY=1 leaves just the reusable base.
[ "${PROVISION_ONLY:-0}" = 1 ] || exec "$(dirname "$0")/run.sh" shpack install gcc
