<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# musl 1.1.24 subset — mes-libc replacement (amd64)

This directory provides a **stripped subset of real musl 1.1.24 sources** to serve as
the C library the bootstrapped tcc links against, replacing the GNU mes libc. Goal:
drop GNU mes from the bootstrap entirely. See `../../LOG-MUSL.md` for the full log.

## Why a subset works

`tcc.c` (both 0.9.26 and 0.9.27) references an **identical 60-symbol libc surface**.
Walking the symbol graph from those 60 seeds through musl's sources yields a closure of
**121 objects** with zero missing libc functions. We vendor **120** of them (the 121st,
`src/errno/__errno_location.c`, is replaced by `glue/errno_loc.c`).

The subset was validated end-to-end with the host compiler as a fast proxy: `tcc.c`
compiled against musl headers, linked against the 120-file subset + the glue + a stripped
crt, produces a working `tcc version 0.9.27 (x86_64 Linux)` that compiles C to valid ELF.

## Contents

- `musl-subset.files` — the 120 musl source paths to compile (relative to the musl tree).
  C files throughout; only `src/setjmp/x86_64/{setjmp,longjmp}.s` are assembly (no C
  version exists). x86_64 `.s` optimizations elsewhere are intentionally avoided in favour
  of the portable C paths, to minimise tcc inline-asm exposure.
- `glue/errno_loc.c` — plain-global `errno` (skips TLS); provides `__errno_location` and
  the hidden `___errno_location`.
- `glue/start.c` — minimal `__libc_start_main` (no TLS/SSP/auxv/poll), paired with musl's
  own `crt/crt1.c` + `crt/x86_64/crt_arch.h`.
- `glue/float.c` — constant-free `strtod`/`strtof`/`strtold`/`ldexp`, replacing musl's
  `src/stdlib/strtod.c` and `src/math/ldexp.c` (both dropped from `musl-subset.files`).
  The stage-1 `tcc_s` is `HAVE_FLOAT=0`: it folds every float *literal* to 0, so musl's
  float code (which derives results from constants like `0x1p-120`) compiles to garbage.
  These replacements form every value from runtime arithmetic on variables (`strtod`) and
  pure integer edits of the IEEE fields (`ldexp`) — codegen `tcc_s` can already emit — so
  the boot-stage tcc gets a working `strtod`/`ldexp` and bakes correct float constants.
- `generated/bits/alltypes.h`, `generated/bits/syscall.h`, `generated/internal/version.h`
  — musl's three generated headers, pre-generated for x86_64 (so the bootstrap needs no
  `sed`/`awk`). Regenerate with musl's own rules:
  - `sed -f tools/mkalltypes.sed arch/x86_64/bits/alltypes.h.in include/alltypes.h.in`
  - `cp arch/x86_64/bits/syscall.h.in bits/syscall.h; sed -n 's/__NR_/SYS_/p' >> bits/syscall.h`
  - `printf '#define VERSION "%s"\n' 1.1.24`
- `COPYRIGHT` — musl's MIT license/notice (musl is MIT; this subset is exact-source).

## Include paths (musl's own, for compiling the subset)

```
-nostdinc -Iarch/x86_64 -Iarch/generic -I<generated/internal> -Isrc/include
-Isrc/internal -I<generated> -Iinclude
```
plus `-std=c99 -ffreestanding -D_XOPEN_SOURCE=700`.

## Known stub-vs-vendor pruning (optional, not required for correctness)

- `abort` -> could be stubbed to `_Exit` to drop `signal/{raise,block}`.
- `gettimeofday`/`time` -> raw syscalls would drop `internal/vdso.c` +
  `time/clock_gettime.c` (and the only otherwise-unresolved `_GLOBAL_OFFSET_TABLE_` ref).
- `localtime` -> simplifying drops `time/{__map_file,__tz,...}`.

## Licensing

musl 1.1.24 is MIT. Exact-source files retain their license; `COPYRIGHT` is shipped here
to satisfy the MIT notice requirement. The glue files are MIT. This repo as a whole is
GPL-3.0-or-later; MIT is GPL-compatible.

## Floating point (two independent facets, both solved)

1. **Float constants** — `glue/float.c` (constant-free `strtod`/`ldexp`); see above.
2. **`double` varargs / `printf("%f")`** — the `0040` patch's `va_arg` macro classifies the
   type at compile time via `__builtin_types_compatible_p` (`__va_argtype`: float/double →
   SSE/XMM `arg_type 1`, else GP `0`). The tcc 0.9.26 x86_64 SysV codegen already spills XMM
   regs in variadic prologues and sets `AL`; the runtime `__va_arg` already reads the XMM save
   area — only the macro dispatch was hardcoded to GP. This `0040` is the float-correct variant
   (was the old `bootstrap-musl-boot` half of the scaffold→boot ladder); `__builtin_types_compatible_p`
   is a pure type query so even the HAVE_FLOAT=0 `tcc_s` resolves it.

## Status

Both float facets verified end-to-end against the subset (full `libc.a` rebuilt with the
bootstrap tcc; `%f`, mixed int/float varargs, and `%.2f`/`%e` are byte-identical to host gcc).
Remaining: the authoritative `task5_amd64.sh` chroot rebuild (`tcc_s` compiles the new header;
chain self-hosts boot1==boot2), then scale the subset up to full musl 1.1.24.
