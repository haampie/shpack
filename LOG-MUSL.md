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

## Task 8 — grow subset → full musl 1.1.24, on a pristine-tarball + simple-patch base  [IN PROGRESS 2026-06-05]

Reworked the packaging so the bootstrap consumes the **pristine** upstream
`musl-1.1.24.tar.gz` (committed in `distfiles/`, shared across arches) instead of a
repackaged subset tarball. All tcc-compat changes are applied **in-chroot** with
`simple-patch` (the chroot has no GNU `patch`); each build stage re-extracts the pristine
tree and applies the patch set it needs. Two representations of the patches coexist:
`patches/*.patch` (canonical unified diffs, for Spack's host `patch`) and
`simple-patches/*.{before,after}` (one fragment pair per hunk, for kaem).

### Tooling: `steps/musl-1.1.24/regen.{py,sh}` (host-side, committed outputs)
- `regen.py` parses each unified diff into per-hunk `before/after` fragments (respecting the
  `@@ -a,b +c,d @@` line counts so the git `-- \n<ver>` trailer isn't slurped), skips the
  `alltypes.h.in` hunk (shipped pre-generated) and `/dev/null` new files (`va_list.c` →
  `newsrc/`), and **verifies** every fragment reproduces GNU `patch` byte-for-byte. It then
  emits `apply-{subset,full}.kaem` (simple-patch lists; subset patches only the 3 files its
  sources include — `src/internal/syscall.h`, `arch/x86_64/syscall_arch.h`, `include/stdarg.h`)
  and `build-libc-{subset,full}.kaem` (per-file compile + `ar`, kaem has no loops).
- `regen.sh` regenerates the committed host artifacts from the pristine tarball: the three
  `generated/` headers (sed), `sysinclude.tar` (flat merged public headers — kept because the
  in-chroot `cp` has no `-r`), the **full** source list (`./configure` + `make -n` on the
  patched tree with `src/complex` + `src/math/x86_64` removed so generic C math is selected →
  1257 src files), then drives `regen.py`.

### Wiring
- `steps/tcc-0.9.26/pass1.kaem`: unpack pristine musl → `kaem --file apply-subset.kaem` (SP
  set) → drop in `generated/` headers, `newsrc/src/stdarg/va_list.c`, and the four glue files →
  `build-libc-subset.kaem` (unchanged compile commands, so the subset `libc.a` and the
  boot2==boot3 fixed point are **behaviorally identical** to Task 7).
- New `steps/musl-1.1.24/pass1.kaem` (+ `sources`/`SHA256SUM`, `build: musl-1.1.24` in the
  manifest): unpack pristine → `apply-full.kaem` → `build-libc-full.kaem` with `CC=tcc`
  (HAVE_FLOAT=1, **no glue**) → overwrite `${LIBDIR}/libc.a`, install real
  `crt1.o`/`crti.o`/`crtn.o` from musl's `crt/`, then a `%f` `hello-float.c` smoke test.

### Validation so far (host, no chroot — sudo unavailable here)
- `regen.py` verify: all 11 fragments == `patch` output. ✓
- Subset: gcc-freestanding proxy compiled all 125 objects; `libc.a` has the expected surface
  (`printf`/`strtod`/`ldexp`/`__va_arg`/`__libc_start_main`/`vfprintf`). ✓ (and the compile
  commands are byte-identical to the old subset build, so tcc self-host is unaffected).
- Full: gcc-freestanding proxy compiled **all 1257** sources (0 failures); `libc.a` carries
  the full-only surface (`getaddrinfo`, `pow`, `sqrt`, `regcomp`, `socket`, `getpwnam`,
  `opendir`). ✓ The remaining unknown is tcc-specific assembler/codegen coverage on the
  `.s`/inline-asm the gcc proxy can't exercise (fenv.s, ldso/*, x86_64 string asm, threads).

### Full tcc-driven build — GREEN (2026-06-05)
`./task5_amd64.sh` ran clean end-to-end: the chroot tcc compiled **all 1257** full-musl
sources, replaced `libc.a`, installed real `crt1.o`/`crti.o`/`crtn.o` from musl's `crt/`,
and the `hello-float.c` smoke test **linked and ran**: `./hello-float` → `3.000000 2.000000
1.500000` (full musl `%f` correct). **No new patches were needed** — the shipped
`0006/0030/0040` + `-DSYSCALL_NO_TLS` sufficed; `0002`/fenv/ldso-asm did NOT have to be
added (the tcc-specific `.s`/inline-asm the gcc proxy couldn't exercise all assembled fine).
One real fix: the smoke test invoked `hello-float` bare, which kaem's `find_executable`
(`src/kaem.c:715`) searches on PATH (→ `/usr/bin`, ENOENT); changed to `./hello-float`.

### NEXT
Hand the full libc off to Spack at binutils.

## Task 9 — port the musl bootstrap to aarch64  [IN PROGRESS 2026-06-06]
Mirror the whole amd64 path (subset → boot2==boot3 fixed point → full musl → `hello-float`)
on aarch64, parametrized by `${ARCH}` so one source tree serves both. The lower bootstrap
was already arm64-capable (`task5_arm64.sh`, `target_arm64/`, `src/arm64-asm.c`,
arch-split `tcc_s`); the gap was the x86_64-hardcoded musl libc wiring.

### Prior art (translated, not re-derived)
From `~/projects/bootstrap-glibc/.../bootstrap_{musl_scaffold,tcc_musl}`:
- musl `aarch64-01-va_list` (AAPCS64 5-field `va_list` → tcc `__va_start`/`__va_arg`
  builtins; **no `va_list.c`** on arm64), `aarch64-02-asm-to-c` (every `.s`/inline-asm →
  C raw-`.int` words: syscalls `svc #0`, setjmp, crt `_init`/`_fini`, fenv, clone,
  single-thread atomics), `aarch64-03-drop-asm-barriers`. Vendored into
  `steps/musl-1.1.24/patches/`; `0006` stays shared.
- tcc `tcc-arm64-0{2,3,4}` (const-lval load/store + ftof mask; AAPCS64 varargs builtin
  loop + array/param decay; `ll` long-double suffix). Vendored into
  `steps/tcc-0.9.26/patches/`, fragments derived by `gen-arm64-patches.py`
  (verified vs GNU patch). `tcc-arm64-01` (asm wiring) was already in the repo.
- `alloca-arm64.S` (raw-word trampoline; musl ships no `alloca`) → `src/`.

### Wiring (single source, `${ARCH}`-parametrized)
- `regen.{py,sh}` now take an arch arg, partition the patch set (shared/x86_64/aarch64),
  handle `/dev/null` deletions and many `/dev/null`→`newsrc/` additions, and emit
  arch-suffixed outputs (`*.aarch64.kaem`, `generated/aarch64/`, `sysinclude.aarch64.tar`,
  `copy-newsrc.aarch64.kaem`). x86_64 outputs byte-identical to before; both arches keep
  the patch-equivalence self-check. (Made the sysinclude tar reproducible to stop churn.)
- `steps/tcc-0.9.26/pass1.kaem`: arch-split the musl unpack/patch/headers, the subset libc
  build (`-I arch/aarch64`, `sysinclude.aarch64.tar`, real `crt{i,n}.o` from the asm→C
  `crt/aarch64/crt{i,n}.c`, libtcc1 = `lib-arm64.c` + `alloca-arm64.S`), and the boot0
  relink. arm64 also applies `tcc-arm64-0{2,3,4}`.
- `steps/musl-1.1.24/pass1.kaem`: widened the `amd64`-only gate to amd64+arm64;
  `copy-newsrc.aarch64.kaem` drops the asm→C sources in; real aarch64 `crt1/crti/crtn`.
- `musl-subset.aarch64.files`: x86 list with setjmp `.s`→aarch64 `.c`, `va_list.c` dropped,
  `syscall_raw.c` added.

### Validation so far (host, no chroot — sudo unavailable here)
- `regen.py` self-check GREEN both arches (every fragment reproduces GNU patch).
- **gcc-aarch64 freestanding proxy**: the SUBSET and all **1257** full sources compile
  against the regenerated aarch64 headers; the *only* errors (78, across 21 files) are
  exactly the `__va_arg(ap, TYPE)` tcc-builtin facet gcc can't model (handled by
  `tcc-arm64-03`). Headers, asm→C sources and patched headers are all coherent.
- Static lint: every `apply-*`/`build-libc-*` fragment exists; every aarch64 source the
  build kaems reference is provided by `copy-newsrc`; no stray `x86_64` in aarch64 outputs.

### NEXT (arm64)
Run `./task5_arm64.sh` in the chroot (needs sudo + aarch64-binfmt): expect `tcc_s`/`tcc`
`-version`, the **boot2==boot3** fixed-point assertion, all 1257 full sources, and
`hello-float` → `3.000000 2.000000 1.500000`. Highest risk: tcc arm64 codegen, never yet
exercised by an actual musl build.

### Bug 1 — `tcc-boot0 -version` segfaults: subset glue never set `libc.page_size` [FIXED 2026-06-06]
First chroot run got through the seed chain and built `tcc-boot0`, but `tcc-boot0 -version`
SIGSEGV'd. Debugged on the host (binaries run via qemu-aarch64 binfmt; boot0 is static and
built `-g`):
- `qemu-aarch64-static -strace` showed `brk(NULL)` ×2 then `mmap(NULL, 0, …)=EINVAL` then
  SIGSEGV at `si_addr=0x100`.
- `gdb-multiarch` over `qemu-aarch64-static -g` gave the backtrace:
  `main → tcc_new (tcc.c:257) → tcc_mallocz → tcc_malloc → tcc_error → error1` crashing at
  `libtcc.c:517` because `error1`'s `s1` (the global `tcc_state`) is still NULL during the
  very allocation of `TCCState`. Breakpoints showed `malloc(0x618)` (correct `sizeof(TCCState)`)
  driving `__expand_heap → mmap(0,0)`.
- Root cause: `__expand_heap` rounds with `n += -n & PAGE_SIZE-1`. **aarch64 has no
  compile-time `PAGE_SIZE`** (configurable 4K/16K/64K), so `src/internal/libc.h` resolves
  `PAGE_SIZE` to the runtime `libc.page_size`. The subset's `glue/start.c` (our minimal
  `__libc_start_main`) never set it → `page_size==0` → `n += -n & (0-1)` → `n==0` → `mmap(0)`
  → first malloc fails. x86_64 has `PAGESIZE 4096` in `bits/limits.h` (constant), so amd64
  never depended on the runtime value — hence amd64 worked and arm64 didn't.
