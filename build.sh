#!/bin/sh

# Build the bootstrap rootfs for one target arch and run it under chroot.
#
#   ./build.sh amd64
#   ./build.sh arm64
#
# Stages a fresh rootfs/ from the stage0-posix submodule (binary seeds +
# bootstrap scripts), adds the MES-replacement-specific seeds and sources,
# then runs kaem inside a chroot to execute the full bootstrap sequence.
#
# No host compilation is required: `make -C src` is NOT called here.
# The committed files src/tcc_cc.<arch>.sl64 and src/stack_c_<arch>.M1_<arch>
# are the only MES-replacement-specific seeds; everything else comes from
# the stage0-posix and bootstrap-seeds submodules.
#
# arm64 note: aarch64 binaries only run inside the chroot, so on an x86_64
# host register the qemu-aarch64 binfmt handler with the F (fix-binary) flag
# (qemu-user-static) before running this script.

set -ex

ARCH="$1"
case "$ARCH" in
    amd64)
        SEEDARCH=AMD64          # bootstrap-seeds/POSIX/<SEEDARCH>
        S0ARCH=AMD64            # stage0-posix arch directory name
        M1ARCH=amd64            # M1 --architecture flag value
        M2ARCH=amd64            # M2libc arch subdirectory
        ;;
    arm64)
        SEEDARCH=AArch64
        S0ARCH=AArch64
        M1ARCH=aarch64
        M2ARCH=aarch64
        ;;
    *)
        echo "usage: $0 <amd64|arm64>" >&2
        exit 1
        ;;
esac

# Delete existing rootfs
rm -rf rootfs

# ── Stage0-posix tree ─────────────────────────────────────────────────────
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

# Checksum file that stage0-posix's kaem.run verifies after building tools
cp -f stage0-posix/${M1ARCH}.answers rootfs/

# We bump kaem's MAX_ARRAY above, which changes the kaem binary, so update its
# expected hash in the staged answers file (amd64 only; the hash is build-specific).
if [ "$ARCH" = amd64 ]; then
    sed -i 's|^[0-9a-f]\{64\}  AMD64/bin/kaem$|dc1a41453eeca57018f7d582f28c45dc5bdc10efac6840566ff3393da57b48fb  AMD64/bin/kaem|' rootfs/${M1ARCH}.answers
fi

# stage0-posix entry point (kaem-optional-seed runs this)
cp -f stage0-posix/kaem.${M1ARCH} rootfs/kaem.${ARCH}

# Our hook: replaces stage0-posix's placeholder after.kaem
cp -f target_${ARCH}/stage0-hook.kaem rootfs/after.kaem

# ── MES-replacement arch directory ────────────────────────────────────────
mkdir -p rootfs/${ARCH}

cp -f -t rootfs/${ARCH} \
    target_${ARCH}/check-tools.kaem \
    target_${ARCH}/after.kaem

# Committed seeds (our unique tcc_cc/stack_c layer).
# amd64 compiles stack_c from C source via M2-Planet, so it needs no committed
# stack_c.M1 seed; arm64 still bootstraps stack_c from its committed seed.
cp -f src/stack_c_intro_${ARCH}.M1    rootfs/${ARCH}/stack_c_intro.M1
if [ "$ARCH" = arm64 ]; then
    cp -f src/stack_c_${ARCH}.M1_${ARCH}  rootfs/${ARCH}/stack_c.M1
fi

# ── Generic C sources ─────────────────────────────────────────────────────
mkdir -p rootfs/src
cp -f -t rootfs/src \
    src/stdlib.c \
    src/bootstrappable.c \
    src/sys_syscall.h \
    src/tcc_cc.${ARCH}.sl64 \
    src/configurator.c \
    src/script-generator.c \
    src/equal.c \
    src/tcc_cc.c \
    src/stack_c_${ARCH}.c

# arm64 also needs its asm backend and alloca helper (referenced by stack_c_arm64.c)
if [ "$ARCH" = arm64 ]; then
    cp -f -t rootfs/src \
        src/arm64-asm.c \
        src/alloca-arm64.S
fi

# ── Script and step support ────────────────────────────────────────────────
cp -f target_${ARCH}/seed.kaem rootfs/
cp -f target_${ARCH}/configurator.${ARCH}.checksums rootfs/
cp -f target_${ARCH}/script-generator.${ARCH}.checksums rootfs/

mkdir -p rootfs/usr
mkdir -p rootfs/usr/bin
mkdir -p rootfs/tmp

cp -r steps rootfs/
cp -f target_${ARCH}/bootstrap.cfg rootfs/steps

mkdir -p rootfs/external
cp -r distfiles rootfs/external/

# ── Execute in chroot ──────────────────────────────────────────────────────
sudo chroot --userspec=$(id -u):$(id -g) rootfs \
    /bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed kaem.${ARCH}
