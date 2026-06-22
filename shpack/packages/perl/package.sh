# SPDX-License-Identifier: MIT

description "Perl 5.40.2 -- build dependency of OpenSSL (its Configure and" \
            "build generators are Perl). Core interpreter only; the optional" \
            "DB/gdbm extensions Spack's perl pulls in aren't needed here."
homepage "https://www.perl.org/"
license "Artistic-1.0-Perl OR GPL-1.0-or-later"

version 5.40.2 sha256=10d4647cfbb543a7f9ae3e5f6851ec49305232ea7621aed24c7cfbb0bef4b70d \
    url=https://www.cpan.org/src/5.0/perl-5.40.2.tar.gz

build_system generic

# Configure leans on awk and grep, neither in the bootstrap base PATH, and probes
# for `comm` (kit-completeness check) -- coreutils supplies it.
depends_on compiler-wrapper coreutils gawk grep@2.4-musl gmake
depends_on dash

edit() {
    local storecat storepwd glibc m
    storecat=$(command -v cat)
    storepwd=${storecat%/cat}/pwd
    glibc=$(prefix_of glibc)
    case "$ARCH" in amd64) m=x86_64 ;; aarch64) m=aarch64 ;; esac

    # Configure's basic-shell search takes the host /bin/sh whenever the file is
    # present, which the sandbox denies executing. Point it at the store shell;
    # the $startsh it derives then flows into every helper script it generates
    # (patch-shebangs, acting only on existing #! lines, can't reach those).
    sed -i "s|xxx='/bin/sh'|xxx='$sh'|" Configure

    # Configure's shebang test runs "#!$xcat", but xcat defaults to the host
    # /bin/cat, which the sandbox denies; the test then silently fails and
    # Configure falls back to unexecutable ': use' scripts. Point xcat at store cat.
    sed -i "s|xcat=/bin/cat|xcat=$storecat|;s|xcat=/usr/bin/cat|xcat=$storecat|" Configure

    # The Errno extension scans <errno.h>, hardcoding "$sysroot/usr/include"
    # first; it finds the host errno.h (unreadable in the sandbox) and dies.
    # Point it at the store glibc headers.
    sed -i "s|\"\$sysroot/usr/include\"|\"$glibc/include\"|" ext/Errno/Errno_pm.PL

    # Cwd.pm shells out to a hardcoded /bin/pwd (denied), so cwd() comes back
    # empty and MakeMaker dies. Repoint the first candidate at the store pwd.
    sed -i "s|'/bin/pwd'|'$storepwd'|" dist/PathTools/Cwd.pm

    # config.over wins over probing (sourced last): pin the wall-clock stamp and
    # the host-FS probes that diverge between host and hermetic chroot. Lib paths
    # -> store glibc; pager -> in-closure cat (no pager packaged; never invoked).
    cat > config.over <<EOF
cf_time='Thu Jan  1 00:00:00 UTC 1970'
groupcat=''
hostcat=''
passcat=''
installusrbinperl='undef'
pager='$storecat'
sysman=''
myarchname='$m-linux'
glibpth='$glibc/lib'
plibpth=''
libpth='$glibc/lib'
libspath=' $glibc/lib'
libc='$glibc/lib/libc.so.6'
incpth=\`echo " \$incpth " | sed 's| /usr/local/include||g'\`
ccincpth=\`echo " \$ccincpth " | sed 's| /usr/local/include||g'\`
EOF
}

setup_build_environment() {
    # Perl's Configure (and myconfig) call `uname`, absent in the sandbox.
    local m
    case "$ARCH" in amd64) m=x86_64 ;; aarch64) m=aarch64 ;; esac
    mkdir -p "$stage_dir/shimbin"
    cat > "$stage_dir/shimbin/uname" <<EOF
#!$sh
case "\$1" in
  -s) echo Linux ;; -r) echo 6.9.1 ;; -m|-p|-i) echo $m ;;
  -n) echo shpack ;; -o) echo GNU/Linux ;;
  -a) echo "Linux shpack 6.9.1 #1 SMP $m GNU/Linux" ;; *) echo Linux ;;
esac
EOF
    chmod 755 "$stage_dir/shimbin/uname"
    export PATH="$stage_dir/shimbin:$PATH"
}

install() {
    local gcc glibc m
    gcc=$(prefix_of compiler-wrapper)
    glibc=$(prefix_of glibc)
    case "$ARCH" in amd64) m=x86_64 ;; aarch64) m=aarch64 ;; esac

    # -des = non-interactive defaults. No /usr/include or /usr/lib, so point the
    # include/lib probes at the glibc store prefix; -Dosname=linux forces
    # hints/linux.sh (the missing uname would otherwise leave osname empty).
    "$sh" ./Configure -des \
        -Dprefix="$PREFIX" \
        -Dcc="$gcc/bin/gcc" \
        -Dld="$gcc/bin/gcc" \
        -Dosname=linux \
        -Darchname="$m-linux" \
        -Dusrinc="$glibc/include" \
        -Dlibpth="$glibc/lib" \
        -Dlocincpth=" " \
        -Dloclibpth=" " \
        -Dman1dir=none \
        -Dman3dir=none \
        -Dusenm=false

    make $makejobs
    make install
}
