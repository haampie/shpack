# SPDX-License-Identifier: MIT
# End-to-end install on the host: fetch/stage a real tarball, dep PATH
# composition, store metadata, idempotency, two-stage bootstrap make.

. "$(dirname "$0")/common.sh"

# A real source tarball for the fetch+stage path.
mkdir -p "$TESTDIR/src/tarpkg-1.0"
echo "payload" > "$TESTDIR/src/tarpkg-1.0/hello.txt"
( cd "$TESTDIR/src" && tar -czf "$TESTDIR/distfiles/tarpkg-1.0.tar.gz" tarpkg-1.0 )
sha=$(sha256sum "$TESTDIR/distfiles/tarpkg-1.0.tar.gz")
sha=${sha%% *}

mkpkg liba <<'EOF'
version 1.0
build_system generic
depends_on dash
install() {
    mkdir -p "$PREFIX/bin"
    printf '#!/bin/sh\necho liba-says-hi\n' > "$PREFIX/bin/liba-cmd"
    chmod 755 "$PREFIX/bin/liba-cmd"
}
EOF

# gmake stand-in: exercises SHPACK_BOOTSTRAP_MAKE's two-stage scheduling.
mkpkg gmake <<'EOF'
version 4.4.1
build_system generic
depends_on liba dash
install() { mkdir -p "$PREFIX/bin"; }
EOF

mkpkg tarpkg <<EOF
version 1.0 sha256=$sha url=http://example.invalid/tarpkg-1.0.tar.gz
build_system generic
depends_on liba gmake@4.4.1 dash
install() {
    # Runs inside the unpacked source dir; the dep's bin must be on PATH.
    [ -f hello.txt ] || die "not in the source dir"
    liba-cmd > /dev/null || die "dep bin not on PATH"
    mkdir -p "\$PREFIX/share"
    cp hello.txt "\$PREFIX/share/"
}
EOF

echo "SHPACK_BOOTSTRAP_MAKE=gmake@4.4.1" >> "$SHPACK_CONFIG"

shpack install tarpkg > "$TESTDIR/install.log" 2>&1 \
    || { cat "$TESTDIR/install.log"; fail "install failed"; }

# Store contents + metadata.
ah=$(index_field liba 3); th=$(index_field tarpkg 3)
aprefix=$TESTDIR/store/liba-1.0-$ah
tprefix=$TESTDIR/store/tarpkg-1.0-$th
assert_file "$aprefix/bin/liba-cmd"
assert_file "$tprefix/share/hello.txt"
assert_file "$tprefix/.shpack/spec"
assert_file "$tprefix/.shpack/manifest"
assert_file "$tprefix/.shpack/package.sh"
assert_file "$tprefix/.shpack/build.log"
assert_contains "$tprefix/.shpack/spec" "name tarpkg"
assert_contains "$tprefix/.shpack/deps" "liba-1.0-$ah"

# Stage dirs are cleaned up after success.
for d in "$SHPACK_VAR/stage"/*; do
    if [ -e "$d" ]; then fail "stage dir $d not cleaned"; fi
done

# Idempotency layer 1: with stamps intact, make skips everything.
shpack install tarpkg > "$TESTDIR/install2.log" 2>&1 \
    || { cat "$TESTDIR/install2.log"; fail "stamped re-install failed"; }
case $(cat "$TESTDIR/install2.log") in
    *"=> tarpkg"*) fail "stamped re-install must not re-run build-one" ;;
esac

# Idempotency layer 2: stamps gone (fresh chroot/VAR), build-one finds the
# spec already in the store and short-circuits.
rm -rf "$SHPACK_VAR/stamps"
shpack install tarpkg > "$TESTDIR/install3.log" 2>&1 \
    || { cat "$TESTDIR/install2.log"; fail "re-install failed"; }
assert_contains "$SHPACK_VAR/logs/tarpkg-1.0.log" "already installed"

# Corrupt distfile is rejected.
mkpkg badpkg <<EOF
version 1.0 sha256=0000000000000000000000000000000000000000000000000000000000000000 fname=tarpkg-1.0.tar.gz url=-
build_system generic
depends_on dash
install() { :; }
EOF
if shpack install badpkg > /dev/null 2>&1; then
    fail "expected bad checksum to fail the build"
fi

echo OK
