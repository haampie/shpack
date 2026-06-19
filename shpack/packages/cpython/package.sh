# SPDX-License-Identifier: MIT

description "CPython 3.14.5 -- the glibc-linked, shared production Python that" \
            "runs clingo and Spack. Distinct from the musl 'python' 3.5.9 used" \
            "only to bootstrap glibc."
homepage "https://www.python.org/"
license "Python-2.0"

version 3.14.5 sha256=7e32597b99e5d9a39abed35de4693fa169df3e5850d4c334337ffd6a19a36db6 \
    url=https://www.python.org/ftp/python/3.14.5/Python-3.14.5.tar.xz

build_system autotools

# zlib-ng (drop-in zlib) for the zlib/gzip/zipfile stdlib modules; libffi for
# _ctypes (Spack's archspec imports ctypes at startup); openssl for _ssl (Spack
# imports ssl unconditionally via spack.util.web). hashlib works via the builtin
# _sha* modules; clingo uses the C-API, not cffi.
# bzip2/xz/zstd back the _bz2, _lzma and _zstd (3.14's compression.zstd) stdlib
# modules -- configure auto-detects each from the headers/libs the wrapper puts
# on the search path, so these need only be direct deps. bzip2 is pinned @1.0.8
# to get the gcc-16 recipe (with libbz2/headers); the bare name ties the bin-only
# kaem seed bzip2@1.0.8-musl, which wins (see etc/externals.in).
depends_on compiler-wrapper zlib-ng libffi openssl bzip2@1.0.8 xz zstd gmake

setup_build_environment() {
    export CC=$(prefix_of compiler-wrapper)/bin/gcc
    export CXX=$(prefix_of compiler-wrapper)/bin/g++

    # The sandbox has no `uname`. CPython's configure uses it (the native path --
    # build==host, so not cross) to set ac_sys_system, which selects LDSHARED.
    # Without it ac_sys_system is empty and LDSHARED falls back to bare `ld`
    # (which then chokes on the `-Wl,` gcc flags). Forcing cross to dodge uname is
    # a non-starter (autoconf won't honour cross_compiling=yes with build==host),
    # so provide a minimal uname that makes configure take the Linux branch.
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
    # config.guess can't probe this environment (no `date`/`uname`), so pass an
    # explicit triple like the other recipes. --enable-shared installs
    # libpython3.14.so; the interpreter needs an rpath to its own libdir
    # (configure adds none by default). zlib's headers/libs come from the
    # wrapper, so its module is detected automatically.
    local t ffi ssl
    t=$(triple gnu)
    ffi=$(prefix_of libffi)
    ssl=$(prefix_of openssl)
    # _ctypes detection: CPython probes libffi via pkg-config, but honours
    # LIBFFI_CFLAGS/LIBFFI_LIBS when set -- so we wire libffi directly and need
    # no pkg-config in the store. --with-openssl points _ssl/_hashlib at the
    # store OpenSSL; --with-openssl-rpath=auto bakes its libdir into the modules'
    # rpath so libssl.so.3/libcrypto.so.3 resolve without LD_LIBRARY_PATH.
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
    # Drop the large bundled test suite.
    rm -rf "$PREFIX/lib/python3.14/test"
}
