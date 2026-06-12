/* SPDX-License-Identifier: MIT */

/* Minimal config.h for building make 3.82 with tcc against FULL musl.
 *
 * make.h gates its system-header includes on autoconf HAVE_* macros. With an
 * empty config.h (as live-bootstrap uses against its bring-up subset libc) none
 * are set, so against full musl <string.h>/<stdlib.h>/<limits.h>/<unistd.h> are
 * never pulled in: string/mem functions get implicit declarations (returning
 * int, truncating 64-bit pointers) and ULONG_MAX / read / write are undeclared.
 * Declare the headers we actually have so make.h includes them. */
#define STDC_HEADERS 1
#define HAVE_STRING_H 1
#define HAVE_LIMITS_H 1
#define HAVE_UNISTD_H 1
/* tcc ships <alloca.h> (void *alloca(size_t)); without this make.h emits its own
 * K&R `char *alloca()` prototype, which tcc rejects once <stdlib.h> pulls in the
 * real one. */
#define HAVE_ALLOCA_H 1

/* full musl already declares strcasecmp/strncasecmp; suppress make.h's
 * tcc-incompatible (int-length) fallback prototypes. */
#define HAVE_STRCASECMP 1
#define HAVE_STRNCASECMP 1
