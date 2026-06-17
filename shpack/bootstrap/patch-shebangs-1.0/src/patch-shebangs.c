/* SPDX-License-Identifier: MIT
 *
 * patch-shebangs INTERP DIR... -- recursively rewrite `#!/bin/sh` (and bash,
 * `env sh`, ...) interpreters to INTERP (an absolute shell), the Nix
 * patchShebangs trick. The Landlock sandbox grants no host /bin/sh, yet build
 * helpers (install-sh, config.guess, missing, depcomp, ...) carry a #!/bin/sh
 * shebang and are exec'd directly; shpack runs this over each source tree (see
 * builder.sh) to repoint them at the store shell.
 *
 * Only the interpreter token is replaced; args and body are kept. Symlinks are
 * not followed. Self-contained (musl/tcc).
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>

/* Largest file treated as a possible script; bigger ones are skipped. */
#define MAX_SCRIPT (4 * 1024 * 1024)

static const char *interp;       /* replacement shell, absolute */
static size_t interp_len;

static int is_shell_name(const char *s, size_t n)
{
	return (n == 2 && memcmp(s, "sh", 2) == 0) ||
	       (n == 4 && memcmp(s, "bash", 4) == 0);
}

/* basename length of token [p, p+n): the run after the last '/'. Sets *bp. */
static size_t base_of(const char *p, size_t n, const char **bp)
{
	size_t i, start = 0;
	for (i = 0; i < n; i++)
		if (p[i] == '/')
			start = i + 1;
	*bp = p + start;
	return n - start;
}

/* If buf[0,len) begins with a shebang whose interpreter is a shell (directly,
 * or via `env sh`/`env bash`), return the offset just past the token to be
 * replaced (the body to keep starts there). Else return 0. */
static size_t shebang_cut(const char *buf, size_t len)
{
	size_t i, ts, te, bn;
	const char *bp;

	if (len < 2 || buf[0] != '#' || buf[1] != '!')
		return 0;
	i = 2;
	while (i < len && (buf[i] == ' ' || buf[i] == '\t'))
		i++;
	ts = i;
	while (i < len && buf[i] != ' ' && buf[i] != '\t' && buf[i] != '\n')
		i++;
	te = i;
	if (te == ts)
		return 0;
	bn = base_of(buf + ts, te - ts, &bp);
	if (is_shell_name(bp, bn))
		return te;                       /* #!/bin/sh [args] */
	if (bn == 3 && memcmp(bp, "env", 3) == 0) {
		/* #!/usr/bin/env sh [args] -- the real interp is the next token */
		size_t as, ae;
		while (i < len && (buf[i] == ' ' || buf[i] == '\t'))
			i++;
		as = i;
		while (i < len && buf[i] != ' ' && buf[i] != '\t' && buf[i] != '\n')
			i++;
		ae = i;
		if (ae > as && is_shell_name(buf + as, ae - as))
			return ae;
	}
	return 0;
}

static void patch_file(const char *path)
{
	struct stat st;
	char *buf;
	ssize_t got;
	size_t cut;
	int fd;

	fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
	if (fd < 0)
		return;                          /* symlink, perm, gone -- skip */
	if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) ||
	    st.st_size < 2 || st.st_size > MAX_SCRIPT) {
		close(fd);
		return;
	}
	buf = malloc((size_t)st.st_size);
	if (buf == NULL) {
		close(fd);
		return;
	}
	got = read(fd, buf, (size_t)st.st_size);
	close(fd);
	if (got < 2 || buf[0] != '#' || buf[1] != '!') {
		free(buf);
		return;
	}

	cut = shebang_cut(buf, (size_t)got);
	if (cut == 0) {
		free(buf);
		return;
	}

	/* Rewrite via a sibling temp file, preserving mode, then rename. */
	{
		char tmp[4096];
		int n, ok = 0;
		n = snprintf(tmp, sizeof(tmp), "%s.pshtmp", path);
		if (n > 0 && (size_t)n < sizeof(tmp)) {
			int w = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
				     st.st_mode & 07777);
			if (w >= 0) {
				if (write(w, "#!", 2) == 2 &&
				    write(w, interp, interp_len) == (ssize_t)interp_len &&
				    write(w, buf + cut, (size_t)got - cut) == (ssize_t)(got - cut))
					ok = 1;
				/* Keep mtime: a shebang rewrite must be invisible to make,
				 * else it revives dormant regeneration rules (e.g.
				 * findutils' gnulib-version.c) and breaks the build. */
				{
					struct timespec times[2];
					times[0] = st.st_atim;
					times[1] = st.st_mtim;
					futimens(w, times);
				}
				close(w);
				if (ok && rename(tmp, path) == 0)
					/* done */;
				else
					unlink(tmp);
			}
		}
	}
	free(buf);
}

static void walk(const char *dir)
{
	DIR *d;
	struct dirent *e;
	char path[4096];

	d = opendir(dir);
	if (d == NULL)
		return;
	while ((e = readdir(d)) != NULL) {
		struct stat st;
		int n;

		if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0)
			continue;
		n = snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
		if (n <= 0 || (size_t)n >= sizeof(path))
			continue;
		if (lstat(path, &st) != 0)
			continue;
		if (S_ISDIR(st.st_mode))
			walk(path);
		else if (S_ISREG(st.st_mode))
			patch_file(path);
		/* symlinks and specials: ignored */
	}
	closedir(d);
}

int main(int argc, char **argv)
{
	int i;

	if (argc < 3) {
		fprintf(stderr, "usage: patch-shebangs INTERP DIR [DIR...]\n");
		return 2;
	}
	interp = argv[1];
	interp_len = strlen(interp);
	if (interp[0] != '/') {
		fprintf(stderr, "patch-shebangs: INTERP must be absolute: %s\n", interp);
		return 2;
	}
	for (i = 2; i < argc; i++)
		walk(argv[i]);
	return 0;
}
