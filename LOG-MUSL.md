# Log: replacing GNU mes libc with a stripped musl 1.1.24 subset

Working log for the effort to drop GNU mes entirely from this bootstrap by linking
the production tcc against a stripped subset of real musl 1.1.24 sources instead of
the mes libc.

## Decisions (2026-06-04)

- **Approach**: hand-selected stripped subset of real musl 1.1.24 sources, compiled
  by `tcc_s` into `libc.a` + `crt1.o`, linked into the production tcc in place of mes libc.
- **Arch**: amd64 (x86_64) first. arm64 deferred (tcc inline/setjmp asm is the unknown).
- **Verification**: byte-for-byte reproducibility against live-bootstrap's tcc is
  deliberately dropped. New anchor = the produced full musl 1.1.24 is correct/reproducible.
- **Env assumptions**: live-bootstrap uses kaem (no sh). Spack target assumes `dash` exists,
  so the *full* musl build there can use configure/make/sed. The *subset* build avoids
  sed/awk by shipping pre-generated headers.

## Where mes is used today

1. Bootstrap compiler — already replaced: `tcc_cc` + `src/stdlib.c` build the first
   `tcc_s` via stack_c/M1/hex2. No mes.
2. Runtime libc the shipped tcc links against — STILL mes: `tcc_s` rebuilds mes
   `unified-libc.c` -> `libc.a` + `crt1.o` + headers in `steps/tcc-0.9.26/pass1.kaem`,
   and every production tcc (boot0/1/2, 0.9.27) links it. THIS is what we replace.

## Target chain (mes-free)

```
tcc_cc + stdlib.c -> tcc_s -> musl-subset libc.a + crt1.o -> tcc-musl -> tcc-0.9.27 -> full musl 1.1.24
```

## Task 1 — pin tcc's libc surface  [DONE]

Method: compile `tcc.c` (ONE_SOURCE) with the bootstrap's amd64 `-D` flags using
`gcc -c -w -fno-builtin -fno-stack-protector` + empty `config.h`, then `nm -u`.
Result: **0.9.26 and 0.9.27 reference an IDENTICAL 60-symbol libc surface.**
`__stack_chk_fail` = gcc SSP artifact (drop). `__isoc23_*` = glibc redirects = plain
`strtol/strtoul/strtoull/sscanf`.

The 60 symbols:
```
abort __assert_fail atoi close __errno_location execvp exit fclose fdopen fflush
fopen fprintf fputc fputs fread free fseek ftell fwrite getcwd getenv gettimeofday
ldexp localtime longjmp lseek malloc memcmp memcpy memmove memset mprotect open
printf qsort read realloc remove _setjmp snprintf sprintf sscanf stderr stdout
strchr strcmp strcpy strlen strncmp strrchr strstr strtod strtof strtol strtold
strtoul strtoull time unlink vsnprintf
```
tcc needs far LESS than `src/stdlib.c` (no stat/fstat/mkdir/chdir/access/fork/dup/
readlink/symlink/uname — those exist for the *utilities*, not tcc).

Direct symbol -> musl file map: string/{memcmp,memcpy,memmove,memset,strchr,strcmp,
strcpy,strlen,strncmp,strrchr,strstr}, stdlib/{atoi,qsort,strtol.c,strtod.c},
malloc/malloc.c, stdio/{fclose,__fdopen,fflush,fopen,fprintf,fputc,fputs,fread,fseek,
ftell,fwrite,printf,snprintf,sprintf,sscanf,vsnprintf,remove,stderr,stdout},
unistd/{close,getcwd,lseek,read,unlink}, fcntl/open, process/execvp, mman/mprotect,
time/{gettimeofday,localtime,time}, math/ldexp, setjmp/x86_64/{setjmp.s,longjmp.s},
errno/__errno_location, exit/{abort,exit,assert.c}, env/getenv.

