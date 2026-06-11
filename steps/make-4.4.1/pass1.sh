# SPDX-License-Identifier: GPL-3.0-or-later
#
# GNU Make 4.4.1 -- replaces the bootstrap make-3.82 for all the heavy downstream
# steps (binutils/gmp/mpfr/mpc/gcc). 4.4.1 fixes 3.82's parallel-build races and
# ships the robust fifo jobserver, so those recursive builds run correctly in
# parallel.
#
# We have no make yet that can build make, so we use make's own bundled
# ./build.sh, which compiles make with just a POSIX shell (dash) + CC (tcc):
# configure generates build.cfg/config.h, build.sh compiles the gnulib lib and
# the make objects, archives libgnu.a with $AR, and links ./make. No m4, no real
# ar, no make-to-build-make.

src_configure() {
    # We have no binutils ar yet, and config.guess needs tools (date/uname) that
    # may be missing, so pin the triple explicitly instead of guessing.
    case "${ARCH}" in
        amd64)   TRIPLE=x86_64-unknown-linux-musl ;;
        aarch64) TRIPLE=aarch64-unknown-linux-musl ;;
    esac

    # tcc as CC; tcc -ar as the archiver (no binutils ar exists yet). Disable
    # everything that would pull in tools we do not have at this stage (guile,
    # nls, dynamic load objects, dependency tracking).
    ./configure \
        CONFIG_SHELL=/bin/sh \
        SHELL=/bin/sh \
        CC=tcc \
        LD=tcc \
        "AR=tcc -ar" \
        ARFLAGS=cr \
        --build="${TRIPLE}" \
        --host="${TRIPLE}" \
        --disable-dependency-tracking \
        --disable-nls \
        --without-guile \
        --disable-load \
        --prefix="${PREFIX}"
}

src_compile() {
    # configure leaves @AR@/@ARFLAGS@ substituted in build.cfg; make sure the
    # archiver is tcc -ar with the create+insert flags it expects (it recreates
    # the archive each call, so this is `tcc -ar cr libgnu.a objs`).
    sed -i "s|^AR=.*|AR='tcc -ar'|; s|^ARFLAGS=.*|ARFLAGS='cr'|" build.cfg

    sh ./build.sh

    # Sanity: it runs and reports the fifo jobserver is compiled in.
    ./make --version
    ./make -p -f /dev/null 2>/dev/null | grep jobserver
}

src_install() {
    mkdir -p "${PREFIX}/bin"
    # Overwrite make-3.82 with 4.4.1; keep a gmake alias.
    cp make "${PREFIX}/bin/make"
    ln -sf make "${PREFIX}/bin/gmake"
}
