/* aarch64 cancellable syscall stub for tcc 0.9.26 hermetic bootstrap.
 * Hello-world does not exercise cancellation; threaded programs that
 * rely on PTHREAD_CANCEL_ASYNCHRONOUS will not see the cancel points. */
extern long __syscall6(long, long, long, long, long, long, long);

long __syscall_cp_asm(volatile void *cancel, long nr,
                      long a, long b, long c, long d, long e, long f)
{
    (void)cancel;
    return __syscall6(nr, a, b, c, d, e, f);
}

/* The cancel-region markers are referenced by the cancellation handler
 * to detect whether a thread was inside a cancellable syscall.  We
 * provide weak no-op definitions so the link succeeds. */
__asm__(
    ".text\n.balign 4\n"
    ".global __cp_begin\n.hidden __cp_begin\n"
    ".global __cp_end\n.hidden __cp_end\n"
    ".global __cp_cancel\n.hidden __cp_cancel\n"
    "__cp_begin:\n__cp_end:\n__cp_cancel:\n"
    ".int 0xd65f03c0\n"   /* ret */
);
