/* SPDX-License-Identifier: MIT
 *
 * Glue for the stripped musl 1.1.24 subset used to bootstrap tcc.
 *
 * tcc's set_exception_handler() (tccrun.c, compiled on a native x86_64 build)
 * references sigaction(). That function is only *called* under
 * CONFIG_TCC_BACKTRACE, which the bootstrap tcc does NOT define, so the
 * reference survives only as dead code -- it must resolve at link time but is
 * never executed. A no-op sigaction is therefore sufficient, and lets us avoid
 * vendoring real musl sigaction (which drags in __libc_sigaction, the
 * __restore_rt sigreturn trampoline, sigprocmask, the __abort_lock LOCK path
 * and the libc global). GNU mes ships an equivalent stub in lib/stub/.
 *
 * NOTE: this stub is ONLY for the tcc-building subset. Programs that need real
 * signal handling (e.g. GNU make) are meant to be compiled against the full
 * musl 1.1.24 produced later in the chain, where sigaction is the real thing.
 *
 * sigemptyset() is the real, self-contained musl src/signal/sigemptyset.c
 * (vendored via the build), so only sigaction needs stubbing here.
 */

struct sigaction;

int sigaction(int sig, const struct sigaction *sa, struct sigaction *old)
{
	(void)sig; (void)sa; (void)old;
	return 0;
}
