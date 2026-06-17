#!/bin/sh
# SPDX-License-Identifier: MIT
#
# run-rootfs.sh -- bootstrap and run shpack inside a rootless bwrap sandbox
# that CHANGES ROOT: the staged rootfs/ is bind-mounted at / (hermetic, the host
# /usr is invisible). Contrast run-local.sh, which runs directly on the host
# with no root change. Both still sandbox each package build via shpack's own
# self-bootstrapped landlock sandbox -- the difference here is the chroot, not
# the per-build isolation.
#
#   ./run-rootfs.sh                    # provision if needed, then shpack install gcc
#   ./run-rootfs.sh --arch aarch64     # build for aarch64 (see the emulation note below)
#   ./run-rootfs.sh shpack install xz  # run a command over the existing base
#   ./run-rootfs.sh sh                 # interactive shell inside the rootfs
#   ./run-rootfs.sh --base-only        # provision the base, run nothing
#   ./run-rootfs.sh --clean            # force a fresh re-provision
#
# Idempotent: it (re)provisions the rootfs -- stage the stage0 seeds + run the
# kaem chain up to dash -- only when the base is missing or its provision stamp
# (arch + config + seeds, see stage.sh) no longer matches; otherwise it skips
# straight to running the command over the existing store (rootfs/opt/*), where
# only out-of-date dag.mk nodes rebuild. Run ./fetch-distfiles.sh first.
#
# Rootless bwrap (see in_rootfs below): no sudo, but needs unprivileged user namespaces.
# The store (rootfs/opt) and state (/tmp/shpack) are shared on disk, so run one
# build at a time -- two concurrent launches corrupt each other.
#
# aarch64 builds natively on an aarch64 host. On x86_64 it runs only under
# qemu-user emulation (the qemu-aarch64 binfmt `F` handler firing in the
# namespace) -- a dependency on an untrusted binary, so it is a testing
# convenience, not a real bootstrap. We do not cross-compile.

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

die() { echo "run-rootfs.sh: $*" >&2; exit 1; }

usage="usage: $0 [--arch amd64|aarch64] [--clean] [--base-only] [cmd...]"
ARCH=""
CLEAN=0
BASE_ONLY=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch)      [ "$#" -ge 2 ] || die "$usage"; ARCH=$2; shift 2 ;;
        --clean)     CLEAN=1; shift ;;
        --base-only) BASE_ONLY=1; shift ;;
        --)          shift; break ;;
        -*)          die "$usage" ;;
        *)           break ;;          # first non-flag begins the command
    esac
done

# ARCH defaults to the host; accept the uname spellings and normalise to the
# mescc-tools/chroot token (amd64, aarch64). SEEDARCH/S0ARCH spell it for the
# stage0-posix dirs; TCC_ARCH_FLAG selects the tcc_cc target.
[ -n "$ARCH" ] || ARCH=$(uname -m)
case "$ARCH" in
    amd64|x86_64)  ARCH=amd64;   SEEDARCH=AMD64;   S0ARCH=AMD64;   TCC_ARCH_FLAG=-64 ;;
    aarch64|arm64) ARCH=aarch64; SEEDARCH=AArch64; S0ARCH=AArch64; TCC_ARCH_FLAG='-a aarch64' ;;
    *) die "unsupported arch: $ARCH (want amd64 or aarch64)" ;;
esac

# Parallelism for the shell-phase package builds (make -j${JOBS}); the kaem phase
# is serial regardless. Override with JOBS=N ./run-rootfs.sh ...
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 1)}"

# Shared staging (subst/derive_paths/stage_*). See stage.sh.
. "$ROOT/stage.sh"

# in_rootfs ROOTFS [bwrap-arg...] -- run a command in a rootless bwrap namespace
# with ROOTFS bound at / (the change of root that defines this launcher), plus
# /dev, /proc and a RAM-backed build-scratch tmpfs. Everything after ROOTFS (the
# caller's extra binds, --chdir, command and args) is passed straight to bwrap.
# Rootless (unprivileged user namespaces), so no sudo. NB: distinct from the
# landlock "sandbox" (sandbox-1.0) that wraps each individual package build.
in_rootfs() {
    local rootfs
    rootfs=$1
    shift
    bwrap --unshare-all --bind "$rootfs" / --dev /dev --proc /proc \
        --tmpfs /tmp/shpack/stage "$@"
}

# Token roots baked into the staged kaem scripts. The rootfs keeps live-bootstrap's
# layout: store at /opt, distfiles at /external/distfiles, seed tree at /tmp/seed,
# kaem TMPDIR at /tmp, shpack at /shpack -- all virtual paths inside the bound
# rootfs. (run-local.sh substitutes real host paths instead.)
T_STORE=/opt
T_DISTFILES=/external/distfiles
T_SEEDDIR=/tmp/seed
T_BUILDDIR=/tmp
T_SHPACK=/shpack
derive_paths "$T_STORE"

