# SPDX-License-Identifier: MIT
# Merkle hashing: determinism, and propagation along (only) the dependents.

. "$(dirname "$0")/common.sh"

mkpkg liba <<'EOF'
version 1.0
build_system generic
install() { :; }
EOF

mkpkg libb <<'EOF'
version 2.0
build_system generic
depends_on liba
install() { :; }
EOF

mkpkg tool <<'EOF'
version 0.5
build_system generic
depends_on libb
install() { :; }
EOF

shpack concretize tool > /dev/null
a1=$(index_field liba 3); b1=$(index_field libb 3); t1=$(index_field tool 3)

# Determinism: a second concretization reproduces the same hashes.
shpack concretize tool > /dev/null
assert_eq "$(index_field liba 3)" "$a1" "liba hash determinism"
assert_eq "$(index_field libb 3)" "$b1" "libb hash determinism"
assert_eq "$(index_field tool 3)" "$t1" "tool hash determinism"

# Editing the leaf recipe changes every hash above it (Merkle property).
echo "# tweak" >> "$SHPACK_REPO/liba/package.sh"
shpack concretize tool > /dev/null
a2=$(index_field liba 3); b2=$(index_field libb 3); t2=$(index_field tool 3)
[ "$a2" != "$a1" ] || fail "liba hash must change when its recipe changes"
[ "$b2" != "$b1" ] || fail "libb hash must change when a dep changes"
[ "$t2" != "$t1" ] || fail "tool hash must change transitively"

# Editing the middle recipe leaves the leaf alone.
echo "# tweak" >> "$SHPACK_REPO/libb/package.sh"
shpack concretize tool > /dev/null
assert_eq "$(index_field liba 3)" "$a2" "liba hash stable"
[ "$(index_field libb 3)" != "$b2" ] || fail "libb hash must change"

# A patches/ file is hashed recipe content too.
mkdir -p "$SHPACK_REPO/tool/patches"
echo "fake patch" > "$SHPACK_REPO/tool/patches/x.patch"
t3=$(index_field tool 3)
shpack concretize tool > /dev/null
[ "$(index_field tool 3)" != "$t3" ] || fail "patch file must affect hash"

# Conditional deps: two versions of one recipe whose dep sets differ by
# when=VER must hash differently (different resolved deps -> different
# manifest), with no manifest code change.
mkpkg cdep-x <<'EOF'
version 1.0
build_system generic
install() { :; }
EOF
mkpkg cdep-y <<'EOF'
version 1.0
build_system generic
install() { :; }
EOF
mkpkg cmulti <<'EOF'
version 4.7
version 8.5
build_system generic
depends_on cdep-x when=4.7
depends_on cdep-y when=8.5
install() { :; }
EOF
shpack concretize cmulti@4.7 > /dev/null
m47=$(index_field cmulti 3)
shpack concretize cmulti@8.5 > /dev/null
m85=$(index_field cmulti 3)
[ "$m47" != "$m85" ] || fail "conditional deps must give the two versions different hashes"

echo OK
