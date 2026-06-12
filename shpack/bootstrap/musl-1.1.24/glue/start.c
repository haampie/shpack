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
 * This is paired with musl's own crt/crt1.c + crt/${ARCH}/crt_arch.h, which
 * define _start and call _start_c() -> __libc_start_main(main, argc, argv, ...).
 * crt1.c passes extra (init/fini) arguments; under both the SysV AMD64 and the
 * AAPCS64 ABIs the unused register arguments are simply ignored, so the
 * 3-argument definition is safe.
 *
 * The one piece of __libc_start_main we MUST keep is setting libc.page_size from
 * the aux vector (AT_PAGESZ). On archs without a compile-time PAGE_SIZE -- such
 * as aarch64, where the page size is configurable (4K/16K/64K) -- musl resolves
 * PAGE_SIZE to the runtime libc.page_size (src/internal/libc.h). malloc's
 * __expand_heap() rounds each request up with `n += -n & PAGE_SIZE-1`, so a zero
 * page_size rounds the size to 0 and the very first malloc mmaps 0 bytes (EINVAL
 * -> NULL -> tcc_error -> crash). On x86_64 PAGE_SIZE is the constant 4096 and
 * libc.page_size is unused, so this loop is harmless there.
 */

#include "libc.h"		/* struct __libc / libc / page_size, size_t */

#define AT_PAGESZ 6

extern char **__environ;

int __libc_start_main(int (*main)(int, char **, char **), int argc, char **argv)
{
	char **envp = argv + argc + 1;
	size_t i, *auxv;
	__environ = envp;
	for (i = 0; envp[i]; i++);
	libc.auxv = auxv = (void *)(envp + i + 1);
	for (i = 0; auxv[i]; i += 2)
		if (auxv[i] == AT_PAGESZ)
			libc.page_size = auxv[i + 1];
	exit(main(argc, argv, envp));
	return 0;
}
