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

    "$sh" ./configure \
        "CONFIG_SHELL=$sh" \
        "SHELL=$sh" \
        "CC=$(prefix_of gcc-boot)/bin/gcc" \
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

    # Drop the large test suite and add the conventional python3 symlink.
    rm -rf "$PREFIX/lib/python3.5/test"
    [ -e "$PREFIX/bin/python3" ] || ln -s python3.5 "$PREFIX/bin/python3"
}
