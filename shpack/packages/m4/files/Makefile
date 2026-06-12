# SPDX-License-Identifier: MIT
#
# Replacement makefile: build GNU m4 1.4.7 with tcc against musl, bypassing
# the shipped configure. Source program objects from upstream
# src/Makefile.in; the gnulib objects in libm4.a are the unconditional set
# plus the replacements the linker actually demands under musl + tcc.
# config.h is created empty; the facts it would carry are DEFS.

CC = tcc
AR = tcc -ar

DEFS = -DPACKAGE='"m4"' -DVERSION='"1.4.7"' \
       -DPACKAGE_NAME='"GNU M4"' -DPACKAGE_STRING='"GNU M4 1.4.7"' \
       -DPACKAGE_BUGREPORT='"bug-m4@gnu.org"' \
       -D_GNU_SOURCE -DHAVE_STDINT_H \
       -DHAVE___FPENDING -DHAVE_DECL___FPENDING \
       -D_GL_UNUSED= -D__getopt_argv_const=const \
       -DSYSCMD_SHELL='"/bin/sh"'

CFLAGS = -Ilib $(DEFS)

M4_OBJS = src/m4.o src/builtin.o src/debug.o src/eval.o src/format.o \
          src/freeze.o src/input.o src/macro.o src/output.o src/path.o \
          src/symtab.o

LIB_OBJS = lib/strnlen1.o lib/verror.o lib/xalloc-die.o lib/xvasprintf.o \
           lib/xasprintf.o lib/xmalloc.o lib/error.o lib/exitfail.o \
           lib/getopt.o lib/getopt1.o lib/obstack.o lib/regex.o \
           lib/cloexec.o lib/close-stream.o lib/dup-safer.o lib/fd-safer.o \
           lib/fopen-safer.o lib/mkstemp-safer.o lib/tmpfile-safer.o

# Linked as src/m4: the tree has an m4/ macro directory in the way of the
# bare name.
src/m4: libm4.a $(M4_OBJS)
	$(CC) -o $@ $(M4_OBJS) libm4.a

libm4.a: $(LIB_OBJS)
	$(AR) rc $@ $(LIB_OBJS)

$(M4_OBJS) $(LIB_OBJS): lib/config.h

lib/config.h:
	: > lib/config.h

.SUFFIXES:
.SUFFIXES: .c .o

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

install: src/m4
	mkdir -p $(PREFIX)/bin
	cp src/m4 $(PREFIX)/bin/m4
