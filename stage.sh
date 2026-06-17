# SPDX-License-Identifier: MIT
#
# stage.sh -- shared rootfs/seed-tree staging, sourced by both launchers:
#   build-rootfs.sh  (sandboxed: stage under rootfs/, run the kaem chain via bwrap)
#   build-local.sh   (no sandbox: stage under a scratch dir, run natively)
#
# The two launchers differ only in WHERE the seed tree and the store live and
# HOW the kaem chain is launched. The staging itself -- which seed binaries and
# sources get copied where, and which @TOKEN@s are baked into the kaem scripts --
# is identical, so it lives here and can't drift between the two paths.
#
# The caller must run these functions from the repo root (they reference
# vendor/... and shpack/... by relative path) and must first set, as the values
# baked into the staged kaem scripts (the @TOKEN@ right-hand sides):
#   ARCH SEEDARCH S0ARCH TCC_ARCH_FLAG JOBS  -- arch identity (see each launcher)
#   T_STORE      -- store prefix root        (@STORE@,    e.g. /opt or $PWD/store)
#   T_DISTFILES  -- distfiles dir            (@DISTFILES@)
#   T_SEEDDIR    -- seed working-tree root   (@SEEDDIR@)
#   T_BUILDDIR   -- kaem TMPDIR / scratch    (@BUILDDIR@)
#   T_SHPACK     -- shpack tree root         (@SHPACK@)
# derive_paths "$T_STORE" then fills T_SEED_PATH / T_BASEPATH from the store.

# provision_stamp -- echo a fingerprint of everything that, per the design,
# requires a re-provision when it changes: the target arch, the resolved token
# roots baked into the staged base, and the provisioning input templates. The
# launchers save this beside the store (.provisioned) and re-provision when it
# no longer matches. Host sha256sum here (staging-time, not the in-sandbox tool
# budget that constrains shpack core). Caller runs from the repo root.
provision_stamp() {
    printf 'arch=%s store=%s seeddir=%s shpack=%s distfiles=%s\n' \
        "$ARCH" "$T_STORE" "$T_SEEDDIR" "$T_SHPACK" "$T_DISTFILES"
    sha256sum shpack/etc/config.in shpack/etc/externals.in shpack/bootstrap/0.kaem.in
}

# derive_paths STORE -- compute the seed-tool PATH and the shell-phase PATH floor
# from a store root, so a relocated store relocates both PATHs with it. Mirrors
# the chain order baked into 0.kaem (kaem-phase /opt prefixes, newest first, then
# the stage0 seed prefixes).
derive_paths() {
    local S="$1"
    T_SEED_PATH="${S}/mescc-tools-1.7.0/bin:${S}/mescc-tools-extra-1.4.0/bin:${S}/M2-Mesoplanet-1.13.0/bin:${S}/tcc_cc/bin:${S}/stack_c/bin"
    # shpack-driver/bin holds the `shpack` launcher wrapper (stage_driver_wrapper):
    # both launchers expose it here so a dropped-in shell can run `shpack` by name.
    T_BASEPATH="${S}/shpack-driver/bin:${S}/dash-0.5.12/bin:${S}/coreutils-5.0/bin:${S}/bzip2-1.0.8/bin:${S}/sed-4.0.9/bin:${S}/tar-1.12/bin:${S}/gzip-1.2.4/bin:${S}/patch-2.5.9/bin:${S}/make-3.82/bin:${S}/tcc-0.9.27/bin:${S}/musl-1.1.24/bin:${S}/tcc-0.9.26/bin:${S}/simple-patch-1.0/bin:${T_SEED_PATH}"
}

# stage_driver_wrapper DEST_DIR STORE_DASH DRIVER_BIN -- write the `shpack`
# launcher wrapper into DEST_DIR. Both the shebang and the body name STORE_DASH
# explicitly, so the host /bin/sh is never resolved (the driver's own #!/bin/sh
# shebang is bypassed); DRIVER_BIN/shpack is the live driver checkout. DEST_DIR
# is an on-disk path that may differ from the in-content absolute paths (under
# chroot the file lands at rootfs/opt/... but must reference the virtual /opt).
stage_driver_wrapper() {
    mkdir -p "$1"
    printf '#!%s\nexec %s %s/shpack "$@"\n' "$2" "$2" "$3" > "$1/shpack"
    chmod 755 "$1/shpack"
}

# subst SRC DST -- instantiate one @TOKEN@ template. Host sed (part of staging,
# not of the in-chroot bootstrap), like the host cp/mkdir used below.
subst() {
    sed -e "s|@ARCH@|${ARCH}|g" \
        -e "s|@S0ARCH@|${S0ARCH}|g" \
        -e "s|@TCC_ARCH_FLAG@|${TCC_ARCH_FLAG}|g" \
        -e "s|@JOBS@|${JOBS}|g" \
        -e "s|@SEED_PATH@|${T_SEED_PATH}|g" \
        -e "s|@BASEPATH@|${T_BASEPATH}|g" \
        -e "s|@STORE@|${T_STORE}|g" \
        -e "s|@DISTFILES@|${T_DISTFILES}|g" \
        -e "s|@SEEDDIR@|${T_SEEDDIR}|g" \
        -e "s|@BUILDDIR@|${T_BUILDDIR}|g" \
        -e "s|@SHPACK@|${T_SHPACK}|g" \
        "$1" > "$2"
}