- Fix: `glue/start.c` now walks past `envp` to the aux vector and sets
  `libc.page_size = aux[AT_PAGESZ]` (exactly the line upstream `__libc_start_main` keeps),
  via `#include "libc.h"`. Arch-neutral: a harmless no-op on x86_64 (constant `PAGE_SIZE`).
  The full-musl step is unaffected (it links the real `__libc_start_main`). Verified the glue
  compiles clean against the aarch64 musl headers with the gcc-aarch64 freestanding proxy and
  that the store targets the `__libc` global. The trace also confirmed tcc's **variadic
  codegen works** (vsnprintf/vfprintf ran while formatting the error), so this was a startup
  bug, not arm64 codegen. Re-run `./task5_arm64.sh`.

### Bug 2 — truncated `.o` files / `ar` SIGSEGV: seed `tcc_cc` miscompiles aggregate init [DIAGNOSED 2026-06-06]
After Bug 1, the chroot run builds `tcc-boot0` and `tcc-boot0 -version` works, but the next
step — `tcc-boot0` rebuilding the musl subset `libc.a`
(`build-libc-subset.aarch64.kaem`, `CC=tcc-boot0`) — dies: `ar` SIGSEGVs (qemu signal 11)
because the `.o` files `tcc-boot0` produced are **truncated**, so `ar` reads past EOF.
Diagnosed entirely on the host (static aarch64 binaries run via `qemu-aarch64-static`,
disassembled with `gdb-multiarch -ex 'set arch aarch64'`).

