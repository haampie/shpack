#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# replay-host.sh -- reproduce, ON THE HOST (no chroot), the Task-4 bring-up of the
# musl-1.1.24 subset as the C library the bootstrap tcc links against, replacing
# GNU mes libc. See ../../LOG-MUSL.md for the narrative.
#
# What it does, end to end:
#   1. unpack pristine musl 1.1.24 and apply the three amd64 tcc-compat patches
#      (0006 [static N] declarators, 0030 r10/r8 syscall asm, 0040 SysV va_list);
#   2. pre-generate musl's three generated headers (alltypes/syscall/version) so
#      no sed/awk is needed at "real" bootstrap time -- here we DO use the host
#      sed once, to PRODUCE them;
#   3. build a gcc-hosted proxy of the bootstrap tcc 0.9.26 (tcc_proxy). gcc only
#      stands in for tcc_cc; the proxy is built from the SAME tcc 0.9.26 sources,
#      with the SAME -DBOOTSTRAP=1 defines as the real tcc_s, so the libc-side
#      compile/link errors it surfaces are faithful. (-DBOOTSTRAP=1 matters: it
#      disables tidy_section_headers(), whose absence in a non-bootstrap proxy
#      otherwise segfaults the static link.);
#   4. compile the musl subset (manifest + 3 extras + glue) into libc.a, build a
#      stripped crt1.o + empty crti/crtn + libtcc1.a (with alloca86_64.S);
#   5. compile tcc.c against the subset's PUBLIC headers (consumer include set --
#      NOT src/include or src/internal, whose hidden/weak macros collide with
#      tcc.h) into tcc_musl.o and link `tcc-musl`;
#   6. smoke-test: tcc-musl -v, then have it compile+link a hello world and run it.
#
# This is a CHECKPOINT / investigation harness, not the kaem boot step.
#
# Usage:  ./replay-host.sh [WORKDIR]        (default WORKDIR: /tmp/msb-replay)
#
# Env overrides (defaults are what was discovered on this host):
#   MUSL_TARBALL    pristine musl-1.1.24.tar.gz
#   TCC_SRC         tcc 0.9.26 source tree (any patch state; static-plt applied if missing)
#   PATCHDIR        dir holding the 0006/0030/0040 musl patches
#   TCC_STATIC_PLT  tcc-static-plt.patch
#   CC              host C compiler used to build the proxy (default: gcc)
set -eu

# --- locations -------------------------------------------------------------
HERE=$(cd "$(dirname "$0")" && pwd)            # steps/musl-1.1.24-subset
SPACK=/home/harmen/projects/bootstrap-glibc/bootstrap/spack_repo/bootstrap/packages

WORKDIR=${1:-/tmp/msb-replay}
MUSL_TARBALL=${MUSL_TARBALL:-/home/harmen/spack/var/spack/cache/_source-cache/archive/13/1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3.tar.gz}
TCC_SRC=${TCC_SRC:-/tmp/msb4/tcc-0.9.26-1147-gee75a10c}
PATCHDIR=${PATCHDIR:-$SPACK/bootstrap_musl_scaffold}
TCC_STATIC_PLT=${TCC_STATIC_PLT:-$SPACK/bootstrap_tcc_mes/tcc-static-plt.patch}
CC=${CC:-gcc}

VERSION=1.1.24
ARCH=x86_64

