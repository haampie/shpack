#!/bin/sh
# Fetch every source tarball the bootstrap needs into distfiles/, in parallel,
# and verify each against its sha256. Distfiles are no longer committed to the
# repo (see .gitignore); run this once before a build. Re-runs only download
# what is missing.
#
# The download list ("sha256  filename  url") is generated from the tree, so it
# never drifts from the recipes:
#   - packages:  each shpack/packages/*/package.sh is sourced with the recipe
#                directives stubbed, so its version/resource lines print their
#                "sha256= / url= / fname=" fields (hook functions are never run).
#   - bootstrap: shpack/bootstrap/*/sources.sha256 (sha256 + @DISTFILES@/fname)
#                paired by filename with the "# Source: URL [FNAME]" line in the
#                same dir's kaem.run (FNAME defaults to the URL basename; give it
#                explicitly only when the saved name differs, e.g. tcc-0.9.26).
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
dest=distfiles
jobs=${JOBS:-8}
mkdir -p "$dest"

repo=shpack/packages
boot=shpack/bootstrap

# Packages: source each recipe in a subshell with the directives stubbed.
# version/resource emit "sha  fname  url"; the rest are no-ops and the recipe's
# hook functions (install/configure_args/...) are defined but never called.
pkg_distfiles() {
    for p in "$repo"/*/package.sh; do
        [ -f "$p" ] || continue
        (
            description() { :; }; homepage() { :; }; license() { :; }
            depends_on()  { :; }; patch()    { :; }; build_system() { :; }
            parallel()    { :; }; build_directory() { :; }
            emit() {
                sha=- url=- fname=-
                for kv in "$@"; do
                    case $kv in
                        sha256=*) sha=${kv#*=} ;;
                        url=*)    url=${kv#*=} ;;
                        fname=*)  fname=${kv#*=} ;;
                    esac
                done
                [ "$sha" = - ] && return 0          # version with no source
                [ "$fname" = - ] && [ "$url" != - ] && fname=${url##*/}
                printf '%s  %s  %s\n' "$sha" "$fname" "$url"
            }
            version()  { shift; emit "$@"; }        # drop the version string
            resource() { emit "$@"; }
            . "$p"
        )
    done
}

# Bootstrap: sha256+fname come from each step's sources.sha256; the URL comes
# from the "# Source:" line in the same tree, paired by filename.
boot_distfiles() {
    srcmap=$(mktemp)
    for k in "$boot"/*/kaem.run; do
        [ -f "$k" ] || continue
        while read -r hash kw url fname _; do
            [ "$hash" = '#' ] && [ "$kw" = 'Source:' ] || continue
            [ -n "$fname" ] || fname=${url##*/}
            printf '%s\t%s\n' "$fname" "$url" >> "$srcmap"
        done < "$k"
    done
    for s in "$boot"/*/sources.sha256; do
        [ -f "$s" ] || continue
        while read -r sha path; do
            case "$sha" in ''|'#'*) continue ;; esac
            fname=${path##*/}
            url=$(awk -F'\t' -v f="$fname" '$1==f{print $2; exit}' "$srcmap")
            if [ -z "$url" ]; then
                echo "fetch-distfiles: no '# Source:' URL for bootstrap distfile $fname" >&2
                rm -f "$srcmap"
                exit 1
            fi
            printf '%s  %s  %s\n' "$sha" "$fname" "$url"
        done < "$s"
    done
    rm -f "$srcmap"
}

# Collect both layers, then dedup by filename (bzip2/musl appear in both). Two
# different sha256 for one filename is a real inconsistency -- fail loudly.
raw=$(mktemp)
{ pkg_distfiles; boot_distfiles; } > "$raw"
manifest=$(sort -u "$raw" | awk '
    $2 in sha { if (sha[$2] != $1) {
                    print "fetch-distfiles: " $2 " has conflicting sha256" > "/dev/stderr"
                    exit 1 }
                next }
    { sha[$2] = $1; print }')
rm -f "$raw"

# sha256 -c front-end: GNU coreutils vs. BSD/macOS.
if command -v sha256sum >/dev/null 2>&1; then
    sha256_check() { sha256sum -c -; }
elif command -v shasum >/dev/null 2>&1; then
    sha256_check() { shasum -a 256 -c -; }
else
    echo "fetch-distfiles: need sha256sum or shasum" >&2
    exit 1
fi

curlrc=$(mktemp)
checks=$(mktemp)
trap 'rm -f "$curlrc" "$checks"' EXIT INT TERM

# One curl config (url+output per entry) for the files we still need, plus a
# checksum list for everything (so a complete tree is re-verified for free).
printf '%s\n' "$manifest" | while read -r sha name url; do
    case "$sha" in ''|'#'*) continue ;; esac
    printf '%s  %s\n' "$sha" "$dest/$name" >> "$checks"
    [ -s "$dest/$name" ] && continue
    printf 'url = "%s"\noutput = "%s"\n' "$url" "$dest/$name" >> "$curlrc"
done

if [ -s "$curlrc" ]; then
    n=$(grep -c '^url' "$curlrc")
    echo "fetch-distfiles: downloading $n file(s) into $dest/ ($jobs in parallel)..."
    # Single parallel curl invocation. --remove-on-error drops partial/failed
    # outputs so a re-run retries them instead of skipping a truncated file.
    curl --fail --location --retry 3 --connect-timeout 30 \
         --remove-on-error --parallel --parallel-max "$jobs" \
         --config "$curlrc"
else
    echo "fetch-distfiles: all distfiles already present."
fi

echo "fetch-distfiles: verifying checksums..."
sha256_check < "$checks"
echo "fetch-distfiles: OK ($(grep -cvE '^\s*(#|$)' "$checks") files)."
