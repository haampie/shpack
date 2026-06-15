# SPDX-License-Identifier: MIT

description "GNU make 4.4.1: replaces the kaem-built make 3.82 for all heavy" \
            "downstream builds (fixes 3.82's parallel races; fifo jobserver)"
homepage "https://www.gnu.org/software/make/"
license "GPL-3.0-or-later"

# make 3.82 is a kaem-phase external (etc/externals); this recipe is the
# parallel-safe upgrade and the spec named by SHPACK_BOOTSTRAP_MAKE.
version 4.4.1 sha256=dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3 \
    url=https://ftpmirror.gnu.org/make/make-4.4.1.tar.gz

build_system autotools

depends_on tcc musl@1.1.24 grep gawk@3.0.4

configure_args() {
    # No binutils ar yet and config.guess cannot probe this environment, so
    # pin the triple and the archiver; disable everything that would pull in
    # tools we do not have (guile, nls, dynamic load objects).
    case "$ARCH" in
        amd64)   triple=x86_64-unknown-linux-musl ;;
        aarch64) triple=aarch64-unknown-linux-musl ;;
    esac
    printf '%s\n' \
        CONFIG_SHELL=/bin/sh \
        SHELL=/bin/sh \
        CC=tcc \
        LD=tcc \
        'AR=tcc -ar' \
        ARFLAGS=cr \
        --build="$triple" \
        --host="$triple" \
        --disable-dependency-tracking \
        --disable-nls \
        --without-guile \
        --disable-load
}

# There is no make that can build make yet (3.82 is what we are replacing),
# so use the bundled build.sh: shell + tcc only, no make-to-build-make.
build() {
    sed -i "s|^AR=.*|AR='tcc -ar'|; s|^ARFLAGS=.*|ARFLAGS='cr'|" build.cfg
    sh ./build.sh
    # Sanity: it runs and the fifo jobserver is compiled in.
    ./make --version
    ./make -p -f /dev/null 2>/dev/null | grep jobserver
}

install() {
    mkdir -p "$PREFIX/bin"
    cp make "$PREFIX/bin/make"
    ln -sf make "$PREFIX/bin/gmake"
}
