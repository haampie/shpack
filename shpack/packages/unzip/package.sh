# SPDX-License-Identifier: MIT

description "Info-ZIP unzip 6.0 -- the unzip CLI for .zip archives. Ancient" \
            "(2009) K&R C, so it needs -std=gnu89 and a couple of -Wno-error" \
            "knobs to compile with gcc 16."
homepage "https://infozip.sourceforge.net/UnZip.html"
license "Info-ZIP"

# Info-ZIP's tarball is unzip60.tar.gz (version digits joined), extracting unzip60/.
version 6.0 sha256=036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37 \
    url=https://downloads.sourceforge.net/infozip/unzip60.tar.gz

build_system generic

# compiler-wrapper supplies gcc 16 + glibc. Builds from unix/Makefile (no
# configure: the `generic` target skips Info-ZIP's feature probe).
depends_on compiler-wrapper gmake

# NOTE: upstream/distros carry a large set of CVE/hardening patches for unzip
# 6.0. They are not build-blocking and are deferred here; revisit before unzip
# is pointed at untrusted input.

install() {
    local cc loc
    cc=$(prefix_of compiler-wrapper)/bin/gcc
    # From Spack's unzip flag_handler/get_make_args: silence the implicit-decl
    # errors gcc 15+ makes fatal, enable large files, and force the gnu89 dialect
    # the K&R sources assume.
    loc="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -DLARGE_FILE_SUPPORT -std=gnu89"
    # No -j: the 2009 Makefile's recursive `generic` target is not parallel-safe.
    make -f unix/Makefile "SHELL=$sh" "CC=$cc" "LOC=$loc" generic
    make -f unix/Makefile "SHELL=$sh" "CC=$cc" "LOC=$loc" prefix="$PREFIX" install
}
