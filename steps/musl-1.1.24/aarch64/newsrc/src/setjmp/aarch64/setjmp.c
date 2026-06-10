/* aarch64 setjmp for tcc 0.9.26.  Raw words; encodings via llvm-mc.
 * AAPCS64 callee-saved: x19-x30, sp, d8-d15. */
__asm__(
    ".text\n.balign 4\n"
    ".global __setjmp\n.global _setjmp\n.global setjmp\n"
    ".type __setjmp,@function\n.type _setjmp,@function\n.type setjmp,@function\n"
    "__setjmp:\n_setjmp:\nsetjmp:\n"
    ".int 0xa9005013\n"   /* stp x19, x20, [x0]        */
    ".int 0xa9015815\n"   /* stp x21, x22, [x0, #16]   */
    ".int 0xa9026017\n"   /* stp x23, x24, [x0, #32]   */
    ".int 0xa9036819\n"   /* stp x25, x26, [x0, #48]   */
    ".int 0xa904701b\n"   /* stp x27, x28, [x0, #64]   */
    ".int 0xa905781d\n"   /* stp x29, x30, [x0, #80]   */
    ".int 0x910003e2\n"   /* mov x2, sp                */
    ".int 0xf9003402\n"   /* str x2, [x0, #104]        */
    ".int 0x6d072408\n"   /* stp d8, d9, [x0, #112]    */
    ".int 0x6d082c0a\n"   /* stp d10, d11, [x0, #128]  */
    ".int 0x6d09340c\n"   /* stp d12, d13, [x0, #144]  */
    ".int 0x6d0a3c0e\n"   /* stp d14, d15, [x0, #160]  */
    ".int 0xd2800000\n"   /* mov x0, #0                */
    ".int 0xd65f03c0\n"   /* ret                       */
);
