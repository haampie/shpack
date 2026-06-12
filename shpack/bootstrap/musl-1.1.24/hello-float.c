/* SPDX-License-Identifier: MIT
 * Smoke test for the full musl 1.1.24 libc: printf %f must round-trip (exercises
 * the double-vararg / XMM path and musl's float formatter under the production
 * tcc). Run in-chroot after the full libc.a + real startfiles are installed. */
#include <stdio.h>

int main(void)
{
	printf("%f %f %f\n", 3.0, 2.0, 1.5);
	return 0;
}