Stub-vs-vendor for the transitive closure: __lockfile -> no-op (single-threaded),
abort -> _Exit (avoid signals), localtime -> simplify (tz heavy), __libc_start_main
-> stripped (no TLS/SSP/poll).

## Task 2 — scaffold steps/musl-1.1.24-subset/  [IN PROGRESS]

Plan: unpack musl from a tarball in-chroot (like the tcc steps) and compile a curated
file list; the repo holds the build (kaem) script, the file list, pre-generated headers,
the stripped crt/stubs, and patches. We do NOT vendor all musl sources into the repo.

- Pre-generated headers (x86_64) regenerated with musl's own rules: `bits/alltypes.h`
  (`sed -f tools/mkalltypes.sed`), `bits/syscall.h` (`sed -n s/__NR_/SYS_/p`),
  `internal/version.h` (`#define VERSION "1.1.24"`). [done in /tmp/msb]
- Closure discovery: compiled 1068 candidate musl C files with gcc freestanding flags
  (`-std=c99 -ffreestanding -nostdinc -D_XOPEN_SOURCE=700`), ALL compiled OK (good omen
  for tcc — prefer C paths, avoid x86_64 .s except setjmp/longjmp).
- **Closure = 121 musl objects**, walking the symbol graph from the 60-symbol seed.
  The ONLY unresolved symbol is `_GLOBAL_OFFSET_TABLE_` (linker-provided; arrives via
  `internal/vdso.c` + `time/clock_gettime.c` behind `gettimeofday`). So the subset has
  **zero missing libc functions** — it is complete.

  The 121 (musl `src/...`): env/{__environ,getenv}; errno/{__errno_location,strerror};
  exit/{_Exit,abort,assert,exit}; fcntl/open; internal/{floatscan,intscan,libc,shgetc,
  syscall_ret,vdso}; locale/__lctrans; malloc/{expand_heap,lite_malloc,malloc};
  math/{__fpclassifyl,__signbitl,copysignl,fabs,fmodl,frexpl,ldexp,scalbn,scalbnl};
  mman/{madvise,mmap,mprotect,mremap,munmap}; multibyte/{internal,mbrtowc,mbsinit,
  wcrtomb,wctomb}; process/{execve,execvp}; setjmp/x86_64/{longjmp.s,setjmp.s};
  signal/{block,raise}; stdio/{__fdopen,__fmodeflags,__lockfile,__overflow,__stdio_close,
  __stdio_exit,__stdio_read,__stdio_seek,__stdio_write,__stdout_write,__string_read,
  __toread,__towrite,__uflow,fclose,fflush,fopen,fprintf,fputc,fputs,fread,fseek,ftell,
  fwrite,ofl,ofl_add,printf,remove,snprintf,sprintf,sscanf,stderr,stdout,vfprintf,
  vfscanf,vsnprintf,vsprintf,vsscanf}; stdlib/{atoi,qsort,strtod,strtol};
  string/{memchr,memcmp,memcpy,memmove,memrchr,memset,stpcpy,strchr,strchrnul,strcmp,
  strcpy,strdup,strlen,strncmp,strnlen,strrchr,strstr}; thread/{__lock,__syscall_cp,
  __wait}; time/{__map_file,__month_to_secs,__secs_to_tm,__tz,__year_to_secs,
  clock_gettime,gettimeofday,localtime,localtime_r,time}; unistd/{close,getcwd,lseek,
  read,unlink}.

  Optional pruning (Task 4, once it builds): stub `abort`->`_Exit` drops signal/{raise,
  block}; simplify `gettimeofday`/`time` to raw syscalls drops internal/vdso +
  time/clock_gettime (and the `_GLOBAL_OFFSET_TABLE_` ref); simplify `localtime` drops
  time/{__map_file,__tz,...}. Not required for correctness.

