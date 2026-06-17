# SPDX-License-Identifier: MIT

description "Compiler wrapper: cc/gcc/c++/g++ shims that inject -I/-L/-rpath" \
            "for a package's direct dependencies (from SHPACK_*_DIRS set by the" \
            "builder), then exec the final gcc. A simpler take on" \
            "spack/compiler-wrapper. Sourceless shim."
homepage "https://github.com/haampie/shpack"
license "MIT"

# Sourceless: no url/sha256 -> nothing to fetch, builds in the stage dir.
version 1.0

build_system generic

# The final, shared, glibc-linked gcc. depends_on gcc puts this wrapper ahead of
# gcc on the composed PATH (reverse topo order), so its cc/gcc shadow the real
# ones; recipes that depend on compiler-wrapper get rpath injection for free.
depends_on gcc

install() {
    local gcc real prog triple
    gcc=$(prefix_of gcc)
    triple=$(triple gnu)

    mkdir -p "$PREFIX/bin"

    # One shim per driver. cc/gcc/cpp -> the C driver; c++/g++ -> the C++ driver.
    # The shim reads the colon-separated SHPACK_*_DIRS the builder exports from
    # this node's direct deps and prepends -I (always) / -L + -Wl,-rpath (link
    # mode only) so store deps win over anything else, like cc.sh. Bare version
    # probes pass through untouched so configure's compiler checks stay clean.
    emit() {
        real=$1
        cat > "$PREFIX/bin/$2" <<EOF
#!$sh
real=$real
case " \$* " in
    *" -v "*|*" --version "*|*" -dumpversion "*|*" -dumpmachine "*|*" -dumpspecs "*)
        exec "\$real" "\$@" ;;
esac
mode=ccld
for a in "\$@"; do
    case \$a in -E) mode=cpp ;; -S) mode=as ;; -c) mode=cc ;; esac
done
inc= lnk=
IFS=:
for d in \$SHPACK_INCLUDE_DIRS; do [ -n "\$d" ] && inc="\$inc -I\$d"; done
if [ "\$mode" = ccld ]; then
    for d in \$SHPACK_LINK_DIRS;  do [ -n "\$d" ] && lnk="\$lnk -L\$d"; done
    for d in \$SHPACK_RPATH_DIRS; do [ -n "\$d" ] && lnk="\$lnk -Wl,-rpath,\$d"; done
fi
unset IFS
exec "\$real" \$inc \$lnk "\$@"
EOF
        chmod 755 "$PREFIX/bin/$2"
    }

    for prog in cc gcc "$triple-gcc"; do emit "$gcc/bin/gcc" "$prog"; done
    for prog in c++ g++ "$triple-g++"; do emit "$gcc/bin/g++" "$prog"; done
}
