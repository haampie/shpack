/* aarch64 crti for tcc 0.9.26: no instruction assembler, so emit the
   .init/.fini function prologues as raw .int words.
   stp x29,x30,[sp,#-16]!  0xa9bf7bfd
   mov x29,sp              0x910003fd
*/
__asm__(
    ".section .init\n"
    ".balign 4\n"
    ".global _init\n"
    ".type _init,@function\n"
    "_init:\n"
    ".int 0xa9bf7bfd\n"
    ".int 0x910003fd\n"
);

__asm__(
    ".section .fini\n"
    ".balign 4\n"
    ".global _fini\n"
    ".type _fini,@function\n"
    "_fini:\n"
    ".int 0xa9bf7bfd\n"
    ".int 0x910003fd\n"
);
