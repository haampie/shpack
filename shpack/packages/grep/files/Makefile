# SPDX-License-Identifier: MIT
#
# Replacement makefile: build GNU grep 2.4 with tcc against musl, bypassing
# the shipped configure (object list from upstream src/Makefile.in). Macros:
# musl has dirent.h/unistd.h/strerror; REGEX_MALLOC makes the bundled regex
# allocate with malloc instead of alloca.

CC = tcc

DEFS = -DPACKAGE='"grep"' -DVERSION='"2.4"' -DSTDC_HEADERS \
       -DHAVE_DIRENT_H -DHAVE_UNISTD_H -DHAVE_STRERROR -DREGEX_MALLOC

CFLAGS = $(DEFS)

OBJS = src/grep.o src/dfa.o src/kwset.o src/obstack.o src/regex.o \
       src/savedir.o src/getopt.o src/getopt1.o src/search.o src/grepmat.o

grep: $(OBJS)
	$(CC) -o $@ $(OBJS)

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

# egrep/fgrep as links to grep is enough for the configure scripts this
# bootstrap runs (they only use plain patterns through egrep).
install: grep
	mkdir -p $(PREFIX)/bin
	cp grep $(PREFIX)/bin/grep
	ln -sf grep $(PREFIX)/bin/egrep
	ln -sf grep $(PREFIX)/bin/fgrep
