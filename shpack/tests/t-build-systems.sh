# SPDX-License-Identifier: MIT
# makefile and autotools build systems, patch application, hooks.

. "$(dirname "$0")/common.sh"

# makefile package: recipe-shipped Makefile (the bootstrap replacement-
# makefile pattern) + a patch that fixes the staged source.
mkdir -p "$TESTDIR/src/mkpkg-1.0"
printf 'broken\n' > "$TESTDIR/src/mkpkg-1.0/data.in"
( cd "$TESTDIR/src" && tar -czf "$TESTDIR/distfiles/mkpkg-1.0.tar.gz" mkpkg-1.0 )
sha=$(sha256sum "$TESTDIR/distfiles/mkpkg-1.0.tar.gz")
sha=${sha%% *}

mkpkg mkpkg <<EOF
version 1.0 sha256=$sha url=http://example.invalid/mkpkg-1.0.tar.gz
build_system makefile
patch fix-data.patch
EOF

mkdir -p "$SHPACK_REPO/mkpkg/files" "$SHPACK_REPO/mkpkg/patches"
cat > "$SHPACK_REPO/mkpkg/files/Makefile" <<'EOF'
all: data.out
data.out: data.in
	cp data.in data.out
install: data.out
	mkdir -p $(PREFIX)/share
	cp data.out $(PREFIX)/share/data.out
EOF
cat > "$SHPACK_REPO/mkpkg/patches/fix-data.patch" <<'EOF'
--- a/data.in
+++ b/data.in
@@ -1 +1 @@
-broken
+fixed
EOF

# autotools package: fake configure script proves --prefix and the
# configure_args hook arrive.
mkdir -p "$TESTDIR/src/atpkg-2.0"
cat > "$TESTDIR/src/atpkg-2.0/configure" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > config.args
cat > Makefile <<'MK'
all:
	cp config.args out.txt
install:
	mkdir -p $(PREFIX)/share
	cp out.txt $(PREFIX)/share/
MK
EOF
chmod 755 "$TESTDIR/src/atpkg-2.0/configure"
( cd "$TESTDIR/src" && tar -czf "$TESTDIR/distfiles/atpkg-2.0.tar.gz" atpkg-2.0 )
sha=$(sha256sum "$TESTDIR/distfiles/atpkg-2.0.tar.gz")
sha=${sha%% *}

mkpkg atpkg <<EOF
version 2.0 sha256=$sha url=http://example.invalid/atpkg-2.0.tar.gz
build_system autotools
parallel false
configure_args() {
    # One argument per line; arguments may contain spaces.
    printf '%s\n' --disable-nls --enable-static 'CXXCPP=tcc -E'
}
install_targets() {
    echo install
}
EOF

# out-of-tree autotools package: build_directory makes configure run from a
# subdir against the source tree's configure. The fake configure records its
# cwd so the test can prove it ran out-of-tree.
mkdir -p "$TESTDIR/src/ootpkg-1.0"
cat > "$TESTDIR/src/ootpkg-1.0/configure" <<'EOF'
#!/bin/sh
pwd > where.txt
printf '%s\n' "$@" > config.args
cat > Makefile <<'MK'
all:
	cp where.txt out.txt
	cat config.args >> out.txt
install:
	mkdir -p $(PREFIX)/share
	cp out.txt $(PREFIX)/share/
MK
EOF
chmod 755 "$TESTDIR/src/ootpkg-1.0/configure"
( cd "$TESTDIR/src" && tar -czf "$TESTDIR/distfiles/ootpkg-1.0.tar.gz" ootpkg-1.0 )
sha=$(sha256sum "$TESTDIR/distfiles/ootpkg-1.0.tar.gz")
sha=${sha%% *}

mkpkg ootpkg <<EOF
version 1.0 sha256=$sha url=http://example.invalid/ootpkg-1.0.tar.gz
build_system autotools
parallel false
build_directory _build
EOF

shpack install mkpkg atpkg ootpkg > "$TESTDIR/install.log" 2>&1 \
    || { cat "$TESTDIR/install.log"; fail "install failed"; }

mh=$(index_field mkpkg 3); ah=$(index_field atpkg 3)
assert_file "$TESTDIR/store/mkpkg-1.0-$mh/share/data.out"
assert_eq "$(cat "$TESTDIR/store/mkpkg-1.0-$mh/share/data.out")" fixed \
    "patched + makefile-built content"

out=$TESTDIR/store/atpkg-2.0-$ah/share/out.txt
assert_file "$out"
assert_contains "$out" "--prefix=$TESTDIR/store/atpkg-2.0-$ah"
assert_contains "$out" "--disable-nls"
# A hook line with spaces must arrive as ONE argument (one line in out.txt).
assert_contains "$out" "CXXCPP=tcc -E"

# out-of-tree: configure ran in the _build subdir and --prefix still arrived.
oh=$(index_field ootpkg 3)
oout=$TESTDIR/store/ootpkg-1.0-$oh/share/out.txt
assert_file "$oout"
assert_contains "$oout" "/_build"
assert_contains "$oout" "--prefix=$TESTDIR/store/ootpkg-1.0-$oh"

echo OK