**Symptom.** Of the 125 objects in `rootfs/tmp/musl-obj-boot0/`, ~all are short of the size
their own ELF header implies (`Start of section headers + shnum*64 > filesize`); shortfalls
vary from 64 B (one section header) to 31 KB (`src_time___tz.o`). The variance rules out
"final stdio buffer not flushed" (always < BUFSIZ) and points at the write path losing data
mid-stream.

**Proximate cause — `tcc-boot0`'s `__stdio_write` is miscompiled.** Disassembly shows it
stores all four fields of `struct iovec iovs[2]` then emits two `memset`s that **zero
`iovs[1]`** (the `{buf,len}` payload). So `writev` only flushes `iovs[0]` (data already in
the FILE buffer), the new data is dropped, and because `rem` is recomputed from the zeroed
length, `cnt==rem` succeeds and `__stdio_write` **returns `len`** — musl believes the write
fully succeeded. Hence silent, variable tail loss. (`__syscall3` is fine: prologue spills
but preserves x0–x7.)

**Root cause — the seed `tcc_cc` miscompiles `tcc.c` on arm64.** The two `memset`s are
`tccgen.c`'s `init_putz` ("put zeros at the end", `decl_initializer`/`decl_designator`). The
front-end logic is correct (hand-traced: `len` should reach `n*size1`, emitting nothing), so
this is a runtime miscompilation. Minimal repro under qemu (`tcc_s -c t.c`) shows `tcc_s`
zeroes the **last element/field of every function-local aggregate initializer**, even
fully-initialized ones — `struct v={b,n}` zeroes the last field (8 B); `int a[3]={…}` zeroes
the last int; `struct v[N]={…}` zeroes the last struct; partial inits (`struct v[2]={{…}}`)
are coincidentally correct. I.e. `tcc_s`'s `decl_designator` length bookkeeping is **off by
one element**.
- **Propagation test is decisive:** the *same* repro compiled by **`tcc-boot0` is clean**
  (4 stores, no `memset`). `tcc_s` and `tcc-boot0` share the `tcc.c`/`arm64-gen.c` source but
  are built by *different* compilers (`tcc_cc` vs `tcc_s`). So the bug is **not** in the
  shared aarch64 backend source — it is in the `tcc_s` *binary*, i.e. `tcc_cc` miscompiled
  `tcc.c`'s `decl_designator`. `tcc-boot0` (built by `tcc_s`) is itself a **correct**
  compiler because `tcc.c`'s own code never hits `tcc_s`'s buggy path.
