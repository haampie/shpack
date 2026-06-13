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
# No host compilation is required: `make -C src` is NOT called here.
# The committed files src/tcc_cc.<arch>.sl64 are the only MES-replacement-specific
# seeds (stack_c is compiled from C source by M2-Planet inside the chroot);
# everything else comes from the stage0-posix and bootstrap-seeds submodules.
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

# PATH to the seed tools' per-package /opt prefixes (a Spack-style store, like the
# rest of the build). The stage0-posix seed tools are split by their upstream
# package + version, plus our two unique seeds (tcc_cc, stack_c). The kaem-phase
# scripts reference every seed tool by bare name and resolve it through this PATH
# (set once in seed.kaem/after.kaem, inherited by every child kaem and 0.sh); the
# shell phase rebuilds PATH from /opt/*/bin and picks these up automatically.
# The version numbers must match the staged stage0-posix submodules (mescc-tools,
# mescc-tools-extra, M2-Mesoplanet) - bump here when those are updated.
SEED_PATH="/opt/mescc-tools-1.7.0/bin:/opt/mescc-tools-extra-1.4.0/bin:/opt/M2-Mesoplanet-1.13.0/bin:/opt/tcc_cc/bin:/opt/stack_c/bin"

# The PATH floor for the shell phase (shpack/etc/config BASEPATH): every
# kaem-phase /opt prefix, newest first, then the seed prefixes. The kaem
# phase is the fixed chain in shpack/bootstrap/0.kaem, so it is known here.
BASEPATH="/opt/dash-0.5.12/bin:/opt/coreutils-5.0/bin:/opt/bzip2-1.0.8/bin:/opt/sed-4.0.9/bin:/opt/tar-1.12/bin:/opt/gzip-1.2.4/bin:/opt/patch-2.5.9/bin:/opt/make-3.82/bin:/opt/tcc-0.9.27/bin:/opt/musl-1.1.24/bin:/opt/tcc-0.9.26/bin:/opt/simple-patch-1.0/bin:${SEED_PATH}"

# Parallelism for the shell-phase package builds (make -j${JOBS}). The kaem phase
# (tcc/musl) is serial regardless. Defaults to the host core count; override with
# JOBS=N ./build.sh ...
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 1)}"

# The kaem scripts and bootstrap.cfg in target/ are shared between arches;
# instantiate them by replacing the @ARCH@/@S0ARCH@/@TCC_ARCH_FLAG@ tokens.
# (Host sed, like the host cp/mkdir used below, is part of the staging step,
# not of the in-chroot bootstrap.)
subst() {
    sed -e "s|@ARCH@|${ARCH}|g" \
        -e "s|@S0ARCH@|${S0ARCH}|g" \
        -e "s|@TCC_ARCH_FLAG@|${TCC_ARCH_FLAG}|g" \
        -e "s|@JOBS@|${JOBS}|g" \
        -e "s|@SEED_PATH@|${SEED_PATH}|g" \
        -e "s|@BASEPATH@|${BASEPATH}|g" \
        "$1" > "$2"
}

# Delete existing rootfs
rm -rf rootfs

# --- Stage0-posix tree ---------------------------------------------------
# Copy the stage0-posix subtree into rootfs root, matching the layout that
# stage0-posix's own kaem scripts expect (paths like ./AMD64/..., ./M2libc/...).

mkdir -p rootfs

# Binary seeds
mkdir -p rootfs/bootstrap-seeds
cp -rf stage0-posix/bootstrap-seeds/. rootfs/bootstrap-seeds/

# Arch-specific bootstrap scripts and hex0/M1 sources
cp -rf stage0-posix/${S0ARCH} rootfs/${S0ARCH}

# Shared source trees referenced by stage0-posix scripts
cp -rf stage0-posix/M2libc       rootfs/M2libc
cp -rf stage0-posix/M2-Planet    rootfs/M2-Planet
cp -rf stage0-posix/mescc-tools  rootfs/mescc-tools
cp -rf stage0-posix/mescc-tools-extra rootfs/mescc-tools-extra
cp -rf stage0-posix/M2-Mesoplanet rootfs/M2-Mesoplanet

# Bump kaem's MAX_ARRAY (tokens per command) on the staged copy only, leaving the
# stage0-posix submodule pristine. The musl full-libc `ar` line lists ~1260 object
# files in one command (tcc's -ar recreates the archive each call, so it can't be
# split), which overflows the stock limit of 512.
sed -i 's/^#define MAX_ARRAY .*/#define MAX_ARRAY 4096/' rootfs/mescc-tools/Kaem/kaem.h

# kaem micro-optimizations (staged copy only, submodule stays pristine): use
# access() instead of slurping each candidate binary in find_executable, and
# trim the per-token MAX_STRING zeroing in list_to_array. No produced artifact
# changes; this only speeds up kaem's own per-command work.
patch -p1 -d rootfs/mescc-tools < target/kaem-perf.patch

# Checksum file that stage0-posix's kaem.run verifies after building tools
cp -f stage0-posix/${ARCH}.answers rootfs/

# We bump kaem's MAX_ARRAY above, which changes the kaem binary, so update its
# expected hash in the staged answers file. The hash is build-specific (depends
# on the resulting kaem binary), one per arch.
if [ "$ARCH" = amd64 ]; then
    sed -i 's|^[0-9a-f]\{64\}  AMD64/bin/kaem$|05e72a2fae51a1cb626815e87f3a5b35f0a3c818656efe73f04286b06742a5b1  AMD64/bin/kaem|' rootfs/${ARCH}.answers
