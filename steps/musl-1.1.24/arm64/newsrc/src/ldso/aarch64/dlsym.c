/* aarch64 dlsym wrapper for tcc 0.9.26.  Original asm does a tail call
 * to __dlsym with the return-address in x2; we use the C builtin. */
extern void *__dlsym(void *restrict, const char *restrict, void *);
void *dlsym(void *restrict p, const char *restrict s)
{
    return __dlsym(p, s, __builtin_return_address(0));
}
