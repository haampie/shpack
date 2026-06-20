# SPDX-License-Identifier: MIT

description "Git 2.53.0 -- distributed version control system. Built" \
            "HTTPS-capable (curl + openssl + nghttp2) at the gcc-16 layer," \
            "without manpages or NLS. shpack has no autoconf, so the build runs" \
            "git's shipped ./configure."
homepage "https://git-scm.com"
license "GPL-2.0-only"

version 2.53.0 sha256=429dc0f5fe5f14109930cdbbb588c5d6ef5b8528910f0d738040744bebdc6275 \
    url=https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.53.0.tar.gz

build_system autotools

# HTTPS transport: curl + openssl + nghttp2 (via curl). expat = dumb-HTTP push;
# pcre2 = `git grep -P`; zlib-ng = pack codec; perl drives script generation.
# coreutils: templates/Makefile's boilerplate rule ends with `date >$@`, which
# would exit-127 without date; the timestamp only lands in a make stamp.
depends_on compiler-wrapper curl openssl zlib-ng@2.3.3 expat pcre2 perl gmake coreutils

edit() {
    # glibc 2.43 provides arc4random, so use it as git's CSPRNG. config.mak is
    # read by git's Makefile after configure.
    printf 'CSPRNG_METHOD=arc4random\n' > config.mak
}

configure_args() {
    # Explicit glibc triple (no uname/config.guess). Dep prefixes via --with-*
    # (no auto-detection); the wrapper supplies the -I/-L/-rpath.
    local t
    t=$(triple gnu)
    printf '%s\n' \
        CC=gcc \
        --build="$t" \
        --host="$t" \
        --with-curl="$(prefix_of curl)" \
        --with-openssl="$(prefix_of openssl)" \
        --with-zlib="$(prefix_of zlib-ng)" \
        --with-expat="$(prefix_of expat)" \
        --with-libpcre2="$(prefix_of pcre2)" \
        --with-perl="$(prefix_of perl)/bin/perl" \
        --without-tcltk
}

# NO_GETTEXT: built ~nls (no gettext in the store). NO_TCLTK: no gitk/git-gui.
# SHELL_PATH bakes the store shell into git's generated scripts and into git's
# compiled-in default shell (the sandbox has no host /bin/sh).
build_args() {
    printf '%s\n' NO_GETTEXT=1 NO_TCLTK=1 "SHELL_PATH=$sh"
}

install_targets() {
    printf '%s\n' install NO_GETTEXT=1 NO_TCLTK=1 "SHELL_PATH=$sh"
}