- `tcc_cc` is a deliberately minimal seed compiler: it does **not** parse designated
  initializers (chokes on `.iov_base`) and `tcc_s` is built **without `-D HAVE_BITFIELD`**
  (the seed can't do C bitfields; `HAVE_BITFIELD` only toggles tcc's internal `struct
  Attribute` layout in `tcc.h:433`, not the init length arithmetic). `tcc-boot0` is built
  *with* `HAVE_BITFIELD=1`/`HAVE_FLOAT=1`. amd64 built clean end-to-end (Task 8), so the
  defect is specific to the **arm64 `tcc_cc` codegen**.

**Blast radius is bounded to the first (subset) `libc.a`** — only `tcc_s`-compiled,
function-local aggregate initializers are affected (globals use the `sec!=NULL` path where
`init_putz` is a no-op). The full musl (1257 files) is compiled later by the *correct*
`tcc-boot0`/`tcc`, so it is unaffected. Subset files with function-local aggregate inits:
`__stdio_write.c` (the bug), `__stdio_read.c` (readahead `iov[1]`, mostly benign),
`vsnprintf.c` (`struct cookie c={.s,.n}` → `.n` size-limit zeroed → likely breaks
`snprintf`), and the harmless `vfprintf.c`/`qsort.c`/`strstr.c` (already all-zero or
already-0 last element).

