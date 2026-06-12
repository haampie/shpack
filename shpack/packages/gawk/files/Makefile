# SPDX-License-Identifier: MIT
#
# Replacement makefile: build gawk 3.0.4 with tcc against musl, bypassing the
# shipped configure (object list from upstream Makefile.in: AWKOBJS + awktab
# + LIBOBJS). awk.h needs config.h to exist; everything it would define is a
# musl/tcc fact passed via DEFS. awktab.c is pregenerated in the release
# tarball; built-in suffix rules are disabled so make never tries yacc.

CC = tcc

DEFS = -DSTDC_HEADERS -DHAVE_UNISTD_H -DHAVE_STDARG_H -DHAVE_STRING_H \
       -DHAVE_LIMITS_H -DHAVE_LOCALE_H -DHAVE_SYS_PARAM_H -DHAVE_VPRINTF \
       -DHAVE_SYSTEM -DHAVE_TZSET -DHAVE_STRERROR -DHAVE_STRFTIME \
       -DHAVE_STRNCASECMP -DHAVE_STRTOD -DHAVE_MEMCMP -DHAVE_MEMCPY \
       -DHAVE_MEMSET -DHAVE_MMAP -DREGEX_MALLOC \
       -DRETSIGTYPE=void -DSPRINTF_RET=int \
       -DGETGROUPS_T=gid_t -DGETPGRP_VOID \
       -DDEFPATH='".:$(PREFIX)/share/awk"'

CFLAGS = -I. $(DEFS)

OBJS = array.o builtin.o eval.o field.o gawkmisc.o io.o main.o missing.o \
       msg.o node.o re.o version.o awktab.o \
       getopt.o getopt1.o regex.o dfa.o random.o

gawk: $(OBJS)
	$(CC) -o $@ $(OBJS) -lm

$(OBJS): config.h

config.h:
	: > config.h

.SUFFIXES:
.SUFFIXES: .c .o

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

install: gawk
	mkdir -p $(PREFIX)/bin
	cp gawk $(PREFIX)/bin/gawk
	ln -sf gawk $(PREFIX)/bin/awk
