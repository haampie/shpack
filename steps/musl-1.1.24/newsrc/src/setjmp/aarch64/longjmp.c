/* aarch64 longjmp for tcc 0.9.26.  Raw words; encodings via llvm-mc. */
__asm__(
    ".text\n.balign 4\n"
    ".global _longjmp\n.global longjmp\n"
    ".type _longjmp,@function\n.type longjmp,@function\n"
    "_longjmp:\nlongjmp:\n"
    ".int 0xa9405013\n"   /* ldp x19, x20, [x0]        */
    ".int 0xa9415815\n"   /* ldp x21, x22, [x0, #16]   */
    ".int 0xa9426017\n"   /* ldp x23, x24, [x0, #32]   */
    ".int 0xa9436819\n"   /* ldp x25, x26, [x0, #48]   */
    ".int 0xa944701b\n"   /* ldp x27, x28, [x0, #64]   */
    ".int 0xa945781d\n"   /* ldp x29, x30, [x0, #80]   */
    ".int 0xf9403402\n"   /* ldr x2, [x0, #104]        */
    ".int 0x9100005f\n"   /* mov sp, x2                */
    ".int 0x6d472408\n"   /* ldp d8, d9, [x0, #112]    */
    ".int 0x6d482c0a\n"   /* ldp d10, d11, [x0, #128]  */
    ".int 0x6d49340c\n"   /* ldp d12, d13, [x0, #144]  */
    ".int 0x6d4a3c0e\n"   /* ldp d14, d15, [x0, #160]  */
    ".int 0xaa0103e0\n"   /* mov x0, x1                */
    ".int 0xb5000041\n"   /* cbnz x1, 1f (offset +8)   */
    ".int 0xd2800020\n"   /* mov x0, #1                */
    /* 1: */
    ".int 0xd61f03c0\n"   /* br x30                    */
);
