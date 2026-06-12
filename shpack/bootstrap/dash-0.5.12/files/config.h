/* SPDX-License-Identifier: MIT
 *
 * Hand-written config.h for the dash-0.5.12 bootstrap build (tcc + musl 1.1.24).
 *
 * dash normally derives this from ./configure, but dash is the FIRST shell in
 * the chain, so there is no shell to run configure with. We compile dash by
 * hand (see pass1.kaem) against full musl, with this fixed config.
 *
 * Rules of thumb for what to enable:
 *  - Define HAVE_* only for symbols musl 1.1.24 actually provides with a real
 *    prototype, so tcc never sees an implicit (int-returning) declaration that
 *    would truncate a 64-bit pointer.
 *  - Leave the GNU helpers (mempcpy/stpcpy/strchrnul) UNDEFINED: dash ships its
 *    own prototyped fallbacks in system.{c,h}; using them avoids needing
 *    _GNU_SOURCE and keeps prototypes correct.
 *  - Leave HAVE_ALIAS_ATTRIBUTE / HAVE_ATTRIBUTE_ALIAS undefined: tcc's alias
 *    attribute support is unreliable; dash falls back to real wrapper funcs.
 *  - Leave HAVE_SIGSETMASK undefined: musl has no sigsetmask; dash uses
 *    sigprocmask instead.
 *
 * To regenerate the committed generated sources (builtins.*, init.c, nodes.*,
 * signames.c, syntax.*, token*.h) consistently with this config, see the regen
 * note at the top of pass1.kaem.
 */

#define PACKAGE "dash"
#define PACKAGE_NAME "dash"
#define PACKAGE_STRING "dash 0.5.12"
#define PACKAGE_TARNAME "dash"
#define PACKAGE_VERSION "0.5.12"
#define VERSION "0.5.12"

#define STDC_HEADERS 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_MEMORY_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_UNISTD_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_ALLOCA_H 1
#define HAVE_PATHS_H 1

#define HAVE_DECL_ISBLANK 1
#define HAVE_ISALPHA 1
#define HAVE_BSEARCH 1
#define HAVE_FNMATCH 1
#define HAVE_GETPWNAM 1
#define HAVE_GETRLIMIT 1
#define HAVE_KILLPG 1
#define HAVE_SYSCONF 1
#define HAVE_STRSIGNAL 1
#define HAVE_STRTOD 1
#define HAVE_STRTOIMAX 1
#define HAVE_STRTOUMAX 1
#define HAVE_FACCESSAT 1
#define HAVE_ST_MTIM 1

#define SIZEOF_INTMAX_T 8
#define SIZEOF_LONG_LONG_INT 8

#define SMALL 1
#define WITH_LINENO 1

/* musl has no separate 64-bit (LFS) API -- everything is already 64-bit -- so
 * map dash's *64 names onto the plain ones, exactly as ./configure does when it
 * finds no distinct large-file interface. (`#define stat64 stat` also rewrites
 * `struct stat64` -> `struct stat`.) */
#define stat64 stat
#define fstat64 fstat
#define lstat64 lstat
#define open64 open
#define readdir64 readdir
#define dirent64 dirent