**Two fix paths (decision pending):**
1. *Proper* — make `tcc_s` correct by fixing the arm64 `tcc_cc` codegen (or rewriting
   `decl_designator` into a form `tcc_cc` compiles correctly). Robust; first libc becomes
   fully trustworthy. Requires localizing a defect in the minimal seed compiler via an
   M1/hex2 build-and-run harness under qemu — more work, touches the seed.
2. *Pragmatic* — patch the handful of subset musl sources to avoid function-local aggregate
   initializers. Contained and fast: once `tcc-boot0` has working I/O + `snprintf`, the
   `CC=tcc-boot0` step rebuilds the libc *correctly* and every later stage uses correct
   compilers. Masks the seed bug (which only ever affects these subset files).

**Decision (2026-06-06):** first scope how hard option 1 (fix `tcc_cc`/`tcc_s`) is; if too
much, fall back to option 2 (simplify the musl subset sources). The arm64 `tcc_cc` binary is
available at `rootfs/usr/bin/tcc_cc` (runs under qemu, emits M1/`.sl`).

#### Exact root cause [PINNED 2026-06-06 via gdb]
gdb on `tcc_s` under qemu (compiling `int a[2]={1,2}`) caught it. `decl_designator`'s tail is
`c += nb_elems*type_size; if (c - corig > al) al = c - corig; return al;` where `c`/`corig`
are `unsigned long` (frame offsets — **negative**, e.g. `corig = -8 = 0xFFFFFFF8`). On the
*last* element `c` reaches frame offset **0**, so true `c - corig = 0 - (-8) = +8` and `al`
should advance to 8.
- **The seed `tcc_cc` maps `long`/`unsigned long` → `int` (32-bit).** Proof: feeding
  `int bad(unsigned long c, ...)` to the real `tcc_cc` emits `.sl` declaring the param as
  `int c c =:`. So `tcc_cc` stores these vars with `str w` and loads them with **`ldr w`
  (zero-extending to 64-bit)**, yet performs the subtraction in a 64-bit X register.
- On the last element: `c`=0 loads as `0x0`, `corig`=`0xFFFFFFF8` **zero-extends** to
  `0x00000000FFFFFFF8`, so `sub` gives `0xFFFFFFFF00000008` — a huge **negative** 64-bit
  value. `c - corig > al` (signed `cmp`/`cset gt`) is then **false**, `al` is never updated,
  `decl_designator` returns the stale `al`, `len` ends one element short, and the array-level
  `if (len < n*size1) init_putz(...)` zeroes the last element. (On non-last elements `c` and
  `corig` are both `0xFFFFFFFx`, both zero-extend the same way, difference is a small
  positive — which is why only the *last* element is ever clobbered.)

#### Fix chosen — `int coff = c - corig;` in `decl_designator` (a tcc patch, not a seed change)
The mis-widened subtraction's **low 32 bits are always correct** (= the true small offset).
Forcing a 32-bit store recovers it: store `c - corig` into an `int coff`, then use `coff` in
the comparison/`init_putz`. `tcc_cc` compiles `int coff = c - corig;` as `... sub x0,x1,x0;
str w0,[coff]` — the `str w` truncates to the correct low-32 (`=8`) — and the reload is a
clean small positive, so `coff > al` is true. **Verified end-to-end**: a `bad`/`good` mimic
assembled through the real `tcc_cc → stack_c → M1 → hex2` chain disassembles to exactly this
— `bad` compares the mis-widened `sub` directly (reproduces the bug); `good` truncates via
`str w0` before comparing (correct).

This is better than the option-2 musl workaround: it makes **`tcc_s` itself correct**, so the
*first* `libc.a` (and any other function-local aggregate init anywhere) is right, not just the
handful of patched subset files. It is a small edit to `tccgen.c` `decl_designator`, correct
for every later stage too (`c - corig` is a genuinely small value there; truncating to `int`
is a no-op).