# stage_seed_tree SEEDROOT -- populate the stage0-posix seed working tree at
# SEEDROOT (the on-disk path that @SEEDDIR@ resolves to). The stage0 scripts are
# CWD-relative, so SEEDROOT is the directory the seed is launched FROM.
stage_seed_tree() {
    local SEEDROOT="$1"
    mkdir -p "${SEEDROOT}"

    # Binary seeds
    mkdir -p "${SEEDROOT}/bootstrap-seeds"
    cp -rf vendor/stage0-posix/bootstrap-seeds/. "${SEEDROOT}/bootstrap-seeds/"

    # Arch-specific bootstrap scripts and hex0/M1 sources
    cp -rf vendor/stage0-posix/${S0ARCH} "${SEEDROOT}/${S0ARCH}"

    # Shared source trees referenced by stage0-posix scripts
    cp -rf vendor/stage0-posix/M2libc            "${SEEDROOT}/M2libc"
    cp -rf vendor/stage0-posix/M2-Planet         "${SEEDROOT}/M2-Planet"
    cp -rf vendor/stage0-posix/mescc-tools       "${SEEDROOT}/mescc-tools"
    cp -rf vendor/stage0-posix/mescc-tools-extra "${SEEDROOT}/mescc-tools-extra"
    cp -rf vendor/stage0-posix/M2-Mesoplanet     "${SEEDROOT}/M2-Mesoplanet"

    # Vendored optimized kaem over the staged submodule copy (MAX_ARRAY=4096 etc.;
    # output byte-identical, gated on the musl libc.a sha256 -- see vendor/kaem).
    cp -f vendor/kaem/kaem.c vendor/kaem/kaem.h vendor/kaem/variable.c \
        "${SEEDROOT}/mescc-tools/Kaem/"

    # Checksum file that stage0-posix's kaem.run verifies after building tools
    cp -f vendor/stage0-posix/${ARCH}.answers "${SEEDROOT}/"

    # Our kaem differs from upstream, so update the expected kaem hash in the
    # staged answers file (build-specific, one per arch). NOTE: the amd64 hash is
    # stale -- recompute on an amd64 build; only aarch64 is verified here.
    if [ "$ARCH" = amd64 ]; then
        sed -i 's|^[0-9a-f]\{64\}  AMD64/bin/kaem$|64d530d91b1e47b4b4d645c98d6d8cd13a2871a5c45e502ed31e084c31a1f801  AMD64/bin/kaem|' "${SEEDROOT}/${ARCH}.answers"
    elif [ "$ARCH" = aarch64 ]; then
        sed -i 's|^[0-9a-f]\{64\}  AArch64/bin/kaem$|805bb0677242fc0e068b5b9ed71d24bb01d5de8a05ff0ed92061bbd0ab412101  AArch64/bin/kaem|' "${SEEDROOT}/${ARCH}.answers"
    fi

    # stage0-posix entry point (kaem-optional-seed runs this)
    cp -f vendor/stage0-posix/kaem.${ARCH} "${SEEDROOT}/kaem.${ARCH}"

    # Our hook: replaces stage0-posix's placeholder after.kaem
    subst shpack/bootstrap/stage0-hook.kaem "${SEEDROOT}/after.kaem"

    # MES-replacement arch directory (seed-phase check assets)
    mkdir -p "${SEEDROOT}/${ARCH}"
    subst shpack/bootstrap/check-tools.kaem "${SEEDROOT}/${ARCH}/check-tools.kaem"
    # The reproducibility pin checked by check-tools.kaem (sha256 of the committed
    # tcc_cc seed) and the stack_c intro/prelude.
    subst vendor/mes-replacement/tcc_cc.${ARCH}.sl64.sha256 "${SEEDROOT}/${ARCH}/tcc_cc.sl64.sha256"
    cp -f vendor/mes-replacement/stack_c_intro_${ARCH}.M1   "${SEEDROOT}/${ARCH}/stack_c_intro.M1"

    # Generic C sources
    mkdir -p "${SEEDROOT}/src"
    cp -f -t "${SEEDROOT}/src" \
        vendor/mes-replacement/stdlib.c \
        vendor/mes-replacement/bootstrappable.c \
        vendor/mes-replacement/sys_syscall.h \
        vendor/mes-replacement/tcc_cc.${ARCH}.sl64 \
        vendor/mes-replacement/tcc_cc.c \
        vendor/mes-replacement/stack_c_${ARCH}.c

    # aarch64 also needs its asm backend and alloca helper (tcc-0.9.26 assets)
    if [ "$ARCH" = aarch64 ]; then
        cp -f -t "${SEEDROOT}/src" \
            vendor/mes-replacement/aarch64-asm.c \
            vendor/mes-replacement/alloca-aarch64.S
    fi
}

# stage_shpack DEST -- stage the kaem-phase shpack base (bootstrap/ + the
# substituted config/externals) under DEST (the on-disk path @SHPACK@ resolves
# to). shpack/{bin,lib,packages} are deliberately NOT staged -- the launchers
# bind or point at the live host checkout for those.
stage_shpack() {
    local DEST="$1" f
    mkdir -p "${DEST}/etc"
    cp -r shpack/bootstrap "${DEST}/"
    subst shpack/bootstrap/0.kaem.in "${DEST}/bootstrap/0.kaem"
    rm -f "${DEST}/bootstrap/0.kaem.in"
    # Each package's sources.sha256 names its distfile by @DISTFILES@-prefixed
    # path (sha256sum -c verifies that exact path), so relocate them with the store.
    for f in "${DEST}"/bootstrap/*/sources.sha256; do
        subst "$f" "$f.tmp" && mv "$f.tmp" "$f"
    done
    # musl's shpack-shell fragments hardcode the store dash path (@STORE@) into
    # system()/popen() so sandboxed builds reach the store shell, not /bin/sh.
    for f in "${DEST}"/bootstrap/musl-1.1.24/shpack-shell/*.after; do
        subst "$f" "$f.tmp" && mv "$f.tmp" "$f"
    done
    subst shpack/etc/config.in    "${DEST}/etc/config"
    subst shpack/etc/externals.in "${DEST}/etc/externals"
}
