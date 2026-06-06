/* aarch64 crtn for tcc 0.9.26: close out the .init/.fini functions.
   ldp x29,x30,[sp],#16    0xa8c17bfd
   ret                     0xd65f03c0
*/
__asm__(
    ".section .init\n"
    ".int 0xa8c17bfd\n"
    ".int 0xd65f03c0\n"
);

__asm__(
    ".section .fini\n"
    ".int 0xa8c17bfd\n"
    ".int 0xd65f03c0\n"
);
