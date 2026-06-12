/* aarch64 TLS-descriptor entries for tcc 0.9.26.

   Raw instruction words: tcc has no AArch64 instruction assembler.
   Encodings verified with llvm-mc --triple=aarch64.

   These match a non-standard ABI (only x0 is live on entry/exit; x1
   and x2 must be preserved by the callee), so they cannot be written
   as plain C functions. */

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global __tlsdesc_static\n"
    ".hidden __tlsdesc_static\n"
    ".type __tlsdesc_static,@function\n"
    "__tlsdesc_static:\n"
    ".int 0xf9400400\n"   /* ldr x0, [x0, #8] */
    ".int 0xd65f03c0\n"   /* ret              */
);

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global __tlsdesc_dynamic\n"
    ".hidden __tlsdesc_dynamic\n"
    ".type __tlsdesc_dynamic,@function\n"
    "__tlsdesc_dynamic:\n"
    ".int 0xa9bf0be1\n"   /* stp x1, x2, [sp, #-16]! */
    ".int 0xd53bd041\n"   /* mrs x1, tpidr_el0       */
    ".int 0xf9400400\n"   /* ldr x0, [x0, #8]        */
    ".int 0xa9400800\n"   /* ldp x0, x2, [x0]        */
    ".int 0xcb010042\n"   /* sub x2, x2, x1          */
    ".int 0xf85f8021\n"   /* ldur x1, [x1, #-8]      */
    ".int 0xf8607821\n"   /* ldr x1, [x1, x0, lsl #3] */
    ".int 0x8b020020\n"   /* add x0, x1, x2          */
    ".int 0xa8c10be1\n"   /* ldp x1, x2, [sp], #16   */
    ".int 0xd65f03c0\n"   /* ret                     */
);
