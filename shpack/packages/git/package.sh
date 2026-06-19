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

# HTTPS transport: curl (libcurl) + openssl (TLS/hashing) + nghttp2 (via curl).
# expat = dumb-HTTP/WebDAV push; pcre2 = `git grep -P`; zlib-ng = pack codec;
# perl drives build-time script generation (and runtime git-svn/add--interactive,
# largely C now). compiler-wrapper injects -I/-L/-rpath for all of these.
# coreutils: templates/Makefile ends its boilerplate rule with `date >$@`, and
# that exit-127 (no date on the base PATH) fails the rule. The timestamp only
# lands in the `boilerplates.made` make stamp -- never installed -- so a real
# date here is inert w.r.t. the reproducible output.
depends_on compiler-wrapper curl openssl zlib-ng expat pcre2 perl gmake coreutils

edit() {
    # glibc 2.43 (>= 2.36) provides arc4random, so use it as git's CSPRNG, per
    # Spack's git patch(). config.mak is read by git's Makefile after configure.
    printf 'CSPRNG_METHOD=arc4random\n' > config.mak
}

configure_args() {
    # No uname/config.guess in the sandbox -> explicit glibc triple. The dep
    # prefixes are passed via --with-* (configure does not auto-detect them); the
    # wrapper still supplies the -I/-L/-rpath that make the links resolve.
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
