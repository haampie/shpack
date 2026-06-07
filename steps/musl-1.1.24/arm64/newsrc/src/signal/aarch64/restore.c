/* aarch64 signal trampolines for tcc 0.9.26.

   Raw instruction words: tcc has no AArch64 instruction assembler.
   Encodings verified with llvm-mc --triple=aarch64.

   These are sigreturn trampolines — the kernel jumps here after a
   signal handler returns; they invoke rt_sigreturn so the syscall
   never returns to userspace. */

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global __restore\n"
    ".hidden __restore\n"
    ".type __restore,@function\n"
    "__restore:\n"
    ".global __restore_rt\n"
    ".hidden __restore_rt\n"
    ".type __restore_rt,@function\n"
    "__restore_rt:\n"
    ".int 0xd2801168\n"   /* mov x8, #139  (SYS_rt_sigreturn) */
    ".int 0xd4000001\n"   /* svc #0                            */
);
