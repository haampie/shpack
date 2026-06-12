/* SPDX-License-Identifier: MIT
 *
 * Smoke test for the freshly built tcc 0.9.27 (aarch64): compile + static link
 * + run. No float, so it only needs the subset libc.a present at this point in
 * the bootstrap (full musl is rebuilt by the next step). A nonzero exit or a
 * failed link aborts the kaem step.
 */
#include <stdio.h>

int main(void)
{
	printf("tcc 0.9.27 aarch64 smoke test ok\n");
	return 0;
}