say()  { printf '\n=== %s ===\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$MUSL_TARBALL" ]   || die "musl tarball not found: $MUSL_TARBALL"
[ -d "$TCC_SRC" ]        || die "tcc source tree not found: $TCC_SRC"
[ -d "$PATCHDIR" ]       || die "patch dir not found: $PATCHDIR"
[ -f "$TCC_STATIC_PLT" ] || die "tcc-static-plt.patch not found: $TCC_STATIC_PLT"
[ -f "$HERE/amd64/musl-subset.files" ] || die "manifest not found: $HERE/amd64/musl-subset.files"

say "workdir $WORKDIR (fresh)"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ---------------------------------------------------------------------------
# 1. musl: unpack pristine + apply the three amd64 tcc-compat patches
# ---------------------------------------------------------------------------
say "unpack + patch musl $VERSION"
tar -xzf "$MUSL_TARBALL"
MUSL="$WORKDIR/musl-$VERSION"
[ -d "$MUSL" ] || die "unpacked tree not at $MUSL"
( cd "$MUSL"
  for p in 0006-Strip-C99-static-N-array-declarators.patch \
           0030-syscall-$ARCH.patch \
           0040-$ARCH-sysv-va_list.patch; do
      printf '  applying %s\n' "$p"
      patch -p1 --no-backup-if-mismatch < "$PATCHDIR/$p" >/dev/null
  done )

# ---------------------------------------------------------------------------
# 2. musl: pre-generate the three generated headers (from the PATCHED tree, so
#    alltypes.h carries the __musl_va_list_t form 0040 introduced)
# ---------------------------------------------------------------------------
say "generate musl headers (alltypes/syscall/version)"
( cd "$MUSL"
  mkdir -p obj/include/bits obj/src/internal
  sed -f tools/mkalltypes.sed \
      arch/$ARCH/bits/alltypes.h.in include/alltypes.h.in > obj/include/bits/alltypes.h
  cp arch/$ARCH/bits/syscall.h.in obj/include/bits/syscall.h
  sed -n 's/__NR_/SYS_/p' arch/$ARCH/bits/syscall.h.in >> obj/include/bits/syscall.h
  printf '#define VERSION "%s"\n' "$VERSION" > obj/src/internal/version.h )
grep -q __musl_va_list_t "$MUSL/obj/include/bits/alltypes.h" \
    || die "generated alltypes.h lacks __musl_va_list_t (0040 not applied?)"

# drop our glue into the musl tree so it compiles with the same include set
cp "$HERE/glue/errno_loc.c" "$MUSL/src/errno/glue_errno_loc.c"
cp "$HERE/glue/start.c"     "$MUSL/src/env/glue_start.c"
cp "$HERE/glue/sigaction.c" "$MUSL/src/signal/glue_sigaction.c"

# ---------------------------------------------------------------------------
# 3. proxy tcc 0.9.26 (gcc-hosted), faithful to tcc_s: static-plt + BOOTSTRAP=1
# ---------------------------------------------------------------------------
say "build proxy tcc 0.9.26 (via $CC)"
TCC_BUILD="$WORKDIR/tcc-src"
rm -rf "$TCC_BUILD"
cp -a "$TCC_SRC" "$TCC_BUILD"
: > "$TCC_BUILD/config.h"                       # TCC_VERSION supplied via -D
# apply static-plt only if not already present (relocate_plt called twice => applied)
if [ "$(grep -c 'relocate_plt(s1);' "$TCC_BUILD/tccelf.c")" -lt 2 ]; then
    ( cd "$TCC_BUILD" && patch -p1 --no-backup-if-mismatch < "$TCC_STATIC_PLT" >/dev/null )
fi
TCC_DEFS="-D BOOTSTRAP=1 -D HAVE_LONG_LONG=1 -D HAVE_FLOAT=1 \
          -D TCC_TARGET_X86_64=1 -D CONFIG_TCC_STATIC=1 -D ONE_SOURCE=1 \
          -D TCC_VERSION=\"0.9.26\""
PROXY="$WORKDIR/tcc_proxy"
# shellcheck disable=SC2086
$CC -O0 -g -w $TCC_DEFS -I"$TCC_BUILD" "$TCC_BUILD/tcc.c" -o "$PROXY"
"$PROXY" -v

# ---------------------------------------------------------------------------
# 4. compile the musl subset + glue into libc.a; build crt + libtcc1
# ---------------------------------------------------------------------------
# include set for compiling musl's OWN .c files (internal overlay allowed)
IINC="-nostdinc -I obj/include -I arch/$ARCH -I arch/generic \
      -I obj/src/internal -I src/include -I src/internal -I include"
MUSL_CFLAGS="-std=c99 -ffreestanding -D_XOPEN_SOURCE=700 -D SYSCALL_NO_TLS"

OBJ="$WORKDIR/obj"
rm -rf "$OBJ"; mkdir -p "$OBJ"

# the manifest (123 exact musl files, incl. va_list.c [created by patch 0040],
# strcat.c [tcc.c uses strcat], sigemptyset.c [tcc set_exception_handler]) ...
SRCLIST=$(grep -vE '^\s*(#|$)' "$HERE/amd64/musl-subset.files")
# ... plus our glue (errno_loc, start, sigaction stub) copied into the tree above.
EXTRA="src/errno/glue_errno_loc.c src/env/glue_start.c src/signal/glue_sigaction.c"

say "compile musl subset with proxy tcc"
( cd "$MUSL"
  n=0
  for f in $SRCLIST $EXTRA; do
      [ -f "$f" ] || die "subset source missing: $f"
      o="$OBJ/$(echo "$f" | tr '/' '_').o"
      # shellcheck disable=SC2086
      "$PROXY" -c $IINC $MUSL_CFLAGS "$f" -o "$o" \
          || die "compile failed: $f"
      n=$((n+1))
  done
  printf '  compiled %d objects\n' "$n" )

say "archive libc.a"
"$PROXY" -ar cr "$WORKDIR/libc.a" "$OBJ"/*.o
ls -l "$WORKDIR/libc.a"

say "crt1.o + empty crti/crtn"
( cd "$MUSL"
  # shellcheck disable=SC2086
  "$PROXY" -c $IINC $MUSL_CFLAGS crt/crt1.c -o "$WORKDIR/crt1.o" )
: > "$WORKDIR/empty.s"
"$PROXY" -c "$WORKDIR/empty.s" -o "$WORKDIR/crti.o"
cp "$WORKDIR/crti.o" "$WORKDIR/crtn.o"      # amd64: crti/crtn are empty in this project

say "libtcc1.a (libtcc1.o + alloca86_64.o)"
"$PROXY" -c -D TCC_TARGET_X86_64=1 "$TCC_BUILD/lib/libtcc1.c"   -o "$WORKDIR/libtcc1.o"
"$PROXY" -c                        "$TCC_BUILD/lib/alloca86_64.S" -o "$WORKDIR/alloca86_64.o"
"$PROXY" -ar cr "$WORKDIR/libtcc1.a" "$WORKDIR/libtcc1.o" "$WORKDIR/alloca86_64.o"

# ---------------------------------------------------------------------------
# 5. compile tcc.c against the subset's PUBLIC headers and link tcc-musl
# ---------------------------------------------------------------------------
# consumer include set: public headers only. NO src/include / src/internal --
# their `#define weak ...` etc. collide with tcc.h identifiers.
CINC="-nostdinc -I $MUSL/obj/include -I $MUSL/arch/$ARCH -I $MUSL/arch/generic -I $MUSL/include"

say "compile tcc.c against the musl subset"
# shellcheck disable=SC2086
"$PROXY" -c $CINC $TCC_DEFS -I"$TCC_BUILD" "$TCC_BUILD/tcc.c" -o "$WORKDIR/tcc_musl.o"

say "link tcc-musl"
"$PROXY" -static -nostdlib -o "$WORKDIR/tcc-musl" \
    "$WORKDIR/crt1.o" "$WORKDIR/crti.o" "$WORKDIR/tcc_musl.o" \
    "$WORKDIR/libc.a" "$WORKDIR/libtcc1.a" "$WORKDIR/crtn.o"
ls -l "$WORKDIR/tcc-musl"

# ---------------------------------------------------------------------------
# 6. smoke test: tcc-musl runs, and self-hosts a hello world
# ---------------------------------------------------------------------------
say "smoke test: tcc-musl -v"
"$WORKDIR/tcc-musl" -v

say "smoke test: tcc-musl compiles + links + runs a hello world"
printf '#include <stdio.h>\nint main(void){ printf("hello from tcc-musl: %%d\\n", 42); return 0; }\n' \
    > "$WORKDIR/hello.c"
"$WORKDIR/tcc-musl" -c $CINC "$WORKDIR/hello.c" -o "$WORKDIR/hello.o"
"$WORKDIR/tcc-musl" -static -nostdlib -o "$WORKDIR/hello" \
    "$WORKDIR/crt1.o" "$WORKDIR/crti.o" "$WORKDIR/hello.o" \
    "$WORKDIR/libc.a" "$WORKDIR/libtcc1.a" "$WORKDIR/crtn.o"
out=$("$WORKDIR/hello")
printf '  program output: %s\n' "$out"
[ "$out" = "hello from tcc-musl: 42" ] || die "hello world produced unexpected output"

say "OK -- tcc-musl built from the musl subset and self-hosts. Artifacts in $WORKDIR"
