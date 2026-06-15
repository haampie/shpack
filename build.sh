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

# Put the throwaway per-package build dir (/tmp/shpack/stage) on tmpfs: the gcc/
# glibc stages churn thousands of short-lived .o's that are deleted at install, so
# RAM-backing them skips the disk I/O (logs/stamps and the /opt store stay on
# disk). Default on; STAGE_TMPFS=0 for low-RAM hosts (peak footprint a few GB).
STAGE_TMPFS="${STAGE_TMPFS:-1}"

# The kaem glue scripts in shpack/bootstrap/ and the shpack config templates are
# shared between arches; instantiate them by replacing the
# @ARCH@/@S0ARCH@/@TCC_ARCH_FLAG@ tokens.
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
mkdir -p ${SEEDROOT}

# Binary seeds
mkdir -p ${SEEDROOT}/bootstrap-seeds
cp -rf vendor/stage0-posix/bootstrap-seeds/. ${SEEDROOT}/bootstrap-seeds/

# Arch-specific bootstrap scripts and hex0/M1 sources
cp -rf vendor/stage0-posix/${S0ARCH} ${SEEDROOT}/${S0ARCH}

# Shared source trees referenced by stage0-posix scripts
cp -rf vendor/stage0-posix/M2libc       ${SEEDROOT}/M2libc
cp -rf vendor/stage0-posix/M2-Planet    ${SEEDROOT}/M2-Planet
cp -rf vendor/stage0-posix/mescc-tools  ${SEEDROOT}/mescc-tools
cp -rf vendor/stage0-posix/mescc-tools-extra ${SEEDROOT}/mescc-tools-extra
cp -rf vendor/stage0-posix/M2-Mesoplanet ${SEEDROOT}/M2-Mesoplanet

# Drop in the vendored, optimized kaem over the staged submodule copy (the
# submodule stays pristine). vendor/kaem/ carries MAX_ARRAY=4096 (the musl
# full-libc `ar` line lists ~1260 objects in one command -- tcc's -ar recreates
# the archive each call, so it can't be split -- overflowing the stock 512) plus
# per-command token/string pools, an envp cache, and access()-based PATH probing
# that cut kaem's ~52 brk/command (M2libc malloc never frees and brks per call)
# toward ~0. Output is byte-identical (gated on the musl libc.a sha256); see the
# header comment in vendor/kaem/kaem.c.
cp -f vendor/kaem/kaem.c vendor/kaem/kaem.h vendor/kaem/variable.c ${SEEDROOT}/mescc-tools/Kaem/

# Checksum file that stage0-posix's kaem.run verifies after building tools
cp -f vendor/stage0-posix/${ARCH}.answers ${SEEDROOT}/

# Our kaem differs from upstream, so its binary hash differs; update the
# expected hash in the staged answers file. Build-specific (depends on the
# resulting kaem binary), one per arch. NOTE: the amd64 hash below is stale
# (left over from the previous patched kaem) -- recompute it on an amd64 build
# of the vendored kaem; only aarch64 is verified here.
if [ "$ARCH" = amd64 ]; then
    sed -i 's|^[0-9a-f]\{64\}  AMD64/bin/kaem$|64d530d91b1e47b4b4d645c98d6d8cd13a2871a5c45e502ed31e084c31a1f801  AMD64/bin/kaem|' ${SEEDROOT}/${ARCH}.answers
elif [ "$ARCH" = aarch64 ]; then
    sed -i 's|^[0-9a-f]\{64\}  AArch64/bin/kaem$|805bb0677242fc0e068b5b9ed71d24bb01d5de8a05ff0ed92061bbd0ab412101  AArch64/bin/kaem|' ${SEEDROOT}/${ARCH}.answers
fi

# stage0-posix entry point (kaem-optional-seed runs this)
cp -f vendor/stage0-posix/kaem.${ARCH} ${SEEDROOT}/kaem.${ARCH}

# Our hook: replaces stage0-posix's placeholder after.kaem
subst shpack/bootstrap/stage0-hook.kaem ${SEEDROOT}/after.kaem

# --- MES-replacement arch directory (seed-phase check assets) ------------
mkdir -p ${SEEDROOT}/${ARCH}

subst shpack/bootstrap/check-tools.kaem ${SEEDROOT}/${ARCH}/check-tools.kaem

# The reproducibility pin checked by check-tools.kaem (sha256 of the committed
# tcc_cc seed, against the freshly rebuilt /tmp/tcc_cc.sl64).
cp -f vendor/mes-replacement/tcc_cc.${ARCH}.sl64.sha256 ${SEEDROOT}/${ARCH}/tcc_cc.sl64.sha256

# Committed seeds (our unique tcc_cc/stack_c layer).
# Both arches compile stack_c from C source via M2-Planet, so there is no
# committed stack_c.M1 seed; only the stack_c intro/prelude is staged.
cp -f vendor/mes-replacement/stack_c_intro_${ARCH}.M1    ${SEEDROOT}/${ARCH}/stack_c_intro.M1

# --- Generic C sources ---------------------------------------------------
mkdir -p ${SEEDROOT}/src
cp -f -t ${SEEDROOT}/src \
    vendor/mes-replacement/stdlib.c \
    vendor/mes-replacement/bootstrappable.c \
    vendor/mes-replacement/sys_syscall.h \
    vendor/mes-replacement/tcc_cc.${ARCH}.sl64 \
    vendor/mes-replacement/tcc_cc.c \
    vendor/mes-replacement/stack_c_${ARCH}.c

