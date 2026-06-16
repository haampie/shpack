/* SPDX-License-Identifier: MIT
 *
 * sandbox -- an unprivileged Landlock launcher used to wrap every shell-phase
 * build step (see shpack/lib/concretize.sh, emit_dagmk). It whitelists the
 * filesystem to exactly the paths a build needs -- the store (read+execute),
 * the recipe tree and distfiles (read), and the package's own prefix plus the
 * scratch dir (write) -- so the host /usr is invisible and a stray write
 * outside the prefix is denied. This makes the chroot-free build-host.sh as
 * hermetic as the bwrap-sandboxed build.sh, and catches escapes under either.
 *
 *   sandbox [--read DIR]... [--write DIR]... -- cmd [args...]
 *
 * read  => execute + read.  write => read + write + create/remove.
 * /dev and /proc are always granted read (no compilers/headers live there).
 *
 * Design mirrors Spack's lib/spack/spack/sandbox.py (LandlockSandbox): the
 * access flags adapt to the kernel's Landlock ABI version, then the thread
 * locks itself down with prctl(NO_NEW_PRIVS) + landlock_restrict_self and
 * execs the command. When Landlock is unavailable or any setup step fails
 * before we restrict ourselves, we warn and exec the command UNSANDBOXED --
 * old kernels and qemu-user (which may not pass the landlock syscalls through)
 * keep working, falling back to whatever isolation the launcher provides.
 *
 * Self-contained: musl 1.1.24 predates the landlock uapi headers, so the
 * syscall numbers, constants and structs are defined here.
 */

#define _GNU_SOURCE   /* O_PATH (glibc); harmless under musl */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

#ifndef __NR_landlock_create_ruleset
#define __NR_landlock_create_ruleset 444
#endif
#ifndef __NR_landlock_add_rule
#define __NR_landlock_add_rule 445
#endif
#ifndef __NR_landlock_restrict_self
#define __NR_landlock_restrict_self 446
#endif

#ifndef PR_SET_NO_NEW_PRIVS
#define PR_SET_NO_NEW_PRIVS 38
#endif

#define LANDLOCK_CREATE_RULESET_VERSION  (1U << 0)
#define LANDLOCK_RULE_PATH_BENEATH       1
#define LANDLOCK_RESTRICT_SELF_TSYNC     (1U << 3)

/* enum landlock_access_fs (uapi/linux/landlock.h) */
#define LL_EXECUTE      (1ULL << 0)
#define LL_WRITE_FILE   (1ULL << 1)
#define LL_READ_FILE    (1ULL << 2)
#define LL_READ_DIR     (1ULL << 3)
#define LL_REMOVE_DIR   (1ULL << 4)
#define LL_REMOVE_FILE  (1ULL << 5)
#define LL_MAKE_CHAR    (1ULL << 6)
#define LL_MAKE_DIR     (1ULL << 7)
#define LL_MAKE_REG     (1ULL << 8)
#define LL_MAKE_SOCK    (1ULL << 9)
#define LL_MAKE_FIFO    (1ULL << 10)
#define LL_MAKE_BLOCK   (1ULL << 11)
#define LL_MAKE_SYM     (1ULL << 12)
#define LL_REFER        (1ULL << 13)   /* ABI v2 */
#define LL_TRUNCATE     (1ULL << 14)   /* ABI v3 */

struct landlock_ruleset_attr {
	uint64_t handled_access_fs;
	uint64_t handled_access_net;
	uint64_t scoped;
};

struct landlock_path_beneath_attr {
	uint64_t allowed_access;
	int32_t parent_fd;
} __attribute__((packed));

#define MAX_PATHS 64

static const char *prog = "sandbox";

static void warn(const char *msg)
{
	fprintf(stderr, "%s: %s: %s\n", prog, msg, strerror(errno));
}

/* The dir-only access rights, stripped from rules whose path is a plain file
 * (mirrors sandbox.py: a file rule can't usefully carry the make/remove bits). */
static uint64_t dir_flags(void)
{
	return LL_MAKE_BLOCK | LL_MAKE_CHAR | LL_MAKE_DIR | LL_MAKE_FIFO |
	       LL_MAKE_REG | LL_MAKE_SOCK | LL_MAKE_SYM | LL_READ_DIR |
	       LL_REFER | LL_REMOVE_DIR | LL_REMOVE_FILE;
}

static uint64_t read_flags(void)
{
	return LL_EXECUTE | LL_READ_FILE | LL_READ_DIR;
}

static uint64_t write_flags(int abi)
{
	uint64_t f = LL_MAKE_BLOCK | LL_MAKE_CHAR | LL_MAKE_DIR | LL_MAKE_FIFO |
		     LL_MAKE_REG | LL_MAKE_SOCK | LL_MAKE_SYM | LL_REMOVE_DIR |
		     LL_REMOVE_FILE | LL_WRITE_FILE;
	if (abi >= 2)
		f |= LL_REFER;
	if (abi >= 3)
		f |= LL_TRUNCATE;
	return f;
}

