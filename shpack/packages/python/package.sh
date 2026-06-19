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

depends_on gcc-boot@9.5.0 binutils@2.30-musl gmake sed tar xz

edit() {
    # subprocess(shell=True) hardcodes ["/bin/sh", "-c"] in pure Python,
    # bypassing libc, so the musl patch can't reach it. The sandbox denies host
    # /bin/sh (glibc's glibcextract.py drives the compiler this way).
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

    # Static musl has no dlopen, so shared C-extension modules can't be
    # imported. glibc's gen-as-const.py transitively needs several stdlib C
    # extensions, so link the dep-free ones STATICALLY into the interpreter via
    # Modules/Setup.local (the *static* directive; listing them also makes
    # setup.py skip their shared build). _socket omitted (musl lacks the Linux
    # CAN socket struct, and glibc's scripts don't need it).
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

    # OPT drops the -g that 3.5's configure forces on every object regardless of
    # CFLAGS (default "-DNDEBUG -g -fwrapv -O3 ..."); -g would leak stage_dir as the
    # DWARF comp_dir (see builder.sh). file_prefix_map in CFLAGS won't do: configure
    # records CFLAGS verbatim, and the path *length* shifts a pprint line-wrap in
    # _sysconfigdata.py the path-scrub can't undo. OPT is recorded as-is, so
    # "-DNDEBUG -fwrapv" stays constant.
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

    # `uname` is absent in the chroot, so configure sets MACHDEP=unknown and
    # PLATDIR=plat-unknown. `make install`'s rule for $(srcdir)/Lib/$(PLATDIR)
    # then runs Lib/plat-generic/regen, which h2py's /usr/include/netinet/in.h
    # -- a path that doesn't exist here -> install fails. Pre-create the dir so
    # make sees the target as satisfied and skips regen. The plat-* modules it
    # would generate (IN.py/DLFCN.py) are deprecated and unused by our consumers.
    mkdir -p Lib/plat-unknown

    make install

    # Drop the large test suite (before recompiling: less to byte-compile).
    rm -rf "$PREFIX/lib/python3.5/test"

    # configure records the absolute build dir verbatim in a couple of installed
    # text files (_sysconfigdata.py's abs_srcdir/abs_builddir/COVERAGE_*, and the
    # config Makefile's srcdir/abs_*). Nothing at runtime consults these paths, so
    # neutralize the scratch path to a constant; do it before recompiling so
    # _sysconfigdata's .pyc reflects the scrubbed source. (python3.5m-config needs
    # no scrub: its only build-path leak was the file_prefix_map CFLAGS value,
    # eliminated by dropping that flag above.)
    sed -i "s|$stage_dir|/build|g" \
        "$PREFIX/lib/python3.5/_sysconfigdata.py" \
        "$PREFIX/lib/python3.5/config-3.5m/Makefile"

    # Reproducible .pyc: `make install` stamps each copied .py with a fresh
    # install-time mtime, and 3.5's timestamp-only .pyc bakes that into its header
    # (3.5 predates PEP 552, so SOURCE_DATE_EPOCH is ignored). Pin every .py to a
    # constant mtime and force-recompile: the header is then constant and import
    # still validates (on-disk mtime == embedded). Recompile all three opt levels --
    # PEP 488 writes plain + .opt-1/.opt-2, each with its own header (3.5's
    # compile_dir takes one int; the list form is 3.7+). PYTHONHASHSEED=0 pins the
    # hash order in which set/frozenset literals (difflib, pydoc, ...) marshal,
    # else it is per-process random and the .pyc diverge.
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

    # The conventional python3 symlink.
    [ -e "$PREFIX/bin/python3" ] || ln -s python3.5 "$PREFIX/bin/python3"
}
