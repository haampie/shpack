# musl 1.1.24 — mes-libc replacement + full libc (amd64 + aarch64)

This directory drives building **real musl 1.1.24** as the C library for the bootstrap,
replacing GNU mes libc. It does so in two phases from the **pristine** upstream tarball
(`distfiles/musl-1.1.24.tar.gz`) — the sources are never repackaged/vendored:

Arch-specific build inputs live under per-arch subdirs `amd64/` and `aarch64/` (the
chroot-facing `${ARCH}` names); `kaem.run` reaches them via `${MSRC}/${ARCH}/…`.
Arch-neutral inputs (`glue/`, `patches/`, `simple-patches/`, `regen.*`, `kaem.run`,
`hello-float.c`) and the per-arch `sysinclude-<arch>.tar` stay at the top level.

The whole bootstrap (this step plus the tcc step) is driven from the repo root by
`./run-rootfs.sh` or `./run-local.sh` (optionally `--arch amd64|aarch64`).

1. **Subset** (in the `tcc-0.9.26` step): a curated 121-file closure of the ~60-symbol
   libc surface `tcc.c` needs, plus four glue files, compiled by the float-blind seed
   `tcc_s` then by `tcc-boot0`, just to bring the production `tcc` into existence.
2. **Full** (this step's `kaem.run`): every musl C source except `src/complex` and the
   `src/math/x86_64` asm shims, compiled by the finished float-correct `tcc`, with **no
   glue** (pristine `strtod`/`ldexp`/`errno`/`__libc_start_main`/`sigaction`). Overwrites
   the subset `libc.a` and installs real `crt1.o`/`crti.o`/`crtn.o` for binutils/gcc.

## Patches: two representations, kept in sync by `regen.py`

- `patches/*.patch` — the canonical unified diffs (`0006` strip `[static N]`, `0030`
  x86_64 syscall asm, `0040` SysV va_list). Use these where a real `patch` exists (Spack).
- `simple-patches/*.{before,after}` — one fragment pair per hunk, applied in the chroot by
  the repo's `simple-patch` (the chroot has no GNU `patch`). `regen.py` derives them from
  the unified diffs and **verifies** each reproduces `patch`'s output byte-for-byte. The
  fragments (and `MANIFEST`/`MANIFEST.aarch64`) are shared across arches — keyed by the
  patch-number prefix, which is arch-unique.
- `<arch>/apply-full.kaem` — the `simple-patch` invocation list (needs env `${SP}`).
  A single list applies the whole patch set for **both** the subset and full builds: every
  full-only hunk targets a file the subset never compiles, so applying it before the subset
  build is a no-op on the resulting `libc.a` (hence no separate `apply-subset.kaem`).

`0040`'s new file `src/stdarg/va_list.c` ships under `amd64/newsrc/` (copied into the tree,
not patched in); its `arch/x86_64/bits/alltypes.h.in` hunk is moot in-chroot because we ship
the pre-generated `amd64/generated/bits/alltypes.h` already in the `__musl_va_list_t` form.
The aarch64 asm→C sources ship under `aarch64/newsrc/` and are copied in by the generated
`aarch64/copy-newsrc.kaem`.

## Host-generated, committed inputs (regenerate with `./regen.sh [ARCH]`)

- `<arch>/generated/bits/{alltypes,syscall}.h`, `<arch>/generated/internal/version.h` —
  musl's three generated headers for the arch (chroot has no sed/awk). `alltypes.h` carries
  the va_list patch.
- `sysinclude-<arch>.tar` — one per arch, a flat, merged **public** header set (`stdio.h`
  etc. at the top, no arch prefix), untarred straight into the musl prefix's `include/`
  (in-chroot `cp` has no `-r`, so the `bits/` overlay — generic then arch then generated —
  is flattened once here). One tar per arch because the two arches' `bits/` headers differ
  and can't share one flat tree. Headers only; the musl *sources* are pristine. The header
  set needs no cross-toolchain, so `regen.sh` rebuilds **both** arches' tars in one pass
  regardless of the `ARCH` argument.
- `<arch>/build-libc-subset.kaem` / `<arch>/build-libc-full.kaem` — per-file compile + `ar`
  lists (kaem has no loops). Subset = `<arch>/musl-subset.files` + glue; full = `make -n` of
  the patched tree with `src/complex` + `src/math/<musl-arch>` removed (so generic C math is
  selected).
- `<arch>/apply-full.kaem`, `aarch64/copy-newsrc.kaem` (above).

`regen.sh` (host: sed/tar/make/python3; aarch64 source list also needs
`aarch64-linux-gnu-gcc`) regenerates the passed arch's inputs from the pristine tarball and
runs `regen.py` (which also verifies the fragments). Both arches' `sysinclude-<arch>.tar`
are rebuilt on every run.

## The four glue files (SUBSET only — the full build uses pristine musl)

- `glue/errno_loc.c` — plain-global `errno` (no TLS).
- `glue/start.c` — minimal `__libc_start_main` (no TLS/SSP/auxv/poll).
- `glue/float.c` — constant-free `strtod`/`strtof`/`strtold` + bit-twiddling `ldexp`,
  replacing `src/stdlib/strtod.c` + `src/math/ldexp.c`. The seed `tcc_s` is `HAVE_FLOAT=0`
  (folds float *literals* to 0), so musl's constant-laden float code would compile to
  garbage; these derive every value from runtime arithmetic/integer field edits instead.
- `glue/sigaction.c` — no-op `sigaction` (tcc references it as dead code under
  `CONFIG_TCC_BACKTRACE`, never called in the bootstrap).

## Compile flags (both phases)

`-nostdinc -I obj/include -I arch/<musl-arch> -I arch/generic -I obj/src/internal
-I src/include -I src/internal -I include -std=c99 -ffreestanding -D_XOPEN_SOURCE=700
-D SYSCALL_NO_TLS` (`<musl-arch>` = `x86_64` for amd64, `aarch64` for aarch64)