#### Patch wiring [DONE 2026-06-06]
- `steps/tcc-0.9.26/patches/tcc-arm64-05-aggregate-init.patch` — canonical unified diff
  (3 hunks in `tccgen.c` `decl_designator`: add `int ... coff;`; `coff = c - corig` before the
  holes `init_putz`; `coff = c - corig` before the tail `al` update).
- Registered in `steps/tcc-0.9.26/gen-arm64-patches.py` `PATCHSET`; regenerated the
  `simple-patches/tcc-arm64-05_tccgen.c_{00,01,02}.{before,after}` fragments. `verify OK`
  (simple-patch result == GNU `patch`, byte-for-byte).
- Wired three `simple-patch tccgen.c ...` calls into `steps/tcc-0.9.26/pass1.kaem`, inside the
  `if match ${ARCH} arm64` block (amd64/riscv64/x86 untouched).
- **Verification still pending:** a full `./task5_arm64.sh` (needs sudo + aarch64 binfmt). It
  `rm -rf rootfs` and rebuilds from scratch, re-applying all patches via `pass1.kaem`. Success
  criteria: every `.o` in `rootfs/tmp/musl-obj-boot0/` well-formed, `ar` completes, `boot2 ==
  boot3`, full musl (1257 files) builds, `hello-float` prints `3.000000 2.000000 1.500000`.
  Also re-disassemble the rebuilt `tcc-boot0`'s `__stdio_write` and confirm the two spurious
  `memset`s are gone. (A host-only rebuild of just `tcc_s` is awkward because `tcc_cc`'s
  invocation uses chroot-absolute paths `/src`, `/usr/include/mes`; not worth fighting — run
  task5 instead.)

#### The real bug is one layer earlier — fixing the seed tools (would make patch 05 redundant)
Patch 05 lives in `tcc` (`tccgen.c`) only because it is the cheapest place to dodge the defect.
The defect itself is **not in tcc** — tcc 0.9.26's `decl_designator` is correct C (it builds
clean on amd64 and when compiled by any correct compiler). The bug is in this project's **own
in-tree seed tools** (`src/tcc_cc.c` front-end + the `stack_c` backend, `src/stack_c_*.c`); both
are hand-written here (see `docs/tcc_cc.html`, `docs/Stack_C.html`), so there is nothing to send
to an external upstream. To remove patch 05 entirely, fix it one layer earlier in either tool:

1. **`stack_c` backend (root cause, most general fix).** `stack_c` lowers a 4-byte (`?4`)
   value load as a **zero-extending** `ldr w` into a 64-bit X register, then runs the operator
   (`-`) and the signed compare (`>s`) at **64-bit** width. So `int - int` whose result should
   wrap mod 2^32 instead goes through a full 64-bit subtraction; when an operand has bit 31 set
   (a negative frame offset like `-8 = 0xFFFFFFF8`), zero-extension turns it into a large
   positive 64-bit number and the signed result/comparison is wrong. Fix: make `?4`-width
   integer arithmetic 32-bit-correct — either operate in `W` registers (`sub w,w,w`; `cmp w,w`)
   for `?4` operands, or **sign-extend signed 4-byte loads** (`ldrsw`) instead of zero-extending
   so `0xFFFFFFF8` loads as `-8`. This corrects *every* 32-bit signed computation that crosses
   the sign boundary, not just `decl_designator`. (Evidence in the `bad`/`good` mimic below:
   `bad` = `ldr w; ldr w; sub x; cmp x; cset gt`; `good` only differs by an intervening
   `str w` that truncates back to 32 bits.)

