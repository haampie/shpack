/* aarch64 sigsetjmp stub for tcc 0.9.26 hermetic bootstrap.
 * The real impl requires `bl setjmp` / `b __sigsetjmp_tail` (extern
 * branches that tcc cannot encode).  Hello-world does not call this;
 * threaded programs using siglongjmp will not work with this libc. */
extern int setjmp(void *);
int sigsetjmp(void *env, int savemask) { (void)savemask; return setjmp(env); }
int __sigsetjmp(void *env, int savemask) { (void)savemask; return setjmp(env); }