- Validation (gcc proxy): compiled tcc.c against MUSL headers (clean), built a stripped
  crt (musl crt1.c + crt_arch.h `_start` + our minimal `__libc_start_main`), replaced
  `__errno_location` with a plain-global version (both public + hidden `___errno_location`
  — musl's internal callers use the 3-underscore hidden name), linked static vs the subset
  + libgcc. Result: **`tcc version 0.9.27 (x86_64 Linux)`**, and it compiles C to a valid
  ELF object. Subset proven complete, headers proven, with ZERO source patches.

### Scaffold created: `steps/musl-1.1.24-subset/`  [DONE]
  - `musl-subset.files` — 120 vendored musl source paths (the 121-closure minus
    `src/errno/__errno_location.c`, replaced by glue).
  - `glue/errno_loc.c` — plain-global errno (skips TLS).
  - `glue/start.c` — minimal `__libc_start_main` (no TLS/SSP/auxv/poll).
  - `generated/{bits/alltypes.h,bits/syscall.h,internal/version.h}` — pre-generated x86_64.
  - `COPYRIGHT` — musl's MIT notice (attribution).
  - `README.md` — design + regen instructions.
  - `make-subset-tarball.sh` — repackages a minimal MIT-compliant `musl-1.1.24-subset.tar.gz`
    from a musl tree (exact subset .c/.s + the per-dir private headers they include, e.g.
    `time_impl.h`/`putc.h`/`__strerror.h`/`internal.h`, + full include/arch/src-internal
    headers + generated headers + glue + COPYRIGHT).

### Tarball self-containment test  [PASS]
  Built `musl-1.1.24-subset.tar.gz` (365 KB, 474 entries), unpacked fresh, compiled all
  120 + glue + crt1 (0 failures), recompiled tcc.c against the tarball's headers only,
  linked, ran: `tcc version 0.9.27 (x86_64 Linux)`. **Self-contained.**

## Task 4 — build the subset with a real tcc 0.9.26  [IN PROGRESS]

Goal: prove tcc 0.9.26 (the compiler `tcc_s` is) can COMPILE the subset, surfacing the
exact tcc-compat patch set, before wiring into the kaem chain.

### Proxy compiler
No host tcc; the bootstrap `tcc_s` is tcc 0.9.26 built by `tcc_cc`. The compiler
*frontend* (asm parser / `weak_alias` / long-double / va handling) is inherent to
tcc.c 0.9.26, so a **gcc-built host tcc 0.9.26 from the same distfile is a faithful
proxy** for surfacing compile errors and far faster than a chroot run. Built at
`/tmp/msb4/tcc09` from `tcc-0.9.26-1147-gee75a10c` with the `static-plt` simple-patch
applied (the only tcc-side patch relevant to the amd64 subset — see below). Work dir
`/tmp/msb4`, unpacked subset tarball at `/tmp/msb4/musl-1.1.24-subset`.

### Prior art (reused) — spack bootstrap packages
`~/projects/bootstrap-glibc/bootstrap/spack_repo/bootstrap/packages/`:
  - `bootstrap_musl_scaffold/` builds *full* musl 1.1.24 with tcc-mes as CC. Its
    **amd64 source patches map exactly onto our errors**:
    - `0006-Strip-C99-static-N-array-declarators.patch` — tcc can't parse `T buf[static N]`;
      only the `src/internal/syscall.h` hunk applies to our subset.
    - `0030-syscall-x86_64.patch` — rewrites `__syscall4/5/6` from register-asm
      (`register long r10 __asm__("r10")`, unsupported by tcc) to explicit
      `mov %N,%%r10 ; syscall`.
    - `0040-x86_64-sysv-va_list.patch` — tcc 0.9.26 x86_64 has no `__builtin_va_*`.
      Rewrites `arch/x86_64/bits/alltypes.h.in` (va_list -> `__musl_va_list_t[1]`
      SysV-AMD64 struct), `include/stdarg.h` (route through tcc's `__va_start`/`__va_arg`),
      and **adds `src/stdarg/va_list.c`** (tcc's va runtime, retyped) so the symbols land
      in libc.a. NOTE the documented scaffold limitation: `__va_arg` arg_type hardcoded
      to GP(0), so `%f` varargs don't round-trip — acceptable for building tcc (the mes
      path had the same limit).
    - `-DSYSCALL_NO_TLS` on CFLAGS — tcc has no `__thread`. We need this too.
    - Not needed for our subset: `0001`/`0020` (build-system -lg/empty-archive),
      `0004` (rcrt1.c), `0002` (sigsetjmp PLT — sigsetjmp not in our 60-symbol surface),
      `0031`/fenv (no fenv in our closure). src/complex + src/math/x86_64 removed there;
      our subset never included them.
  - `bootstrap_tcc_musl/` builds tcc 0.9.26 linked against a musl (the analogue of our
    `tcc-musl`). Gives the exact link recipe: `crt1.o crti.o tcc.c libc.a libtcc1.a
    crtn.o`, `-static -nostdlib -nostdinc`, `-DHAVE_FLOAT=1` (CRITICAL: the 0.9.26 fork
    zeroes all float literals without it), and **libtcc1.a must include `alloca86_64.S`**
    (tcc maps `__builtin_alloca` -> symbol `alloca`, which musl lacks). Self-hosts in 3
    stages, asserts stage2==stage3. tcc-side patches there: `tcc-static-plt`,
    `tcc-va-list` (mes-only, superseded by musl 0040), `tcc-x86_64-mxcsr` (only for
    musl's fenv.s — not in our subset). So for amd64 the only tcc-side patch we need is
    `static-plt`.

### Results with the real tcc 0.9.26
- Before patches: 80/118 C files FAILED — two signatures: `';' expected (got "va_list")`
  (the `__builtin_va_list` typedef) and `identifier expected` (the `[static N]` in
  syscall.h). Exactly the two issues 0040 and 0006 fix.
- After applying 0006 (syscall.h hunk) + 0030 + 0040 (alltypes.h regenerated to the
  `__musl_va_list_t` form, stdarg.h rerouted, `src/stdarg/va_list.c` added) and compiling
  with `-DSYSCALL_NO_TLS`: **all 120 subset sources + va_list.c + glue compile cleanly**,
  and tcc assembles `setjmp.s`/`longjmp.s` and builds `crt1.o` + `libtcc1.a`(+alloca).
- **Consumer vs internal include paths**: musl's `src/include/` + `src/internal/` are an
  *internal* overlay for compiling musl's own sources (e.g. `src/include/features.h`
  `#define weak __attribute__((__weak__))`, which collides with tcc.h's `weak` bitfield).
  When compiling a *consumer* (tcc.c) use ONLY public headers:
  `-nostdinc -I. -Iobj/include -Iarch/x86_64 -Iarch/generic -Iinclude`. With that,
  **tcc.c compiles cleanly under real tcc 0.9.26** (490 KB .o). (A red-herring
  `identifier expected` while debugging was an `eval`/shell-quoting artifact stripping
  the quotes off `-DTCC_LIBGCC="..."`, not a tcc/musl issue.)

### CURRENT BLOCKER
Linking `tcc-musl` (`tcc09 -static -nostdlib -o tcc-musl crt1.o crti.o tcc_musl.o
libc.a libtcc1.a crtn.o`; empty crti/crtn on amd64, as pass1.kaem does) — **the proxy
tcc09 itself SEGFAULTs during the link** (exit 139, core dumped). All input symbols are
present (`__va_start`/`__va_arg` now `T` in libc.a after fixing a word-split that had
skipped building `va_list.c.o`). The earlier gcc-proxy linked the same subset fine, so
this is in tcc09's *linker/codegen* path, not a missing symbol. Next: determine whether
the crash is the `static-plt`/`relocate_plt` path on a fully static `-nostdlib` link, an
empty-crti/crtn artifact, or a tcc09-as-built-by-gcc quirk; try the spack link form
(real crti.o/crtn.o from musl, or drop `-nostdlib` variations) and bisect. Then run
`tcc-musl -version` + a hello-world compile/link, and codify into the repo:
`steps/musl-1.1.24-subset/patches/` (0006/0030/0040), regenerated `generated/bits/alltypes.h`,
`src/stdarg/va_list.c` added to `musl-subset.files`, and a kaem build script mirroring
pass1.kaem's libc section.

## Task 5 — wire the subset into tcc-0.9.26 (amd64), replace mes  [DONE]

`steps/tcc-0.9.26/pass1.kaem` rewired with a `LIBC=musl|mes` switch (amd64 -> musl,
others -> mes; kaem has no `else`, so each branch is a separate `if match`). The amd64
path now: unpacks `musl-1.1.24-subset.tar.gz`, untars `sysinclude.tar` into `${INCDIR}`,
runs the generated `build-libc.kaem` (126 per-file `tcc_s -c` lines + one `ar`) to build
`${LIBDIR}/libc.a`, builds `crt1.o` + empty `crti.o`/`crtn.o` + `libtcc1.a`(+alloca86_64.S),
and reuses that one libc across boot0/1/2 (the mes per-stage libc rebuilds are gated to
`mes`). The 3 musl patches (0006/0030/0040) are baked into the distfile by
`make-distfile.sh`; only `static-plt` remains as a tcc-side patch. `steps/manifest` stops
after tcc-0.9.26 (0.9.27 still needs mes). Distfile committed to `distfiles/`.

## Task 6 — in-chroot verification  [IN PROGRESS]

First `./task5_amd64.sh` runs surfaced three real bugs, all now fixed:

### Bug A — `make -C src` fails under GNU make 4.4 ("No rule to make target unittest.amd64")
GNU make **4.4** no longer uses a *match-anything* rule (`% : %.c`) to build a prerequisite
needed only to **chain** implicit rules. The seed tools (`tcc_cc`, `blood-elf`, `M1`,
`hex2`, `stack_c*`) are static prereqs of the `.sl64 -> .M1_amd64 -> .blood_elf_amd64 ->
.macro_amd64 -> .amd64` chain, so the chain couldn't form. **Fix** (`src/Makefile`): add a
**static pattern rule** for those tools (`$(HOST_SEED_TOOLS) : % : %.c`) — not
match-anything, so it's eligible for chaining. Verified clean `x86`/`amd64`/`all` builds.

### Bug B — `tcc_s` SIGSEGV on decimal float constants (e.g. musl `NAN` = `0.0f/0.0f`)
Stage-1 `tcc_s` is built with `HAVE_FLOAT` undefined (the seed has no real float). tccpp.c
guards the double/long-double constant evaluators with `#if HAVE_FLOAT` but **left the
float `F`-suffix case unguarded**: `tokc.f = strtof(token_buf, NULL)` calls the seed's
`strtof` **stub** (`*endptr = str; return 0;`), which derefs the NULL endptr -> crash.
First hit compiling `src/internal/floatscan.c`. Pinpointed with gdb (`f_strtof+55`) and
cvise (reduced to `0.0f`). **Fix**: simple-patch `tccpp-have-float-strtof.{before,after}`
wraps that line in `#if HAVE_FLOAT`.

### Bug C — `tcc_s` infinite hang on hex-float constants with negative exponent (`0x1p-120f`)
Same incomplete-`HAVE_FLOAT` story for the hex-float path: the mantissa is guarded but the
following `d = ldexp(d, exp_val - frac_bits)` is not. The seed's `ldexp(double, size_t exp)`
loops `for(i=1;i<exp;i++)` (and isn't even a real ldexp), so a negative exponent becomes a
~2^64-iteration hang. Hit `fmodl.c`, `scalbn.c`, `scalbnl.c`, `vfprintf.c`. **Fix**:
simple-patch `tccpp-have-float-ldexp.{before,after}` moves the `ldexp` call inside the
existing `#if HAVE_FLOAT`. Both patches wired in pass1.kaem after the tcctools patches
(unconditional — harmless for mes/other arches and for the HAVE_FLOAT=1 boot stages).

### Full scan (current unpatched `tcc_s`, per-file timeout)
121/126 subset compiles OK; the only 5 failures are exactly the float-constant files above
(1 crash + 4 hangs) — **no non-float bugs**. tcc's float-value computation is only
strtof/strtod/strtold (decimal) + mantissa/ldexp (hex); strtod/strtold were already
guarded, so the two new patches close every float path. After them, no float constant can
call into the seed libc, so none can crash or hang `tcc_s`.

**Caveat (now resolved — see Task 7):** because the seed can't evaluate float constants,
every float/double constant in the `tcc_s`-built `libc.a` (floatscan/strtod tables, vfprintf
`%f`) is left 0 / garbage. Harmless for self-hosting tcc + non-float hello-world; a real
blocker for the eventual gcc bootstrap (float-heavy).

## Task 7 — genuine float bootstrap (amd64)  [DONE 2026-06-05]

The seed is float-blind in **two independent ways**; both are now fixed, and the shipped
`tcc` prints `%f` byte-identical to host gcc.

### Facet 1 — float *constants* (`tcc_s` is `HAVE_FLOAT=0`, folds every float literal to 0)
`HAVE_FLOAT` gates only constant *evaluation/folding/storage* (tccpp.c + the `tccgen.c`
`vtop->c.*` cases incl. `init_putv`); runtime float **codegen** (`x86_64-gen.c`
mulsd/cvtsi2sd) is NOT gated. So `tcc_s` can emit runtime float arithmetic — it just bakes
float *literals* as 0. mes converged only because mes' `strtod` (`abtod`) is **constant-free
runtime arithmetic**; musl's `strtod`/`scalbn` are constant-laden (`0x1p-120`, …) → folded
to 0 (LOG bugs B/C above were the constant-evaluator *crashing*; this is the next layer —
the constants *silently zeroing*).

**Fix:** `steps/musl-1.1.24-subset/glue/float.c` — constant-free `strtod`/`strtof`/`strtold`
(integer mantissa scaled by a *runtime* base multiply/divide loop) + bit-manipulation
`ldexp` (edits the IEEE exponent field via a `union{double; unsigned long long;}`, bit-exact).
No float literals / static-float initializers, so `tcc_s` compiles them correctly. Drops
`src/stdlib/strtod.c` + `src/math/ldexp.c` from `musl-subset.files`. The lone hex-path
constant `4294967296.0` self-heals at boot1 (boot0 evaluates it via the now-correct decimal
`strtod`). Validated vs glibc: `ldexp` bit-exact over ±1100; exact decimals exact; short
inexact decimals ≤1 ULP. The two `tccpp-have-float-{strtof,ldexp}` guard patches **stay**
(they keep `tcc_s` from *calling* the float libc).

### Facet 2 — `double` through varargs / `printf("%f")` (separate from constants)
tcc 0.9.26's x86_64 SysV codegen is fully correct: `gfunc_prolog` spills all 8 XMM regs in
variadic prologues (`!nosse`), `gfunc_call` sets `AL = nb_sse_args`, and the runtime
`__va_arg` in the `0040` patch already reads the XMM save area. The **sole** defect was the
`va_arg(ap,type)` macro hardcoding `arg_type=0` (GP) for every type, so a `double` was
fetched from a GP slot → 0.

**Fix:** classify the type at compile time. Replaced the scaffold's GP-only `0040` with the
float-correct variant (the old `bootstrap_musl_boot/0040`): adds
`#define __va_argtype(type) ((__builtin_types_compatible_p(type,float)||…double)?1:0)` and
routes `va_arg` through it. `__builtin_types_compatible_p` is a pure type query (no float
eval), so even the `HAVE_FLOAT=0` `tcc_s` resolves it — the two facets are independent. The
patch also adds `#ifdef __TINYC__` guards in `alltypes.h.in` (tcc gets the explicit SysV
`__musl_va_list_t[1]`; a real gcc-stage0 against this sysroot gets `__builtin_va_list`,
ABI-identical). Proven in isolation: a tcc_s-compiled variadic callee fed real doubles by the
final-tcc caller returns `8.0` (`4020000000000000`), so the prologue+runtime are correct.

### The third layer — vfprintf's *formatter* also has constants (the actual `%f → 0.000000`)
With both facets in, the chroot `tcc` *still* printed `0.000000`. Cause: musl's float
**formatter** `fmt_fp` (inside `src/stdio/vfprintf.c`) is itself constant-laden —
`vfprintf.c:268 y *= 0x1p28`, plus `0x1.0p0`/`0x1.8p0` at 326-327. Facet-1's glue only covers
`strtod`/`ldexp`; it can't glue away the formatter. Because `pass1.kaem` builds `libc.a` with
`CC=tcc_s` (`HAVE_FLOAT=0`), `0x1p28` folds to 0 and `y *= 0` zeroes the value before
formatting → `0.000000`, even though the va_arg/XMM path is correct.

**Fix (stage B):** `pass1.kaem` now rebuilds `${LIBDIR}/libc.a` with `CC=tcc-boot0`
(`HAVE_FLOAT=1`) right after boot0 is built, before boot1/boot2. boot0 evaluates those
constants, and boot1 (built by boot0) + boot2/`tcc` (built by boot1) both link the
float-correct archive — so this relinks the final tcc *and* keeps the stages consistent. The
first `tcc_s`-built `libc.a` is only needed to bring boot0 into existence; tcc never calls
`printf("%f")` while compiling, so the self-host is unaffected. `crt1.o`/`libtcc1.a` carry no
float constants and are not rebuilt. This is the float-*constant* half of the old chain's
two-musl ladder — note it is **not** the va_arg facet (that's closed by `0040`).

### Verification (chroot-produced `tcc`, 2026-06-05)
- `printf("%f %f %f", 3.0, 2.0, 1.5)` → `3.000000 2.000000 1.500000`, and mixed int/float
  varargs + `%.2f`/`%10.3f`/`%e` are **byte-identical to host gcc**.
- Raw bytes of constant `3.0` = `4008000000000000`, runtime `3.0+0.5` = `400c000000000000`
  (facet 1 in the final tcc, exact).

### Fixed point — reached at boot2, now asserted (boot2 == boot3)
The chain does **not** converge at boot1: boot0 is compiled by the float-blind `tcc_s`
(`HAVE_FLOAT=0`), so it bakes a couple of float *constants* inside `tcc.c`'s own `.data` as 0.
boot1 (`HAVE_FLOAT=1`, built by boot0) evaluates them correctly when it compiles boot2, so
boot1 and boot2 differ by **exactly 2 bytes** in `.data` — the high (sign/exponent) byte of
two float constants, `0x00`→`0x80`, 16 bytes apart (file offset `0x5A3F9`/`0x5A409`). Hashes:
boot0/boot1/tcc = `3ed9a1`/`7d17…`/`5b59…` (boot0 unchanged by stage B; boot1+tcc moved
because they now link the boot0-built libc). boot2 is therefore the **first float-correct
compiler**, and `boot2(tcc.c)` reproduces boot2 byte-for-byte.

`pass1.kaem` now **asserts this**: after boot2 it records `sha256sum -o` of boot2, rebuilds
`tcc.c` with boot2 over the same filename (= boot3), and runs `sha256sum -c` — which exits
nonzero (aborting kaem) if boot2 ≠ boot3. (Verified the tool's pass/fail/abort semantics out
of band: match → `OK` rc 0, mismatch → `FAILED` rc 1.) This is the reproducibility anchor that
replaces the old, never-actually-checked boot1==boot2 assumption, and the gate to keep before
scaling.

**Next:** scale the subset up to full musl 1.1.24 (plan step 2), then hand off to Spack at
binutils.
