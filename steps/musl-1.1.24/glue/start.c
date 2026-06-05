/* SPDX-License-Identifier: MIT
 *
 * Glue for the stripped musl 1.1.24 subset used to bootstrap tcc.
 *
 * Replaces musl's src/env/__libc_start_main.c with a minimal version. Upstream
 * __libc_start_main() parses the aux vector, runs __init_tls() / __init_ssp(),
 * does the set*id security check (poll on fds 0/1/2) and runs init arrays. None
 * of that is needed for the single-threaded bootstrap tcc, and __init_tls would
 * drag in the TLS machinery we deliberately avoid (errno is a plain global, see
 * glue/errno_loc.c).
 *
 * This is paired with musl's own crt/crt1.c + crt/x86_64/crt_arch.h, which
 * define _start and call _start_c() -> __libc_start_main(main, argc, argv, ...).
 * crt1.c passes extra (init/fini) arguments; under the SysV AMD64 ABI the unused
 * register arguments are simply ignored, so the 3-argument definition is safe.
 */

extern char **__environ;
extern void exit(int);

int __libc_start_main(int (*main)(int, char **, char **), int argc, char **argv)
{
	char **envp = argv + argc + 1;
	__environ = envp;
	exit(main(argc, argv, envp));
	return 0;
}