/* Add a path_beneath rule to the ruleset. Returns 0 on success; a missing
 * path is skipped (warned) and treated as success -- a build can't reach what
 * isn't there. A real syscall failure returns -1. */
static int add_path(int ruleset_fd, const char *path, uint64_t access)
{
	struct landlock_path_beneath_attr rule;
	struct stat st;
	int fd, rc;

	fd = open(path, O_PATH | O_CLOEXEC | O_NOFOLLOW);
	if (fd < 0) {
		warn(path);
		return 0;
	}
	if (fstat(fd, &st) == 0 && !S_ISDIR(st.st_mode))
		access &= ~dir_flags();

	rule.allowed_access = access;
	rule.parent_fd = fd;
	rc = syscall(__NR_landlock_add_rule, ruleset_fd,
		     LANDLOCK_RULE_PATH_BENEATH, &rule, 0U);
	close(fd);
	if (rc != 0) {
		warn("landlock_add_rule");
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	const char *reads[MAX_PATHS];
	const char *writes[MAX_PATHS];
	int nreads = 0, nwrites = 0;
	char **cmd = NULL;
	int abi, ruleset_fd, i;
	uint64_t handled, wflags;
	struct landlock_ruleset_attr attr;

	/* Always-on paths: nothing host-specific (no headers/libs). /dev must be
	 * writable -- builds write /dev/null constantly; DAC still guards real
	 * devices. /proc is read-only. */
	writes[nwrites++] = "/dev";
	reads[nreads++] = "/proc";

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--") == 0) {
			cmd = &argv[i + 1];
			break;
		} else if (strcmp(argv[i], "--read") == 0) {
			if (++i >= argc) { fprintf(stderr, "%s: --read needs an argument\n", prog); return 2; }
			if (nreads >= MAX_PATHS) { fprintf(stderr, "%s: too many --read paths\n", prog); return 2; }
			reads[nreads++] = argv[i];
		} else if (strcmp(argv[i], "--write") == 0) {
			if (++i >= argc) { fprintf(stderr, "%s: --write needs an argument\n", prog); return 2; }
			if (nwrites >= MAX_PATHS) { fprintf(stderr, "%s: too many --write paths\n", prog); return 2; }
			writes[nwrites++] = argv[i];
		} else {
			fprintf(stderr, "%s: unknown option '%s'\n", prog, argv[i]);
			return 2;
		}
	}

	if (cmd == NULL || cmd[0] == NULL) {
		fprintf(stderr, "usage: %s [--read DIR]... [--write DIR]... -- cmd [args...]\n", prog);
		return 2;
	}

	/* ABI probe. Any failure (ENOSYS on old kernels, qemu-user) => run the
	 * command unsandboxed rather than block the build. */
	abi = (int)syscall(__NR_landlock_create_ruleset, NULL, (size_t)0,
			   LANDLOCK_CREATE_RULESET_VERSION);
	if (abi < 1) {
		warn("landlock unavailable, running unsandboxed");
		execvp(cmd[0], cmd);
		warn(cmd[0]);
		return 127;
	}

	wflags = write_flags(abi);
	handled = wflags | read_flags();

	attr.handled_access_fs = handled;
	attr.handled_access_net = 0;
	attr.scoped = 0;
	ruleset_fd = (int)syscall(__NR_landlock_create_ruleset, &attr,
				  sizeof(attr), 0U);
	if (ruleset_fd < 0) {
		warn("landlock_create_ruleset, running unsandboxed");
		execvp(cmd[0], cmd);
		warn(cmd[0]);
		return 127;
	}

	for (i = 0; i < nreads; i++) {
		if (add_path(ruleset_fd, reads[i], read_flags()) != 0)
			goto fallback;
	}
	for (i = 0; i < nwrites; i++) {
		/* write implies read: a build installs then reads back. */
		if (add_path(ruleset_fd, writes[i], wflags | read_flags()) != 0)
			goto fallback;
	}

	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
		warn("prctl(PR_SET_NO_NEW_PRIVS), running unsandboxed");
		goto fallback;
	}
	if (syscall(__NR_landlock_restrict_self, ruleset_fd,
		    abi >= 8 ? LANDLOCK_RESTRICT_SELF_TSYNC : 0U) != 0) {
		warn("landlock_restrict_self, running unsandboxed");
		goto fallback;
	}
	close(ruleset_fd);

	execvp(cmd[0], cmd);
	warn(cmd[0]);
	return 127;

fallback:
	close(ruleset_fd);
	execvp(cmd[0], cmd);
	warn(cmd[0]);
	return 127;
}