2. **`tcc_cc` front-end (ABI-correct alternative).** `tcc_cc` maps plain `long`/`unsigned long`
   → 32-bit `int` (proof: it emits `int c c =:` for an `unsigned long c` param, hence the `?4`
   loads). aarch64 is LP64, so `long` should be 8 bytes. If `tcc_cc` typed `long` as 64-bit,
   `c`/`corig` would be `?8` (`ldr x`, true 64-bit subtraction) and the result would be correct
   regardless of the `stack_c` issue. This is the ABI-correct fix but more invasive: it changes
   `sizeof(long)` and struct layouts for everything `tcc_cc` compiles (only the seed tools, which
   today all assume `long==int`, so they'd need an audit). `tcc_cc` already handles `long long`/
   `LL` 64-bit arithmetic (see git log "no 'long' was generated for negative constants with LL
   postfix", ">> for 64 bits"), so the machinery exists; plain `long` just isn't wired to it.

Either fix is in-tree and would let patch 05 (and its `simple-patches` fragments + `pass1.kaem`
wiring) be deleted. Option 1 (`stack_c`) is recommended: smaller blast radius for the layout
ABI, and it eliminates a whole *class* of latent sign-boundary miscompiles in the seed.

#### How to reproduce / re-derive from scratch (future session)
All binaries are static aarch64 ELF; run on an x86_64 host via `qemu-aarch64-static`.
1. **Repro the miscompile** (any function-local aggregate init triggers it):
   ```sh
   printf 'int f(){int a[2]={1,2};return a[1];}\n' > t.c
   qemu-aarch64-static rootfs/usr/bin/tcc_s -c t.c -o t.o
   aarch64-linux-gnu-objdump -d t.o | sed -n '/<f>:/,/ret/p'   # spurious bl <memset> near the end
   ```
   Cross-check `tcc-boot0` on the same `t.c` → **clean** (no memset): confirms the bug is in the
   `tcc_s` *binary* (i.e. how `tcc_cc` built it), not in the shared `tcc.c`/`arm64-gen.c` source.
2. **Pin it with gdb** (watch `decl_designator` return the stale `al`):
   ```sh
   qemu-aarch64-static -g 1234 rootfs/usr/bin/tcc_s -c t.c -o t.o &
   # symbols are blood-elf-mangled & size 0: f_decl_designator, f_init_putz (objdump -t)
   gdb-multiarch -q rootfs/usr/bin/tcc_s -ex 'target remote :1234' \
     -ex 'break *<addr of decl_designator ret>' \
     -ex 'commands' -ex 'printf "al=%d c=%lu corig=%lu\n",*(int*)($x17+0x8),...' ...
   ```
   The last element shows `c=0`, `corig=0xFFFFFFF8`, returns the stale `al` (4 not 8).
3. **Prove the seed types `long` as `int`** and that the fix truncates correctly — assemble a
   mimic through the *real* seed chain and disassemble:
   ```sh
   # mimic.c: bad() uses `c-corig` directly; good() does `int coff=c-corig;` first
   qemu-aarch64-static rootfs/usr/bin/tcc_cc -a arm64 -o mimic.sl mimic.c   # note: `int c c =:`
   qemu-aarch64-static rootfs/usr/bin/stack_c -i src/stack_c_intro_arm64.M1 mimic.sl -o mimic.M1
   qemu-aarch64-static rootfs/usr/bin/blood-elf -a arm64 --file mimic.M1 --little-endian --output mimic.be
   qemu-aarch64-static rootfs/usr/bin/M1 mimic.M1 -o mimic.macro
   qemu-aarch64-static rootfs/usr/bin/hex2 -o mimic.elf M2libc/aarch64/ELF-aarch64-debug.hex2 mimic.macro mimic.be
   aarch64-linux-gnu-objdump -d mimic.elf   # f_bad: cmp on 64-bit sub; f_good: str w truncates first
   ```
4. **Regenerate the patch** if `tccgen.c` line numbers drift: edit a pristine
   `tcc-0.9.26-1147-gee75a10c/tccgen.c`, `diff -u` to refresh
   `patches/tcc-arm64-05-aggregate-init.patch`, then
   `python3 steps/tcc-0.9.26/gen-arm64-patches.py <pristine-tcc-srcdir>` (must print `verify OK`).
