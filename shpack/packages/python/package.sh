# SPDX-License-Identifier: MIT

description "Python 3.8.20, built by the gcc-9.5 bridge against static musl --" \
            "glibc 2.43 needs python3 (scripts/gen-as-const.py and friends)."
homepage "https://www.python.org/"
license "Python-2.0"

# 3.9 removed --without-threads; static musl here has no pthreads.
version 3.8.20 sha256=6fb89a7124201c61125c0ab4cf7f6894df339a40c02833bfd28ab4d7691fafb4 \
    url=https://www.python.org/ftp/python/3.8.20/Python-3.8.20.tar.xz

build_system generic

depends_on gcc-boot@9.5.0 binutils@2.30-musl gmake sed@4.9-musl tar@1.35-musl xz@5.2.5-musl
depends_on dash@0.5.12

edit() {
    # subprocess(shell=True) hardcodes ["/bin/sh", "-c"] in pure Python, which
    # the musl patch can't reach and the sandbox denies (glibc's glibcextract.py
    # drives the compiler this way).
    replace_bin_sh Lib/subprocess.py
}

setup_build_environment() {
    export CC="$(prefix_of gcc-boot)/bin/gcc"
    export CXX="$(prefix_of gcc-boot)/bin/g++"
    # PYTHONHASHSEED=0 pins marshal order of set/frozenset literals in .pyc.
    export PYTHONHASHSEED=0
    # Make setup.py take its cross_compiling branch, which skips /usr/include
    # and /usr/local probing (those dirs don't exist in the chroot).
    case "$ARCH" in
        amd64)   export _PYTHON_HOST_PLATFORM=linux-x86_64 ;;
        aarch64) export _PYTHON_HOST_PLATFORM=linux-aarch64 ;;
    esac
}

install() {
    local triple
    triple=$(triple musl)

    # Only the modules needed by glibc's build scripts (gen-as-const.py,
    # glibcextract.py): subprocess machinery plus locale for encoding detection.
    # *disabled* blocks ctypes (needs libffi) and ossaudiodev (needs ALSA).
    cat > Modules/Setup.local <<'EOF'
*static*
_posixsubprocess _posixsubprocess.c
fcntl fcntlmodule.c
select selectmodule.c
_struct _struct.c
_locale -DPy_BUILD_CORE_BUILTIN _localemodule.c
math mathmodule.c _math.c
_random _randommodule.c
_md5 md5module.c
_sha1 sha1module.c
_sha256 sha256module.c
_sha512 sha512module.c
*disabled*
_ctypes
ossaudiodev
EOF

    # OPT drops the -g configure forces on every object regardless of CFLAGS; -g
    # would leak stage_dir as the DWARF comp_dir. file_prefix_map in CFLAGS won't
    # do: configure records CFLAGS verbatim and its path length shifts a pprint
    # line-wrap in _sysconfigdata.py the path-scrub can't undo. OPT is constant.
    "$sh" ./configure \
        "CONFIG_SHELL=$sh" \
        "SHELL=$sh" \
        "CC=$(prefix_of gcc-boot)/bin/gcc" \
        CFLAGS=-O2 \
        'OPT=-DNDEBUG -fwrapv' \
        --build="$triple" \
        --host="$triple" \
        --prefix="$PREFIX" \
        --without-ensurepip \
        --without-threads \
        --without-pymalloc \
        --with-doc-strings=no \
        --disable-ipv6 \
        --disable-shared

    make $makejobs

    # Scrub build path before install so make install's compileall bakes the
    # scrubbed source into .pyc directly.
    sed -i "s|$stage_dir|/build|g" build/lib.*/_sysconfigdata_*.py

    # No uname -> PLATDIR=plat-unknown, whose make rule runs regen (h2py's
    # /usr/include/netinet/in.h, absent here) and fails install. Pre-create the
    # dir so make skips regen; the modules it would generate are deprecated/unused.
    mkdir -p Lib/plat-unknown

    make install

    rm -rf "$PREFIX/lib/python3.8/test"

    # config Makefile has no .pyc; scrub it after install.
    sed -i "s|$stage_dir|/build|g" \
        "$PREFIX/lib/python3.8/config-3.8"*"-linux-"*/Makefile

    [ -e "$PREFIX/bin/python3" ] || ln -s python3.8 "$PREFIX/bin/python3"
}
