#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Run the shpack test suite on the host. Uses dash when available, since
# dash 0.5.12 is the shell shpack runs under in the bootstrap.

cd "$(dirname "$0")" || exit 1

if [ -n "${TEST_SH:-}" ]; then
    runner=$TEST_SH
elif command -v dash > /dev/null 2>&1; then
    runner=dash
else
    echo "warning: dash not found, falling back to sh" >&2
    runner=sh
fi

fail=0
for t in t-*.sh; do
    log=/tmp/shpack-test-${t%.sh}.log
    if "$runner" "$t" > "$log" 2>&1; then
        printf 'PASS %s\n' "$t"
    else
        printf 'FAIL %s (log: %s)\n' "$t" "$log"
        tail -n 20 "$log" | sed 's/^/    /'
        fail=1
    fi
done
exit $fail
