#!/bin/sh

# Build the bootstrap rootfs for one target arch and run it under chroot.
#
#   ./build.sh amd64
#   ./build.sh arm64
#
# Stages a fresh rootfs/ (seed binaries, per-arch tool artifacts, generic C
# sources, the steps/ tree and distfiles) and executes the kaem scripts inside
# a chroot to compile tcc-0.9.26 and tcc-0.9.27 for the target.
#
# arm64 note: its aarch64 artifacts can only run inside the chroot, so on an
# x86_64 host first register the qemu-aarch64 binfmt handler with the F
# (fix-binary) flag (qemu-user-static), and only the build half runs natively.

set -x

ARCH="$1"
case "$ARCH" in
    amd64)
        SEEDARCH=AMD64       # bootstrap-seeds/POSIX/<SEEDARCH>
        M2ARCH=amd64         # M2libc/<M2ARCH>/ELF-<M2ARCH>-debug.hex2
        MAKEGOAL=            # bare `make -C src` == default `all: x86 amd64`
        ;;
    arm64)
        SEEDARCH=AArch64
        M2ARCH=aarch64
        MAKEGOAL=arm64
        ;;
    *)
        echo "usage: $0 <amd64|arm64>" >&2
        exit 1
        ;;
esac

# Build sources
make -C src ${MAKEGOAL}

# Delete existing rootfs
rm -rf rootfs

# Create minimal directories
mkdir -p rootfs
mkdir -p rootfs/usr
mkdir -p rootfs/usr/bin
mkdir -p rootfs/tmp

# Create and fill bootstrap-seeds directory
mkdir -p rootfs/bootstrap-seeds/POSIX/${SEEDARCH}
cp -f src/kaem-minimal.${ARCH} rootfs/bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed
cp -f src/hex0.${ARCH}         rootfs/bootstrap-seeds/POSIX/${SEEDARCH}/hex0-seed

# Copy root kaem script
cp -f target_${ARCH}/kaem.${ARCH} rootfs/kaem.${ARCH}

# Create and fill the arch specific directory with scripts and source files
mkdir -p rootfs/${ARCH}
mkdir -p rootfs/${ARCH}/artifact
cp -f -t rootfs/${ARCH} \
    target_${ARCH}/tools-seed-kaem.kaem \
    target_${ARCH}/tools-mini-kaem.kaem \
    target_${ARCH}/check-tools.kaem \
    target_${ARCH}/tools-kaem.kaem \
    target_${ARCH}/after.kaem
# M2libc names the hex2 by its musl arch (amd64/aarch64); install it under the
# ${ARCH}=amd64/arm64 convention (a no-op rename for amd64).
cp -f M2libc/${M2ARCH}/ELF-${M2ARCH}-debug.hex2 rootfs/${ARCH}/ELF-${ARCH}-debug.hex2
cp -f src/hex0.${ARCH}_hex0            rootfs/${ARCH}/hex0.hex0
cp -f src/kaem-minimal.${ARCH}_hex0    rootfs/${ARCH}/kaem-minimal.hex0
cp -f src/hex2.${ARCH}_hex0            rootfs/${ARCH}/hex2.hex0
cp -f src/blood-elf.macro_${ARCH}      rootfs/${ARCH}/blood-elf.macro
cp -f src/blood-elf.blood_elf_${ARCH}  rootfs/${ARCH}/blood-elf.blood_elf
cp -f src/M1.macro_${ARCH}             rootfs/${ARCH}/M1.macro
cp -f src/M1.blood_elf_${ARCH}         rootfs/${ARCH}/M1.blood_elf
cp -f src/stack_c_${ARCH}.M1_${ARCH}   rootfs/${ARCH}/stack_c.M1
cp -f src/stack_c_intro_${ARCH}.M1     rootfs/${ARCH}/stack_c_intro.M1

# Create and fill directory for generic source files
mkdir -p rootfs/src
cp -f -t rootfs/src \
    src/stdlib.c \
    src/sys_syscall.h \
    src/tcc_cc.${ARCH}.sl64 \
    src/kaem.c \
    src/catm.c \
    src/bootstrappable.c \
    src/match.c \
    src/mkdir.c \
    src/cp.c \
    src/chmod.c \
    src/rm.c \
    src/untar.c \
    src/ungz.c \
    src/unxz.c \
    src/unbz2.c \
    src/sha256sum.c \
    src/configurator.c \
    src/script-generator.c \
    src/stack_c_interpreter.c

# arm64 also needs its asm->C backend and alloca helper
if [ "$ARCH" = arm64 ]; then
    cp -f -t rootfs/src \
        src/arm64-asm.c \
        src/alloca-arm64.S
fi

# Also add source files for checking
cp -f -t rootfs/src \
    src/equal.c \
    src/hex0.c \
    src/hex2.c \
    src/blood-elf.c \
    src/M1.c \
    src/stack_c_${ARCH}.c \
    src/tcc_cc.c \
    src/kaem-minimal.c

# Copy scripts for processing steps
cp -f target_${ARCH}/seed.kaem rootfs
cp -f target_${ARCH}/configurator.${ARCH}.checksums rootfs
cp -f target_${ARCH}/script-generator.${ARCH}.checksums rootfs

# Copy steps
cp -r steps rootfs
cp -f target_${ARCH}/bootstrap.cfg rootfs/steps

# Copy the necessary distribution files
mkdir rootfs/external
cp -r distfiles rootfs/external

# Execute kaem scripts in change root environment
sudo chroot --userspec=$(id -u):$(id -g) rootfs \
    /bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed kaem.${ARCH}

# Alternative with strace to generate trace.txt file that can be used
# to generate documentation with the help of scan_trace.cpp
#sudo strace -f -o trace.txt -e trace=open,openat,close,chmod,chdir,dup,fcntl,link,linkat,unlink,fork,execve chroot --userspec=$(id -u):$(id -g) rootfs /bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed kaem.${ARCH}
