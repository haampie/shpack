# SPDX-License-Identifier: MIT
# The edit phase + replace_bin_sh: a recipe's edit() mutates the staged source
# before the build, and replace_bin_sh repoints the literal /bin/sh (not a #!
# line) at the store shell, covering the quoted-string and ["/bin/sh","-c"]
# forms uniformly.

. "$(dirname "$0")/common.sh"

# replace_bin_sh repoints /bin/sh at the build shell $sh, which is the declared
# dash dep's bin/sh (TEST_DASH_SH here), not CONFIG_SHELL.

# Toy source with /bin/sh hardcoded two ways (a quoted C string literal and
# Python's ["/bin/sh", "-c"] list) plus a marker the edit() hook will stamp,
# proving the phase ran. Neither /bin/sh is a #! shebang.
mkdir -p "$TESTDIR/src/edpkg-1.0"
cat > "$TESTDIR/src/edpkg-1.0/hard.txt" <<'EOF'
execl("/bin/sh", "sh", "-c", cmd);
args = ["/bin/sh", "-c"]
MARKER
EOF
( cd "$TESTDIR/src" && tar -czf "$TESTDIR/distfiles/edpkg-1.0.tar.gz" edpkg-1.0 )
sha=$(sha256sum "$TESTDIR/distfiles/edpkg-1.0.tar.gz")
sha=${sha%% *}

mkpkg edpkg <<'EOF'
version 1.0 sha256=SHA url=http://example.invalid/edpkg-1.0.tar.gz
build_system generic
depends_on dash
edit() {
    replace_bin_sh hard.txt
    sed -i 's/MARKER/edited/' hard.txt
}
install() {
    mkdir -p "$PREFIX/share"
    cp hard.txt "$PREFIX/share/hard.txt"
}
EOF
sed -i "s/SHA/$sha/" "$SHPACK_REPO/edpkg/package.sh"

shpack install edpkg > "$TESTDIR/install.log" 2>&1 \
    || { cat "$TESTDIR/install.log"; fail "install failed"; }

h=$(index_field edpkg 3)
out=$TESTDIR/store/edpkg-1.0-$h/share/hard.txt
assert_file "$out"
# edit() ran (custom sed after replace_bin_sh) ...
assert_contains "$out" "edited"
# ... and both /bin/sh forms got repointed at the build shell ($sh = the dash
# dep's bin/sh). $sh itself ends in /bin/sh, so assert the full transformed
# forms rather than the mere absence of the substring.
assert_contains "$out" "execl(\"$TEST_DASH_SH\", \"sh\", \"-c\", cmd);"
assert_contains "$out" "[\"$TEST_DASH_SH\", \"-c\"]"

echo OK
