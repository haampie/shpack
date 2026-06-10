/* aarch64 __set_thread_area for tcc 0.9.26.
   msr tpidr_el0,x0   d51bd040
   mov w0,#0          52800000
   ret                d65f03c0
*/
__asm__(
    ".text\n"
    ".balign 4\n"
    ".global __set_thread_area\n"
    ".hidden __set_thread_area\n"
    ".type   __set_thread_area,@function\n"
    "__set_thread_area:\n"
    ".int 0xd51bd040\n"
    ".int 0x52800000\n"
    ".int 0xd65f03c0\n"
);
