/* SPDX-License-Identifier: MIT
 *
 * Glue for the stripped musl 1.1.24 subset used to bootstrap tcc.
 *
 * Replaces musl's src/errno/__errno_location.c. Upstream musl stores errno in
 * the thread-control-block (errno = *__errno_location(), and __errno_location()
 * returns &__pthread_self()->errno_val). That dereferences the thread pointer,
 * which would force us to run __init_tls() at startup. The bootstrap tcc is
 * single-threaded and only touches errno trivially, so we keep errno in a plain
 * global and skip TLS setup entirely (see glue/start.c).
 *
 * Two accessors are provided on purpose:
 *   __errno_location  - the public name (include/errno.h)
 *   ___errno_location - the internal hidden name musl's own .c files call
 *                       (src/include/errno.h: `hidden int *___errno_location()`,
 *                       #define errno (*___errno_location())).
 */

static int __errno_storage;

int *__errno_location(void) { return &__errno_storage; }

__attribute__((__visibility__("hidden")))
int *___errno_location(void) { return &__errno_storage; }
