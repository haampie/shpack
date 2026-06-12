# SPDX-FileCopyrightText: 2022 Andrius Štikonas <andrius@stikonas.eu>
#
# SPDX-License-Identifier: GPL-3.0-or-later

CC      = tcc

CFLAGS  = -I . -g
# HAVE_VPRINTF is required: without it util.c substitutes a my_vfprintf that does
# `int *a = (int *) args; fprintf(stream, format, a[0]..a[9])`, assuming va_list is
# a pointer to an array of stacked ints. That holds on i386 (live-bootstrap's
# target) but NOT on aarch64, where va_list is a struct -- so %s args become garbage
# pointers and musl's printf segfaults in strnlen. musl has real vprintf/vfprintf,
# so define HAVE_VPRINTF and use them. (This, not any tcc miscompile, was the cause
# of the patch SIGSEGV.)
CPPFLAGS = -DHAVE_VPRINTF=1 -DHAVE_DECL_GETENV -DHAVE_DECL_MALLOC -DHAVE_DIRENT_H -DHAVE_LIMITS_H -DHAVE_GETEUID -DHAVE_MKTEMP -DPACKAGE_BUGREPORT= -Ded_PROGRAM=\"/nullop\" -Dmbstate_t=void\* -DRETSIGTYPE=int -DHAVE_MKDIR -DHAVE_RMDIR -DHAVE_FCNTL_H -DPACKAGE_NAME=\"patch\" -DPACKAGE_VERSION=\"2.5.9\" -DHAVE_MALLOC -DHAVE_REALLOC -DSTDC_HEADERS -DHAVE_STRING_H -DHAVE_STDLIB_H -DHAVE_STRERROR -DHAVE_DECL_STRERROR=1
LDFLAGS = -static

.PHONY: all
all: patch

patch: error.o getopt.o getopt1.o addext.o argmatch.o backupfile.o basename.o dirname.o inp.o maketime.o partime.o patch.o pch.o quote.o quotearg.o quotesys.o util.o version.o xmalloc.o
	$(CC) $^ $(LDFLAGS) -o $@