# aarch64 also needs its asm backend and alloca helper (tcc-0.9.26 assets)
if [ "$ARCH" = aarch64 ]; then
    cp -f -t ${SEEDROOT}/src \
        vendor/mes-replacement/aarch64-asm.c \
        vendor/mes-replacement/alloca-aarch64.S
fi

mkdir -p rootfs/usr
mkdir -p rootfs/usr/bin
mkdir -p rootfs/tmp

# --- shpack: the package manager (see README.md) -------------------------
# bootstrap/ is the static kaem-phase chain; 0.kaem.in is instantiated with
# the host-known config (this replaces live-bootstrap's in-chroot
# configurator + script-generator). bootstrap/ also holds the two glue kaem
# scripts (check-tools.kaem, stage0-hook.kaem); the cp below copies them into
# rootfs/shpack/bootstrap/ where they go unused -- the live copies are the
# subst outputs above (rootfs/after.kaem, rootfs/${ARCH}/check-tools.kaem).
mkdir -p rootfs/shpack/etc
cp -r shpack/bin shpack/lib shpack/packages shpack/bootstrap rootfs/shpack/
subst shpack/bootstrap/0.kaem.in rootfs/shpack/bootstrap/0.kaem
rm -f rootfs/shpack/bootstrap/0.kaem.in
subst shpack/etc/config.in rootfs/shpack/etc/config
cp -f shpack/etc/externals.in rootfs/shpack/etc/externals

mkdir -p rootfs/external
# distfiles are not committed; run ./fetch-distfiles.sh first to populate them.
cp -r distfiles rootfs/external/

# --- Execute the bootstrap -----------------------------------------------
# The seed tree lives at /tmp/seed and its scripts are CWD-relative, so the
# runner must launch the seed with the working directory set there.
#  - bwrap (default, rootless): --chdir /tmp/seed. Needs unprivileged user
#    namespaces; on Ubuntu these are AppArmor-gated, and bwrap ships a profile
#    that permits them (a bare `unshare --map-root-user` does not).
#  - unshare (RUNNER=chroot, or when bwrap is missing): chroot(2) does not touch
#    CWD and coreutils `chroot` only offers `--skip-chdir` (restricted to
#    NEWROOT=/), so it cannot land on a subdir. `unshare --root=DIR --wd=SUBDIR`
#    does chroot then chdir in the right order; --setuid/--setgid then drop to
#    the real uid (so GNU tar's ownership restore maps to us, not root). It runs
#    under sudo because this path is for hosts without unprivileged userns.
# Both stay non-root inside. aarch64 relies on the qemu-aarch64 binfmt handler
# being registered with the F flag, so it fires inside the namespace.
SEED=/tmp/seed/bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed
RUNNER="${RUNNER:-$(command -v bwrap >/dev/null 2>&1 && echo bwrap || echo chroot)}"

# bwrap mounts the scratch tmpfs natively (namespaced, auto-created, writable as
# the sandbox user); the chroot path mounts it on the host below.
BWRAP_TMPFS=""
[ "$STAGE_TMPFS" = 1 ] && BWRAP_TMPFS="--tmpfs /tmp/shpack/stage"

case "$RUNNER" in
    bwrap)  bwrap --unshare-all --bind rootfs / --dev /dev --proc /proc \
                ${BWRAP_TMPFS} --chdir /tmp/seed \
                "$SEED" kaem.${ARCH} ;;
    chroot)
        # The chroot has no /dev, but shpack and the package configure scripts
        # redirect to /dev/null constantly (a missing /dev/null makes those
        # redirects fail). Provide a minimal device set, then remove it: the
        # nodes are root-owned, so leaving them would make the next non-root
        # `rm -rf rootfs` choke.
        sudo mkdir -p rootfs/dev rootfs/proc
        sudo mknod -m 666 rootfs/dev/null    c 1 3
        sudo mknod -m 666 rootfs/dev/zero    c 1 5
        sudo mknod -m 666 rootfs/dev/full    c 1 7
        sudo mknod -m 666 rootfs/dev/random  c 1 8
        sudo mknod -m 666 rootfs/dev/urandom c 1 9
        sudo mknod -m 666 rootfs/dev/tty     c 5 0
        # gmake is linked against musl 1.1.24, whose realpath() reads
        # /proc/self/fd; the kernel/glibc/gcc Makefiles that call $(realpath ...)
        # (e.g. linux-headers) return empty and misfire without /proc. (Only the
        # bwrap path got --proc; this unprivileged-userns-less path needs it too.)
        sudo mount -t proc proc rootfs/proc
        # Scratch tmpfs (mode 1777 for the --setuid non-root build); unmounted on
        # exit so the next run's `rm -rf rootfs` doesn't hit a live mount.
        if [ "$STAGE_TMPFS" = 1 ]; then
            mkdir -p rootfs/tmp/shpack/stage
            sudo mount -t tmpfs -o mode=1777 tmpfs rootfs/tmp/shpack/stage
        fi
        trap 'sudo umount rootfs/tmp/shpack/stage 2>/dev/null; sudo umount rootfs/proc 2>/dev/null; sudo rm -rf rootfs/dev rootfs/proc' EXIT
        sudo unshare --root=rootfs --wd=/tmp/seed \
             --setuid $(id -u) --setgid $(id -g) "$SEED" kaem.${ARCH}
        sudo umount rootfs/tmp/shpack/stage 2>/dev/null || true
        sudo umount rootfs/proc 2>/dev/null || true
        sudo rm -rf rootfs/dev rootfs/proc
        trap - EXIT
        ;;
    *)      echo "unknown RUNNER: $RUNNER (use bwrap or chroot)" >&2; exit 1 ;;
esac
