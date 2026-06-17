# SPDX-License-Identifier: MIT

description "Perl 5.40.2 -- build dependency of OpenSSL (its Configure and" \
            "build generators are Perl). Core interpreter only; the optional" \
            "DB/gdbm extensions Spack's perl pulls in aren't needed here."
homepage "https://www.perl.org/"
license "Artistic-1.0-Perl OR GPL-1.0-or-later"

version 5.40.2 sha256=10d4647cfbb543a7f9ae3e5f6851ec49305232ea7621aed24c7cfbb0bef4b70d \
    url=https://www.cpan.org/src/5.0/perl-5.40.2.tar.gz

build_system generic

# Configure leans on awk and grep, neither of which is in the bootstrap base
# PATH (only sed/coreutils/make are). gawk/grep supply them.
depends_on compiler-wrapper gawk grep gmake

edit() {
    local storecat storepwd glibc
    storecat=$(command -v cat)
    storepwd=${storecat%/cat}/pwd
    glibc=$(prefix_of glibc)

    # No chroot, so the host /bin/sh exists as a *file* -- and Configure's
    # basic-shell search (line ~1531) takes /bin/sh whenever the file is present.
    # The sandbox then denies executing it ("./sharp: Permission denied"). Point
    # the search at the store shell instead. This runs before Configure, so the
    # $startsh it derives ($sh-based) flows into every helper script Configure
    # generates at runtime (sharp, loc, ...) -- which patch-shebangs, acting only
    # on pre-existing #! lines, can't reach.
    sed -i "s|xxx='/bin/sh'|xxx='$sh'|" Configure

    # Configure decides whether '#!' shebangs work by writing a one-line script
    # "#!$xcat" and running it -- but xcat defaults to the host /bin/cat (then
    # /usr/bin/cat), which the sandbox denies executing. So the test silently
    # fails and Configure falls back to shebang-less ': use' scripts that the
    # kernel then can't exec at all. Point xcat at the store cat (on the build
    # PATH) so the shebang test runs an allowed interpreter and succeeds.
    sed -i "s|xcat=/bin/cat|xcat=$storecat|;s|xcat=/usr/bin/cat|xcat=$storecat|" Configure

    # The Errno extension scans the C <errno.h> for E* definitions. On Linux+gcc
    # it hardcodes "\$sysroot/usr/include" as the first place to look, finds the
    # host /usr/include/errno.h (which exists but the sandbox denies reading) and
    # dies. Point that probe at the store glibc headers instead, so it reads the
    # real, allowed errno.h.
    sed -i "s|\"\$sysroot/usr/include\"|\"$glibc/include\"|" ext/Errno/Errno_pm.PL

    # Cwd.pm hunts for a pwd command among hardcoded host paths (/bin/pwd,
    # /usr/bin/pwd) and shells out to it; the sandbox denies executing the host
    # binary, so cwd() comes back empty and MakeMaker dies "Can't figure out
    # your cwd!". Repoint the first candidate at the store pwd.
    sed -i "s|'/bin/pwd'|'$storepwd'|" dist/PathTools/Cwd.pm
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

    # Configure -des = non-interactive defaults. There is no /usr/include or
    # /usr/lib in the sandbox, so point Perl's system include/lib probes at the
    # glibc store prefix; -Dosname=linux forces hints/linux.sh (otherwise the
    # missing uname leaves osname empty and the wrong defaults load).
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
