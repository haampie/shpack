# SPDX-License-Identifier: MIT
#
# Replacement makefile: build diffutils 2.7 (diff + cmp; diff3/sdiff are not
# needed downstream) with tcc against musl, bypassing the shipped configure.
# Object lists from upstream Makefile.in; musl provides memchr/waitpid/alloca
# so no gnulib replacements are linked. The empty config.h satisfies the
# unconditional #include; everything it would define is passed as -D flags.

CC = tcc

DEFS = -DSTDC_HEADERS -DHAVE_STDLIB_H -DHAVE_TIME_H -DHAVE_LIMITS_H \
       -DHAVE_STRERROR -DHAVE_DIRENT_H -DHAVE_UNISTD_H -DHAVE_FCNTL_H \
       -DHAVE_DUP2 -DHAVE_FORK -DHAVE_VPRINTF -DHAVE_ALLOCA_H \
       -DREGEX_MALLOC -DNULL_DEVICE='"/dev/null"'

CFLAGS = -I. $(DEFS)

DIFF_OBJS = diff.o analyze.o cmpbuf.o dir.o io.o util.o context.o ed.o \
            ifdef.o normal.o side.o fnmatch.o getopt.o getopt1.o regex.o \
            version.o

CMP_OBJS = cmp.o cmpbuf.o error.o getopt.o getopt1.o xmalloc.o version.o

all: diff cmp

diff: $(DIFF_OBJS)
	$(CC) -o $@ $(DIFF_OBJS)

cmp: $(CMP_OBJS)
	$(CC) -o $@ $(CMP_OBJS)

$(DIFF_OBJS) $(CMP_OBJS): config.h

config.h:
	: > config.h

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

install: all
	mkdir -p $(PREFIX)/bin
	cp diff cmp $(PREFIX)/bin/
