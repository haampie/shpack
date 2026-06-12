# SPDX-License-Identifier: MIT
# Concretization: resolution, externals, topo order, dag.mk shape.

. "$(dirname "$0")/common.sh"

mkpkg liba <<'EOF'
description "toy leaf library"
version 1.0
build_system generic
install() { :; }
EOF

mkpkg libb <<'EOF'
description "toy mid-layer, two versions"
version 2.0
version 2.1
build_system generic
depends_on liba
install() { :; }
EOF

mkpkg tool <<'EOF'
description "toy root"
version 0.5
build_system generic
depends_on libb@2.1 liba ext
install() { :; }
EOF

echo "ext@3.0 /fake/ext-3.0" > "$SHPACK_EXTERNALS"

shpack concretize tool > /dev/null

# Resolution: bare libb -> newest (2.1); ext -> external with its prefix.
assert_eq "$(index_field libb 2)" 2.1 "libb version"
assert_eq "$(index_field ext 4)" external "ext kind"
assert_eq "$(index_field ext 5)" /fake/ext-3.0 "ext prefix"
assert_eq "$(index_field tool 4)" built "tool kind"

# Topo order: dependencies before dependents.
topo=$(cat "$SHPACK_VAR/topo" | tr '\n' ' ')
case $topo in
    *liba-1.0*libb-2.1*tool-0.5*) ;;
    *) fail "bad topo order: $topo" ;;
esac

# Built prefix embeds name-version-hash in the store.
h=$(index_field tool 3)
assert_eq "$(index_field tool 5)" "$TESTDIR/store/tool-0.5-$h" "tool prefix"

# dag.mk: tool's stamp depends on libb's and liba's but not on the external.
assert_contains "$SHPACK_VAR/dag.mk" "build-one tool-0.5"
case $(cat "$SHPACK_VAR/dag.mk") in
    *"/ext-"*"build-one ext"*) fail "external must not get a build rule" ;;
esac

# tool's composed PATH: own prefix first, then deps, then the external's bin.
sh "$TESTROOT/bin/shpack" env tool > "$TESTDIR/env.out"
assert_contains "$TESTDIR/env.out" "tool-0.5-$h/bin:"
assert_contains "$TESTDIR/env.out" "/fake/ext-3.0/bin:"

# Pinned version resolves exactly.
shpack concretize libb@2.0 > /dev/null
assert_eq "$(index_field libb 2)" 2.0 "pinned libb version"

# Unknown packages and unknown deps fail loudly.
if shpack concretize nosuchpkg 2> /dev/null; then
    fail "expected concretize nosuchpkg to fail"
fi

mkpkg broken <<'EOF'
version 1.0
depends_on missingdep
EOF
if shpack concretize broken 2> /dev/null; then
    fail "expected unresolvable dep to fail"
fi

echo OK
