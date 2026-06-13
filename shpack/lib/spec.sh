# SPDX-License-Identifier: MIT
#
# spec.sh -- spec naming, version comparison, and content hashing.
#
# A spec names a package at a concrete version. On the command line and in
# depends_on it is written "name" or "name@version"; once resolved it becomes
# the node id "name-version". Because versions may themselves contain dashes
# (gcc-4.7-2013.11 is name "gcc" at version "4.7-2013.11"), ids are never split
# back into parts: the name and version of a node are stored separately in its
# state dir.
#
# Every concretized node gets a DAG hash: sha256 over a canonical manifest of
# everything that determines its build -- the recipe text and auxiliary files,
# the source tarball checksums, the target architecture, and the (name,
# version, hash) of every direct dependency -- truncated to 7 hex digits.
# Dependency hashes make it a Merkle hash: any change anywhere in a package's
# closure changes its store prefix $STORE/<name>-<version>-<hash7>.

# sha256_file FILE -> print the 64-hex digest.
# Works with both GNU sha256sum and the stage0 (mescc-tools-extra) one: each
# prints "digest  filename".
sha256_file() {
    set -- $(sha256sum "$1")
    printf '%s\n' "$1"
}

# truncate7 STRING -> first 7 characters.
truncate7() {
    printf '%.7s\n' "$1"
}

# is_int STRING -> true if a non-empty string of digits.
is_int() {
    case $1 in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

# str_gt A B -> true if A sorts strictly after B (lexically, via sort(1)).
str_gt() {
    if [ "$1" = "$2" ]; then
        return 1
    fi
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort | tail -n 1)" = "$1" ]
}

# vercmp_gt A B -> true if version A is strictly newer than B.
# Versions are split on '.' and '-'; numeric segments compare numerically,
# mixed/alpha segments lexically; missing segments count as 0, so
# 4.4.1 > 4.4 and 0.9.27 > 0.9.26.
vercmp_gt() {
    local a b s1 s2
    a=$(printf '%s' "$1" | tr -- '-' '.')
    b=$(printf '%s' "$2" | tr -- '-' '.')
    while [ -n "$a" ] || [ -n "$b" ]; do
        s1=${a%%.*}
        if [ "$s1" = "$a" ]; then a=; else a=${a#*.}; fi
        s2=${b%%.*}
        if [ "$s2" = "$b" ]; then b=; else b=${b#*.}; fi
        if [ -z "$s1" ]; then s1=0; fi
        if [ -z "$s2" ]; then s2=0; fi
        if is_int "$s1" && is_int "$s2"; then
            if [ "$s1" -gt "$s2" ]; then return 0; fi
            if [ "$s1" -lt "$s2" ]; then return 1; fi
        else
            if str_gt "$s1" "$s2"; then return 0; fi
            if str_gt "$s2" "$s1"; then return 1; fi
        fi
    done
    return 1
}

# walk_files DIR [REL] -> print the relative paths of all regular files under
# DIR, depth-first. Glob expansion order is deterministic (sorted), which is
# what makes the recipe-content part of the hash canonical. Dotfiles are not
# package material and are skipped.
walk_files() {
    local f rel
    for f in "$1"/*; do
        if [ ! -e "$f" ]; then continue; fi
        rel="${2:+$2/}${f##*/}"
        if [ -d "$f" ]; then
            walk_files "$f" "$rel"
        else
            printf '%s\n' "$rel"
        fi
    done
}

# reverse_lines FILE -> the lines of FILE, last first. (No tac dependency.)
reverse_lines() {
    local line out
    out=
    while read -r line; do
        out="$line
$out"
    done < "$1"
    printf '%s' "$out"
}

# member_line STRING FILE -> true if FILE contains STRING as a whole line.
member_line() {
    local line
    while read -r line; do
        if [ "$line" = "$1" ]; then return 0; fi
    done < "$2"
    return 1
}
