# SPDX-License-Identifier: MIT
# Version comparison unit tests.

set -e
. "$(dirname "$0")/../lib/spec.sh"

die() { printf 'die: %s\n' "$*" >&2; exit 1; }

gt() {
    if ! vercmp_gt "$1" "$2"; then
        printf 'FAIL: expected %s > %s\n' "$1" "$2" >&2
        exit 1
    fi
    if vercmp_gt "$2" "$1"; then
        printf 'FAIL: %s > %s must not hold both ways\n' "$2" "$1" >&2
        exit 1
    fi
}

eqv() {
    if vercmp_gt "$1" "$2" || vercmp_gt "$2" "$1"; then
        printf 'FAIL: expected %s == %s\n' "$1" "$2" >&2
        exit 1
    fi
}

gt 4.4.1 3.82
gt 0.9.27 0.9.26
gt 2.30 2.4          # numeric segments: 30 > 4
gt 4.4.1 4.4         # missing segment counts as 0
gt 1.1.24 1.1.2
gt 4.7-2013.11 4.7   # dash-separated date suffix
gt 4.7-2013.11 4.7-2013.10
gt 10 9
gt 1.0a 1.0          # alpha tail sorts after nothing
eqv 1.2.3 1.2.3
eqv 1.2 1.2.0

echo OK
