# SPDX-License-Identifier: MIT

description "Python 3.5.9, built by the gcc-9.5 bridge against static musl --" \
            "glibc 2.43 needs python3 (scripts/gen-as-const.py and friends)."
homepage "https://www.python.org/"
license "Python-2.0"

# 3.5 is the highest CPython that builds without pthreads (musl scaffold has
# --without-threads here) and without threading backports.
version 3.5.9 sha256=c24a37c63a67f53bdd09c5f287b5cff8e8b98f857bf348c577d454d3f74db049 \
    url=https://www.python.org/ftp/python/3.5.9/Python-3.5.9.tar.xz

build_system generic

depends_on gcc-boot@9.5.0 binutils@2.30-musl gmake sed@4.9-musl tar@1.35-musl xz@5.2.5-musl

edit() {
    # subprocess(shell=True) hardcodes ["/bin/sh", "-c"] in pure Python, which
    # the musl patch can't reach and the sandbox denies (glibc's glibcextract.py
    # drives the compiler this way).
    replace_bin_sh Lib/subprocess.py
}

setup_build_environment() {
    export CC="$(prefix_of gcc-boot)/bin/gcc"
    export CXX="$(prefix_of gcc-boot)/bin/g++"
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

    # Disable ctypes (needs libffi, absent) and ossaudiodev (needs ALSA/OSS
    # headers, absent) -- both would fail setup.py's extension build.
    sed -i '/extensions\.append(ctypes)/d' setup.py
    sed -i "s/'linux', //" setup.py

    # Static musl has no dlopen, so shared extensions can't be imported. glibc's
    # gen-as-const.py needs several stdlib C extensions; link the dep-free ones
    # statically via Modules/Setup.local (also makes setup.py skip their shared
    # build). _socket omitted (musl lacks the Linux CAN struct; not needed).
    cat > Modules/Setup.local <<'EOF'
*static*
array arraymodule.c
math mathmodule.c _math.c
cmath cmathmodule.c _math.c
_struct _struct.c
_random _randommodule.c
_bisect _bisectmodule.c
_heapq _heapqmodule.c
_datetime _datetimemodule.c
_pickle _pickle.c
_json _json.c
_csv _csv.c
unicodedata unicodedata.c
fcntl fcntlmodule.c
select selectmodule.c
_posixsubprocess _posixsubprocess.c
_locale _localemodule.c
binascii binascii.c
_md5 md5module.c
_sha1 sha1module.c
_sha256 sha256module.c
_sha512 sha512module.c
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
        --disable-shared

    make $makejobs

    # No uname -> PLATDIR=plat-unknown, whose make rule runs regen (h2py's
    # /usr/include/netinet/in.h, absent here) and fails install. Pre-create the
    # dir so make skips regen; the modules it would generate are deprecated/unused.
    mkdir -p Lib/plat-unknown

    make install

    # Drop the test suite before recompiling: less to byte-compile.
    rm -rf "$PREFIX/lib/python3.5/test"

    # configure records the absolute build dir in _sysconfigdata.py and the config
    # Makefile. Nothing at runtime consults these, so scrub to a constant before
    # recompiling so the .pyc reflects the scrubbed source.
    sed -i "s|$stage_dir|/build|g" \
        "$PREFIX/lib/python3.5/_sysconfigdata.py" \
        "$PREFIX/lib/python3.5/config-3.5m/Makefile"

    # Reproducible .pyc: `make install` stamps a fresh mtime that 3.5's
    # timestamp-only .pyc bakes into its header (predates PEP 552, ignores
    # SOURCE_DATE_EPOCH). Pin every .py to a constant mtime and force-recompile so
    # the header is constant and import still validates. Recompile all three opt
    # levels (PEP 488 writes plain + .opt-1/.opt-2). PYTHONHASHSEED=0 pins the
    # marshal order of set/frozenset literals, else the .pyc diverge.
    PYTHONHASHSEED=0 "$PREFIX/bin/python3.5" - "$PREFIX/lib/python3.5" "${SOURCE_DATE_EPOCH:-0}" <<'PY'
import os, sys, compileall
root, epoch = sys.argv[1], int(sys.argv[2])
for d, _, files in os.walk(root):
    for f in files:
        if f.endswith('.py'):
            os.utime(os.path.join(d, f), (epoch, epoch))
for opt in (0, 1, 2):
    compileall.compile_dir(root, force=True, quiet=1, optimize=opt)
PY

    [ -e "$PREFIX/bin/python3" ] || ln -s python3.5 "$PREFIX/bin/python3"
}
