/* aarch64 __unmapself for tcc 0.9.26.
   mov x8,#215 (munmap)   d2801ae8
   svc 0                  d4000001
   mov x8,#93  (exit)     d2800ba8
   svc 0                  d4000001
*/
__asm__(
    ".text\n"
    ".balign 4\n"
    ".global __unmapself\n"
    ".type   __unmapself,@function\n"
    "__unmapself:\n"
    ".int 0xd2801ae8\n"
    ".int 0xd4000001\n"
    ".int 0xd2800ba8\n"
    ".int 0xd4000001\n"
);
