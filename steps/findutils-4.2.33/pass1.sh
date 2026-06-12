# SPDX-License-Identifier: GPL-3.0-or-later
#
# findutils provides `find`, which gcc-linaro's libstdc++ libtool needs to merge
# the per-directory convenience archives (libsupc++/libc++98/libc++11) into the
# static libstdc++.a. Without it, libtool extracts the convenience objects but
# the find-based collection step yields nothing, so libstdc++.a ends up holding
# only the few compatibility*.o and every real C++ program fails to link.
#
# Unlike live-bootstrap we do NOT autoreconf: the release tarball ships a working
# pre-generated ./configure, which is our standing deviation, so we just run it.

src_configure() {
    case "${ARCH}" in
        amd64)   HOST=x86_64-unknown-linux-gnu ;;
        aarch64) HOST=aarch64-unknown-linux-gnu ;;
    esac

    # musl is unknown to the 2007 config.sub, so present as gnu for the triple;
    # uname returns "unknown" in the bare chroot so config.guess cannot deduce
    # --build either -- give both explicitly. Tell gnulib we are uClibc-like so
    # it avoids glibc-only assumptions under musl.
    #
    # --disable-nls: find needs no translations; drops the gettext path.
    #
    # LD=tcc: configure's AC_PROG_LD probes `$CC -print-prog-name=ld` then
    # searches PATH for `ld`, and fatally errors ("no acceptable ld") when none
    # is found -- and there is none yet (binutils builds after findutils). When
    # LD is preset, configure uses it verbatim and skips the probe entirely. tcc
    # links internally, so a real ld is never actually invoked. (tcc already
    # links static by default via our patch, so no LDFLAGS=-static needed.)
    CC=tcc LD=tcc ./configure \
        --prefix="${PREFIX}" \
        --build="${HOST}" \
        --host="${HOST}" \
        --disable-nls \
        CPPFLAGS="-D__UCLIBC__"
}

src_compile() {
    # No binutils yet, so the static archives (libgnulib.a) are built with
    # tcc's built-in archiver. tcc -ar has no `u` (update) mode, so override the
    # automake default ARFLAGS=cru with rc.
    make "${MAKEJOBS}" MAKEINFO=true AR="tcc -ar" ARFLAGS="rc"
}

src_install() {
    make MAKEINFO=true AR="tcc -ar" ARFLAGS="rc" install
}
