/* SPDX-License-Identifier: MIT
 *
 * AArch64 alloca, the analogue of upstream tcc's lib/alloca86_64.S. The
 * bootstrappable tcc 0.9.26 fork does not inline alloca(); a source-level
 * alloca(n) compiles to `bl alloca` (size in x0, result in x0). musl ships no
 * such symbol, so this trampoline supplies it. tcc's arm64 assembler accepts
 * only .int/.word data directives, so each instruction is its raw little-endian
 * opcode -- the exact encodings arm64-gen.c emits for VLAs. It is a leaf
 * function: on AArch64 the return address is in x30 (not on the stack, unlike
 * x86's pop/repush), and the lowered sp is reclaimed for free by every caller's
 * `mov sp,x29` epilogue (arm64-gen.c gfunc_epilog).
 */
.globl alloca
alloca:
    .int 0x91003c00   /* add x0, x0, #15   ; round the request size up... */
    .int 0x927cec00   /* bic x0, x0, #15   ; ...to a multiple of 16        */
    .int 0xcb2063ff   /* sub sp, sp, x0    ; grow the stack                */
    .int 0x910003e0   /* mov x0, sp        ; return a pointer to the block */
    .int 0xd65f03c0   /* ret               ; br x30                        */
