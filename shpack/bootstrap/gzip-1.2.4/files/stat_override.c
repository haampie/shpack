/*
 * SPDX-FileCopyrightText: 2022 Samuel Tyler <samuel@samuelt.me>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

/* musl's <sys/stat.h> is self-contained; the live-bootstrap original also pulled
 * in mes libc's <linux/syscall.h> and <linux/x86/syscall.h>, which do not exist
 * (and are not needed) under musl on aarch64. */
#include <sys/stat.h>

int _stat(const char *path, struct stat *buf) {
	int rc = stat(path, buf);
	if (rc == 0) {
		buf->st_atime = 0;
		buf->st_mtime = 0;
	}
	return rc;
}

int _lstat(const char *path, struct stat *buf) {
	int rc = lstat(path, buf);
	if (rc == 0) {
		buf->st_atime = 0;
		buf->st_mtime = 0;
	}
	return rc;
}

#define stat(a,b) _stat(a,b)
#define lstat(a,b) _lstat(a,b)
