# SPDX-License-Identifier: MIT

description "dash 0.5.13.4 -- a small POSIX /bin/sh. Built fully static against" \
            "glibc so the resulting binary has no shared-library dependency and" \
            "an empty runtime closure."
homepage "http://gondor.apana.org.au/~herbert/dash/"
license "BSD-3-Clause"

version 0.5.13.4 sha256=d10dfd41cda59165560db39ca915c2c4a7636fff04281d8d2df77ad92c753e2b \
    url=http://gondor.apana.org.au/~herbert/dash/files/dash-0.5.13.4.tar.gz

build_system autotools

# Built by gcc-16-boot0 directly (no wrapper): a static link needs only glibc's
# startfiles + libc.a via -B, not the dynamic loader/rpath a wrapper injects.
# glibc here is the throwaway 2.43-boot (the final 2.43 depends on this dash, so
# linking it against 2.43 would be a cycle). binutils provides as/ld.
depends_on gcc-boot glibc@2.43-boot binutils@2.46.0-musl gmake

configure_args() {
    local t cc gl
    t=$(triple gnu)
    cc=$(prefix_of gcc-boot)/bin/gcc
    gl=$(prefix_of glibc)
    # Static: -B finds crt*.o + libc.a, -I glibc's headers. No NLS/printf-builtin
    # frills -- this is a build-time /bin/sh, not a user shell.
    printf '%s\n' \
        "CC=$cc -B$gl/lib -I$gl/include -static" \
        "--build=$t" "--host=$t" \
        --enable-static
}

install() {
    default_install
    # dash installs only bin/dash; consumers ($sh, /bin/sh) expect bin/sh too.
    ln -f "$PREFIX/bin/dash" "$PREFIX/bin/sh"
}