elif [ "$ARCH" = aarch64 ]; then
    sed -i 's|^[0-9a-f]\{64\}  AArch64/bin/kaem$|1dcef6f99ae10f2805e2693746931089545a4e487c8934c5a9ca109d559580ac  AArch64/bin/kaem|' rootfs/${ARCH}.answers
fi

# stage0-posix entry point (kaem-optional-seed runs this)
cp -f stage0-posix/kaem.${ARCH} rootfs/kaem.${ARCH}

# Our hook: replaces stage0-posix's placeholder after.kaem
subst target/stage0-hook.kaem rootfs/after.kaem

# --- MES-replacement arch directory --------------------------------------
mkdir -p rootfs/${ARCH}

subst target/check-tools.kaem rootfs/${ARCH}/check-tools.kaem

# The reproducibility pin checked by check-tools.kaem (sha256 of the committed
# tcc_cc seed, against the freshly rebuilt /tmp/tcc_cc.sl64).
cp -f src/tcc_cc.${ARCH}.sl64.sha256 rootfs/${ARCH}/tcc_cc.sl64.sha256

# Committed seeds (our unique tcc_cc/stack_c layer).
# Both arches compile stack_c from C source via M2-Planet, so there is no
# committed stack_c.M1 seed; only the stack_c intro/prelude is staged.
cp -f src/stack_c_intro_${ARCH}.M1    rootfs/${ARCH}/stack_c_intro.M1

# --- Generic C sources ---------------------------------------------------
mkdir -p rootfs/src
cp -f -t rootfs/src \
    src/stdlib.c \
    src/bootstrappable.c \
    src/sys_syscall.h \
    src/tcc_cc.${ARCH}.sl64 \
    src/tcc_cc.c \
    src/stack_c_${ARCH}.c

# aarch64 also needs its asm backend and alloca helper (tcc-0.9.26 assets)
if [ "$ARCH" = aarch64 ]; then
    cp -f -t rootfs/src \
        src/aarch64-asm.c \
        src/alloca-aarch64.S
fi

mkdir -p rootfs/usr
mkdir -p rootfs/usr/bin
mkdir -p rootfs/tmp

# --- shpack: the package manager (see shpack/README.md) -------------------
# bootstrap/ is the static kaem-phase chain; 0.kaem.in is instantiated with
# the host-known config (this replaces live-bootstrap's in-chroot
# configurator + script-generator).
mkdir -p rootfs/shpack/etc
cp -r shpack/bin shpack/lib shpack/packages shpack/bootstrap rootfs/shpack/
subst shpack/bootstrap/0.kaem.in rootfs/shpack/bootstrap/0.kaem
rm -f rootfs/shpack/bootstrap/0.kaem.in
subst shpack/etc/config.in rootfs/shpack/etc/config
cp -f shpack/etc/externals.in rootfs/shpack/etc/externals

mkdir -p rootfs/external
cp -r distfiles rootfs/external/

# --- Execute the bootstrap -----------------------------------------------
# Run rootfs as / via rootless bubblewrap (default), or the original sudo chroot
# (RUNNER=chroot, or when bwrap is missing). Both run as the real, non-root uid:
# nothing in the chain needs privilege, and staying non-root keeps GNU tar from
# trying to restore archive ownership (which fails in bwrap's single-uid userns).
# aarch64 relies on the qemu-aarch64 binfmt handler being registered with the F
# flag, so it fires inside the namespace without qemu present in rootfs.
SEED=/bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed
RUNNER="${RUNNER:-$(command -v bwrap >/dev/null 2>&1 && echo bwrap || echo chroot)}"

case "$RUNNER" in
    bwrap)  bwrap --unshare-all --bind rootfs / --dev /dev --proc /proc --chdir / \
                "$SEED" kaem.${ARCH} ;;
    chroot)
        # Plain chroot leaves the rootfs with no /dev. The build framework's
        # fn_exists() (steps/helpers.sh) probes functions with
        # `command -v NAME 2>/dev/null`; with no /dev/null that redirect fails,
        # fn_exists returns false for every name, and each package's custom
        # src_* stage is silently skipped in favour of the default (e.g.
        # diffutils loses its `touch config.h` and fails on #include <config.h>).
        # Mirror bwrap's `--dev /dev` with a minimal device set, then remove it:
        # the nodes are root-owned, so leaving them would make the next non-root
        # `rm -rf rootfs` choke.
        sudo mkdir -p rootfs/dev
        sudo mknod -m 666 rootfs/dev/null    c 1 3
        sudo mknod -m 666 rootfs/dev/zero    c 1 5
        sudo mknod -m 666 rootfs/dev/full    c 1 7
        sudo mknod -m 666 rootfs/dev/random  c 1 8
        sudo mknod -m 666 rootfs/dev/urandom c 1 9
        sudo mknod -m 666 rootfs/dev/tty     c 5 0
        trap 'sudo rm -rf rootfs/dev' EXIT
        sudo chroot --userspec=$(id -u):$(id -g) rootfs "$SEED" kaem.${ARCH}
        sudo rm -rf rootfs/dev
        trap - EXIT
        ;;
    *)      echo "unknown RUNNER: $RUNNER (use bwrap or chroot)" >&2; exit 1 ;;
esac
