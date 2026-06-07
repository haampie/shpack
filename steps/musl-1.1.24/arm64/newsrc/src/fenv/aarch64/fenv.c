/* aarch64 fenv accessors for tcc 0.9.26.

   Raw instruction words: tcc has no AArch64 instruction assembler.
   Encodings verified with llvm-mc --triple=aarch64. */

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global fegetround\n"
    ".type fegetround,@function\n"
    "fegetround:\n"
    ".int 0xd53b4400\n"   /* mrs x0, fpcr        */
    ".int 0x120a0400\n"   /* and w0, w0, #0xc00000 */
    ".int 0xd65f03c0\n"   /* ret                 */
);

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global __fesetround\n"
    ".hidden __fesetround\n"
    ".type __fesetround,@function\n"
    "__fesetround:\n"
    ".int 0xd53b4401\n"   /* mrs x1, fpcr        */
    ".int 0x12087421\n"   /* and w1, w1, #0xff3fffff  (bic w1,w1,#0xc00000) */
    ".int 0x2a000021\n"   /* orr w1, w1, w0      */
    ".int 0xd51b4401\n"   /* msr fpcr, x1        */
    ".int 0x52800000\n"   /* mov w0, #0          */
    ".int 0xd65f03c0\n"   /* ret                 */
);

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global fetestexcept\n"
    ".type fetestexcept,@function\n"
    "fetestexcept:\n"
    ".int 0x12001000\n"   /* and w0, w0, #0x1f   */
    ".int 0xd53b4421\n"   /* mrs x1, fpsr        */
    ".int 0x0a010000\n"   /* and w0, w0, w1      */
    ".int 0xd65f03c0\n"   /* ret                 */
);

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global feclearexcept\n"
    ".type feclearexcept,@function\n"
    "feclearexcept:\n"
    ".int 0x12001000\n"   /* and w0, w0, #0x1f   */
    ".int 0xd53b4421\n"   /* mrs x1, fpsr        */
    ".int 0x0a200021\n"   /* bic w1, w1, w0      */
    ".int 0xd51b4421\n"   /* msr fpsr, x1        */
    ".int 0x52800000\n"   /* mov w0, #0          */
    ".int 0xd65f03c0\n"   /* ret                 */
);

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global feraiseexcept\n"
    ".type feraiseexcept,@function\n"
    "feraiseexcept:\n"
    ".int 0x12001000\n"   /* and w0, w0, #0x1f   */
    ".int 0xd53b4421\n"   /* mrs x1, fpsr        */
    ".int 0x2a000021\n"   /* orr w1, w1, w0      */
    ".int 0xd51b4421\n"   /* msr fpsr, x1        */
    ".int 0x52800000\n"   /* mov w0, #0          */
    ".int 0xd65f03c0\n"   /* ret                 */
);

__asm__(
    ".text\n"
    ".balign 4\n"
    ".global fegetenv\n"
    ".type fegetenv,@function\n"
    "fegetenv:\n"
    ".int 0xd53b4401\n"   /* mrs x1, fpcr        */
    ".int 0xd53b4422\n"   /* mrs x2, fpsr        */
    ".int 0x29000801\n"   /* stp w1, w2, [x0]    */
    ".int 0x52800000\n"   /* mov w0, #0          */
    ".int 0xd65f03c0\n"   /* ret                 */
);

/* fesetenv: TODO preserve some bits.  Branch offset for `b.eq 1f` is
   +3 instructions (12 bytes) past the b.eq itself. */
__asm__(
    ".text\n"
    ".balign 4\n"
    ".global fesetenv\n"
    ".type fesetenv,@function\n"
    "fesetenv:\n"
    ".int 0xd2800001\n"   /* mov x1, #0          */
    ".int 0xd2800002\n"   /* mov x2, #0          */
    ".int 0xb100041f\n"   /* cmn x0, #1          */
    ".int 0x54000040\n"   /* b.eq 1f  (offset +8 = skip ldp) */
    ".int 0x29400801\n"   /* ldp w1, w2, [x0]    */
    /* 1: */
    ".int 0xd51b4401\n"   /* msr fpcr, x1        */
    ".int 0xd51b4422\n"   /* msr fpsr, x2        */
    ".int 0x52800000\n"   /* mov w0, #0          */
    ".int 0xd65f03c0\n"   /* ret                 */
);
