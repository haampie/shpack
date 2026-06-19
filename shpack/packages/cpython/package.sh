# SPDX-License-Identifier: MIT

description "CPython 3.14.5 -- the glibc-linked, shared production Python that" \
            "runs clingo and Spack. Distinct from the musl 'python' 3.5.9 used" \
            "only to bootstrap glibc."
homepage "https://www.python.org/"
license "Python-2.0"

version 3.14.5 sha256=7e32597b99e5d9a39abed35de4693fa169df3e5850d4c334337ffd6a19a36db6 \
    url=https://www.python.org/ftp/python/3.14.5/Python-3.14.5.tar.xz

build_system autotools

# Backs stdlib modules: zlib-ng -> zlib/gzip/zipfile, libffi -> _ctypes, openssl
# -> _ssl, bzip2/xz/zstd -> _bz2/_lzma/_zstd. configure auto-detects each from
# the wrapper's search path. bzip2 pinned @1.0.8 for the gcc-16 recipe (the bare
# name resolves to the bin-only kaem seed; see etc/externals.in).
depends_on compiler-wrapper zlib-ng libffi openssl bzip2@1.0.8 xz zstd gmake

edit() {
    # Suspected fix for an intermittent "build-details.json: Bus error" under the
    # jobserver: the rule runs the interpreter (imports json -> _json.so) but only
    # depends on pybuilddir.txt, so it may race sharedmods writing that .so. Order
    # it after sharedmods. Unconfirmed; cf. cpython#102007.
    sed -i 's/^build-details.json: pybuilddir.txt$/build-details.json: pybuilddir.txt sharedmods/' Makefile.pre.in
}

setup_build_environment() {
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    export CXX=$(prefix_of compiler-wrapper)/bin/g++

    # No uname: configure leaves ac_sys_system empty and LDSHARED falls back to
    # bare `ld`, which chokes on the `-Wl,` flags. Forcing cross to dodge uname
    # won't work (autoconf rejects cross with build==host), so shim a uname that
    # makes configure take the Linux branch.
    local m
    case "$ARCH" in amd64) m=x86_64 ;; aarch64) m=aarch64 ;; esac
    mkdir -p "$stage_dir/shimbin"
    cat > "$stage_dir/shimbin/uname" <<EOF
#!$sh
case "\$1" in
  -s) echo Linux ;;
  -r) echo 6.9.1 ;;
  -m|-p|-i) echo $m ;;
  -n) echo shpack ;;
  -o) echo GNU/Linux ;;
  -a) echo "Linux shpack 6.9.1 #1 SMP $m GNU/Linux" ;;
  *)  echo Linux ;;
esac
EOF
    chmod 755 "$stage_dir/shimbin/uname"
    export PATH="$stage_dir/shimbin:$PATH"
    export _PYTHON_HOST_PLATFORM="linux-$m"
}

configure_args() {
    # Explicit triple (no date/uname for config.guess). --enable-shared installs
    # libpython3.14.so; the interpreter needs an rpath to its own libdir
    # (configure adds none).
    local t ffi ssl
    t=$(triple gnu)
    ffi=$(prefix_of libffi)
    ssl=$(prefix_of openssl)
    # LIBFFI_CFLAGS/LIBFFI_LIBS wire _ctypes directly (no pkg-config in the store).
    # --with-openssl points _ssl/_hashlib at the store OpenSSL; -rpath=auto bakes
    # its libdir into the modules so libssl/libcrypto resolve without LD_LIBRARY_PATH.
    printf '%s\n' \
        --build="$t" \
        --host="$t" \
        --enable-shared \
        --without-ensurepip \
        --disable-test-modules \
        --with-system-ffi \
        --with-openssl="$ssl" \
        --with-openssl-rpath=auto \
        "LIBFFI_CFLAGS=-I$ffi/include" \
        "LIBFFI_LIBS=-L$ffi/lib -lffi" \
        "LDFLAGS=-Wl,-rpath,$PREFIX/lib"
}

install() {
    make install
    [ -e "$PREFIX/bin/python3" ] || ln -s python3.14 "$PREFIX/bin/python3"
    rm -rf "$PREFIX/lib/python3.14/test"
}
