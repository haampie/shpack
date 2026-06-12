/* aarch64 __clone for tcc 0.9.26.  Raw words; encodings via llvm-mc.
 * __clone(func, stack, flags, arg, ptid, tls, ctid) -> Linux clone svc. */
__asm__(
    ".text\n.balign 4\n"
    ".global __clone\n.hidden __clone\n"
    ".type __clone,@function\n"
    "__clone:\n"
    ".int 0x927cec21\n"   /* and x1, x1, #-16          */
    ".int 0xa9bf0c20\n"   /* stp x0, x3, [x1, #-16]!   */
    ".int 0xd3407c40\n"   /* uxtw x0, w2               */
    ".int 0xaa0403e2\n"   /* mov x2, x4                */
    ".int 0xaa0503e3\n"   /* mov x3, x5                */
    ".int 0xaa0603e4\n"   /* mov x4, x6                */
    ".int 0xd2801b88\n"   /* mov x8, #220 (SYS_clone)  */
    ".int 0xd4000001\n"   /* svc #0                    */
    ".int 0xb4000040\n"   /* cbz x0, 1f (offset +8)    */
    ".int 0xd65f03c0\n"   /* ret  (parent)             */
    /* 1: child */
    ".int 0xa8c103e1\n"   /* ldp x1, x0, [sp], #16     */
    ".int 0xd63f0020\n"   /* blr x1                    */
    ".int 0xd2800ba8\n"   /* mov x8, #93  (SYS_exit)   */
    ".int 0xd4000001\n"   /* svc #0                    */
);