[ -d "$ROOT/distfiles" ] || die "no distfiles at $ROOT/distfiles -- run ./fetch-distfiles.sh first"

# --- Provision (idempotent) ---------------------------------------------------
# The provision stamp records arch + config + seed fingerprint (stage.sh). When
# it still matches we reuse the rootfs as-is; otherwise rebuild it from scratch.
STAMP=rootfs/opt/.provisioned
want=$(provision_stamp)
if [ "$CLEAN" = 1 ] || [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$want" ]; then
    echo "run-rootfs.sh: provisioning rootfs/ for $ARCH ..."
    rm -rf rootfs
    mkdir -p rootfs/usr/bin rootfs/tmp rootfs/external/distfiles

    # The stage0 bring-up scripts are CWD-relative and the seed interpreters have
    # no `cd`, so the seed tree must sit at the launch CWD. We stage it at
    # /tmp/seed (launched with --chdir below) to keep the rootfs root clean: only
    # the persistent store (/opt), shpack and distfiles live at root.
    stage_seed_tree rootfs/tmp/seed

    # Bake only the kaem-phase base: bootstrap/ (the static kaem chain) plus the
    # substituted config/externals. shpack/{bin,lib,packages} are deliberately
    # NOT baked -- the launch step below bind-mounts them live so recipe edits
    # take effect without a re-provision. etc/config IS baked (its tokens are
    # host- and arch-specific).
    stage_shpack rootfs/shpack

    # Run the kaem chain over the seed tree, in a rootless bwrap namespace with
    # the rootfs bound at /. distfiles are bind-mounted read-only (the bootstrap
    # scripts read their tarballs from /external/distfiles). aarch64 on an x86_64
    # host relies on the qemu-aarch64 binfmt handler (user-mode emulation) firing
    # inside the namespace.
    SEED=/tmp/seed/bootstrap-seeds/POSIX/${SEEDARCH}/kaem-optional-seed
    in_rootfs "$ROOT/rootfs" \
        --ro-bind "$ROOT/distfiles" /external/distfiles \
        --chdir /tmp/seed \
        "$SEED" kaem.${ARCH}

    # stage0 doesn't propagate a nested kaem failure as its own exit status, so
    # assert the deliverable (dash) rather than trusting $?.
    [ -x rootfs/opt/dash-0.5.12/bin/sh ] \
        || die "kaem base failed: no rootfs/opt/dash-0.5.12/bin/sh (see output above)"
    printf '%s\n' "$want" > "$STAMP"
else
    echo "run-rootfs.sh: base present ($ARCH) -- skipping provision (--clean to rebuild)"
fi

# The `shpack` launcher wrapper, written into the rootfs store (virtual /opt) so
# it is on BASEPATH (shpack-driver/bin). Its store-dash shebang + body exec the
# bind-mounted live driver at /shpack/bin, so nothing relies on a #!/bin/sh
# shebang -- the reason the rootfs no longer carries a /bin/sh. The on-disk path
# is rootfs/opt/..., but its contents reference the virtual /opt and /shpack.
stage_driver_wrapper "$ROOT/rootfs/opt/shpack-driver/bin" \
    "/opt/dash-0.5.12/bin/sh" "/shpack/bin"

[ "$BASE_ONLY" = 1 ] && exit 0

# --- Launch -------------------------------------------------------------------
# Default to building the toolchain; otherwise run the given command (shpack
# resolves via the wrapper on BASEPATH, so `shpack install xz`, `sh`, etc. work).
[ "$#" -gt 0 ] || set -- shpack install gcc

# PATH floor handed to shpack: the BASEPATH the kaem phase baked into the config.
BP=$(sed -n 's/^BASEPATH=//p' rootfs/shpack/etc/config | head -1)

# Bind the package manager + distfiles read-only from the host checkout. Only
# /shpack/{bin,lib,packages} are mounted; /shpack/{etc,bootstrap} come from the
# baked base, so the substituted etc/config is preserved. shpack writes only
# under /tmp/shpack and the /opt store. --clearenv so the host environment never
# reaches a build.
in_rootfs "$ROOT/rootfs" \
    --clearenv \
    --setenv PATH "$BP" \
    --setenv HOME /tmp \
    --setenv TERM "${TERM:-dumb}" \
    --ro-bind "$ROOT/shpack/bin"      /shpack/bin \
    --ro-bind "$ROOT/shpack/lib"      /shpack/lib \
    --ro-bind "$ROOT/shpack/packages" /shpack/packages \
    --ro-bind "$ROOT/distfiles"       /external/distfiles \
    --chdir /shpack \
    "$@"
