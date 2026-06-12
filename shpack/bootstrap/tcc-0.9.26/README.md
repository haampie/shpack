<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# tcc 0.9.26 — float-correct, self-hosting C compiler (amd64 + aarch64)

This step builds the production **tcc 0.9.26** from the pristine upstream tarball
(`distfiles/tcc-0.9.26.tar.gz`, the `0.9.26-1147-gee75a10c` snapshot). The seed
`tcc_cc`/`stack_c` layer first brings a float-blind stage-1 `tcc_s` into existence;
that compiles a subset of musl 1.1.24 into `libc.a`, then `tcc.c` is rebuilt through
`tcc-boot0` → `boot1` → `boot2` until it reaches a byte-for-byte fixed point
(`boot2(tcc.c) == boot2`). The result is the float-correct `tcc` the musl step uses.

`pass1.kaem` drives the whole step. It is arch-generic: `${ARCH}` is `amd64` or
`aarch64`, and `TCC_TARGET_${TCC_TARGET_ARCH}` selects the backend
(`TCC_TARGET_X86_64` / `TCC_TARGET_ARM64`).

> **A note on `arm64` vs `aarch64`.** Everything *this repo* owns uses the
> live-bootstrap arch token `aarch64` (M2libc dir, `--architecture aarch64`, our
> `src/aarch64-asm.c` / `src/alloca-aarch64.S`, the `tcc-aarch64-*` patch names).
> But tcc 0.9.26 *upstream* names its 64-bit Arm backend `arm64`: it ships
> `arm64-gen.c`, `arm64-link.c`, `lib/lib-arm64.c` and the macro `TCC_TARGET_ARM64`.
> Those literal upstream names are kept as-is (a `simple-patch arm64-gen.c …` must
> name the real file), so a fragment such as `tcc-aarch64-04_tccpp.c_00` reads
> "our aarch64 patch series, hunk targeting upstream's `tccpp.c`".

## Patches: two representations, kept in sync by `regen.py`

The chroot has no GNU `patch`, so every tcc source edit is applied in-chroot by the
repo's `simple-patch FILE before after` (replaces the FIRST exact byte-match of
`before` with `after`). Two representations exist, mirroring the musl step:

- `patches/*.patch` — canonical unified diffs for the three aarch64 backend fixes.
  Use these where a real `patch` exists (Spack). They are the source of truth for
  the `tcc-aarch64-*` fragments.
- `simple-patches/*.{before,after}` — one fragment pair per hunk, applied in the
  chroot. The `tcc-aarch64-*` pairs are **generated** from the unified diffs above;
  the remaining small compat pairs are **hand-written** (no standalone upstream
  diff). `regen.py`:
  1. regenerates the `tcc-aarch64-*` fragments from `patches/*.patch`;
  2. verifies they reproduce GNU `patch`'s output byte-for-byte;
  3. replays the **entire** per-arch `simple-patch` chain (generated + hand-written)
     against pristine tcc, exactly in `pass1.kaem` order, so the hand-written pairs
     are validated too and an out-of-order fragment is caught;
  4. rewrites `simple-patches/MANIFEST` (amd64) and `simple-patches/MANIFEST.aarch64`
     — each the complete ordered fragment set for that arch (`fragment target`),
     common fragments listed in both.

  Run: `./regen.py <pristine-tcc-srcdir>` (the unpacked
  `tcc-0.9.26-1147-gee75a10c` tree; needs host `python3` + `patch`).

The fragment layout is **flat** (like the musl step): provenance lives in the
MANIFESTs, not in subdirectories.

## What each patch fixes and why tcc needs it

Common (both arches):

- `remove-fileopen` / `addback-fileopen` (`tcctools.c`) — relocate tcc's internal
  file-open helper so the seed `tcc_cc` can compile `tcctools.c` (a delete + re-add
  pair; together they have no single clean upstream diff, hence hand-written only).
- `tccpp-have-float-strtof` (`tccpp.c`) — guard the float (`F`-suffix) constant
  evaluator with `#if HAVE_FLOAT`, matching the double/long-double branches. Stage-1
  `tcc_s` has `HAVE_FLOAT` undefined and only a stub `strtof`, which derefs the NULL
  endptr and segfaults on any float constant (e.g. musl's `NAN == 0.0f/0.0f`).
- `tccpp-have-float-ldexp` (`tccpp.c`) — move the hex-float `ldexp(d, …)` call inside
  the same `#if HAVE_FLOAT` guard; the seed's `ldexp` loops on an unsigned exponent,
  so a negative exponent (`0x1p-120f`) becomes a ~2^64-iteration hang.

amd64 only:

- `static-plt` (`tccelf.c`) — call `relocate_plt()` for static executables; upstream
  never does, leaving every PLT stub with a wrong RIP-relative offset.
- `x86_64-mxcsr` (`x86_64-asm.h`) — teach the x86_64 assembler the `ldmxcsr`/`stmxcsr`
  SSE opcodes, needed to assemble pristine musl `src/fenv/x86_64/fenv.s`.

aarch64 only:

- `aarch64-asm-defs` (`tcc.h`) / `aarch64-asm-include` (`libtcc.c`) — wire in our
  minimal data-directive inline assembler `src/aarch64-asm.c` next to tcc's upstream
  `arm64-gen.c` / `arm64-link.c`.
- `tcc-aarch64-02-codegen` (`arm64-gen.c`, 3 hunks) — const-lval load/store for
  string/float literals + `ftof` mask.
- `tcc-aarch64-03-varargs` (`arm64-gen.c`, 2 hunks) — AAPCS64 `va` builtin loop and
  `va_list` parameter/array decay.
- `tcc-aarch64-04-long-double-suffix` (`tccpp.c`, 1 hunk) — treat the `ll` suffix as
  long double, like x86_64.
