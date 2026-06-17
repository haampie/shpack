# vendor/

Layers of the software stack this project drives but did not invent. The
contribution lives in `shpack/`; everything here is taken from an upstream
project and, where noted, patched to make it bootstrappable or faster. Each
layer keeps its upstream license and (where the original carries one) its
copyright headers.

## `mes-replacement/`

The seed C-compiler layer, from Frans Faase's
[MES-replacement](https://github.com/FransFaase/MES-replacement). It replaces
GNU Mes's detour through Scheme with a small C compiler (`tcc_cc.c`) that emits
a stack-machine IR, plus a transpiler (`stack_c_<arch>.c`) that lowers that IR
to assembly. Together they grow tcc 0.9.26 and musl directly out of
stage0-posix. Modified here to be bootstrappable from **M2-Planet** (the
stage0-posix C subset) and extended for AArch64.

Contents:

- `tcc_cc.c` — the seed C compiler.
- `stack_c_<arch>.c` — stack-IR → assembly transpiler (amd64, aarch64).
- `stdlib.c`, `bootstrappable.c`, `sys_syscall.h` — minimal runtime/syscall glue.
- `aarch64-asm.c` — a dummy tcc arm64 assembler (data directives only; tcc
  0.9.26 ships none).
- `alloca-aarch64.S` — an AArch64 `alloca` trampoline (raw opcode words; the
  fork's tcc lowers `alloca(n)` to `bl alloca` and musl ships no such symbol).
- **Committed binary seeds**: `tcc_cc.<arch>.sl64` (+ `.sha256` pins) and
  `stack_c_intro_<arch>.M1`. These are the only prebuilt artifacts in the repo;
  `check-tools.kaem` re-derives `tcc_cc.<arch>.sl64` in-chroot and gates it
  against the committed sha256.

## `kaem/`

mescc-tools' `kaem` minimal shell (the kaem-phase interpreter), vendored from
**mescc-tools 1.7.0** (`stage0-posix/mescc-tools/Kaem/`) and optimized to avoid
per-command `malloc`. Upstream kaem `calloc`s a fresh buffer per token and
rebuilds argv/envp on every exec (~52 `calloc`/command); since M2libc's malloc
never frees and `brk`s per call, that is ~52 `brk`/command, making kaem 3–10×
slower than dash. This copy reuses per-command token/string pools, caches the
envp array, and stops copying argv, driving per-command `brk` toward 0. It also
raises `MAX_ARRAY` to 4096 (musl's full-libc `ar` line lists ~1260 objects in
one command, and `tcc -ar` can't split). Output is byte-identical, gated on the
musl `libc.a` sha256. Staging (`stage.sh`) drops these files over the staged
submodule copy (`mescc-tools/Kaem/`), which stays pristine. Still compiled by M2-Planet,
so it stays within that C subset. See the header comment in `kaem.c`.

## `stage0-posix/`

Submodule, [oriansj/stage0-posix](https://github.com/oriansj/stage0-posix) at
Release_1.9.1. The upstream binary seeds and the hex0/M1/M2 bring-up chain
(mescc-tools, M2-Planet, M2-Mesoplanet, M2libc). Pristine — local
modifications are layered on at stage time by `stage.sh`, never committed into
the submodule.
