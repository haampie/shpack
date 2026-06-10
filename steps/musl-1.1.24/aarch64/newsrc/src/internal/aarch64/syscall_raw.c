/* aarch64 Linux syscall wrappers, raw-encoded for tcc 0.9.26.
 *
 * tcc has no AArch64 assembler and no support for inline-asm operand
 * constraints, so musls inline "register long x8 __asm__("x8") = n" trick
 * is unavailable.  Instead we expose these as out-of-line functions and
 * emit raw instruction words via __asm__(".int 0x..").
 *
 * AAPCS64 places incoming args in x0..x7.  Linux aarch64 syscall ABI
 * wants the number in x8 and args in x0..x5, so each wrapper moves
 * x0 -> x8 (number) and shifts the remaining arguments down by one.
 * tccs aarch64 prologue ("stp x29,x30,[sp,#-224]!; mov x29,sp") and
 * epilogue ("mov sp,x29; ldp x29,x30,[sp],#224; ret") preserve x0..x7,
 * so the post-svc x0 flows out as the C return value.
 *
 * Encodings (verified with llvm-mc --triple=aarch64):
 *   mov x8,x0 = 0xaa0003e8   mov x3,x4 = 0xaa0403e3
 *   mov x0,x1 = 0xaa0103e0   mov x4,x5 = 0xaa0503e4
 *   mov x1,x2 = 0xaa0203e1   mov x5,x6 = 0xaa0603e5
 *   mov x2,x3 = 0xaa0303e2   svc #0    = 0xd4000001
 */

long __syscall0(long n)
{
	__asm__(".int 0xaa0003e8"); /* mov x8, x0 */
	__asm__(".int 0xd4000001"); /* svc #0     */
}

long __syscall1(long n, long a)
{
	__asm__(".int 0xaa0003e8"); /* mov x8, x0 */
	__asm__(".int 0xaa0103e0"); /* mov x0, x1 */
	__asm__(".int 0xd4000001"); /* svc #0     */
}

long __syscall2(long n, long a, long b)
{
	__asm__(".int 0xaa0003e8"); /* mov x8, x0 */
	__asm__(".int 0xaa0103e0"); /* mov x0, x1 */
	__asm__(".int 0xaa0203e1"); /* mov x1, x2 */
	__asm__(".int 0xd4000001"); /* svc #0     */
}

long __syscall3(long n, long a, long b, long c)
{
	__asm__(".int 0xaa0003e8"); /* mov x8, x0 */
	__asm__(".int 0xaa0103e0"); /* mov x0, x1 */
	__asm__(".int 0xaa0203e1"); /* mov x1, x2 */
	__asm__(".int 0xaa0303e2"); /* mov x2, x3 */
	__asm__(".int 0xd4000001"); /* svc #0     */
}

long __syscall4(long n, long a, long b, long c, long d)
{
	__asm__(".int 0xaa0003e8"); /* mov x8, x0 */
	__asm__(".int 0xaa0103e0"); /* mov x0, x1 */
	__asm__(".int 0xaa0203e1"); /* mov x1, x2 */
	__asm__(".int 0xaa0303e2"); /* mov x2, x3 */
	__asm__(".int 0xaa0403e3"); /* mov x3, x4 */
	__asm__(".int 0xd4000001"); /* svc #0     */
}

long __syscall5(long n, long a, long b, long c, long d, long e)
{
	__asm__(".int 0xaa0003e8"); /* mov x8, x0 */
	__asm__(".int 0xaa0103e0"); /* mov x0, x1 */
	__asm__(".int 0xaa0203e1"); /* mov x1, x2 */
	__asm__(".int 0xaa0303e2"); /* mov x2, x3 */
	__asm__(".int 0xaa0403e3"); /* mov x3, x4 */
	__asm__(".int 0xaa0503e4"); /* mov x4, x5 */
	__asm__(".int 0xd4000001"); /* svc #0     */
}

long __syscall6(long n, long a, long b, long c, long d, long e, long f)
{
	__asm__(".int 0xaa0003e8"); /* mov x8, x0 */
	__asm__(".int 0xaa0103e0"); /* mov x0, x1 */
	__asm__(".int 0xaa0203e1"); /* mov x1, x2 */
	__asm__(".int 0xaa0303e2"); /* mov x2, x3 */
	__asm__(".int 0xaa0403e3"); /* mov x3, x4 */
	__asm__(".int 0xaa0503e4"); /* mov x4, x5 */
	__asm__(".int 0xaa0603e5"); /* mov x5, x6 */
	__asm__(".int 0xd4000001"); /* svc #0     */
}

/* Thread-pointer read used by __pthread_self.  Out-of-line because tcc
 * cannot bind an inline-asm result to a C variable.  Encoding:
 *   mrs x0, tpidr_el0 = 0xd53bd040
 * tccs prologue/epilogue do not touch x0, so the register value flows
 * out as the return value.
 */
void *__aarch64_read_tp(void)
{
	__asm__(".int 0xd53bd040"); /* mrs x0, tpidr_el0 */
}
