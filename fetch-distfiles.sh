#!/bin/sh
# Fetch every source tarball the bootstrap needs into distfiles/, in parallel,
# and verify each against its sha256. Distfiles are no longer committed to the
# repo (see .gitignore); run this once before build.sh. build.sh also calls it
# automatically. Re-runs only download what is missing.
#
# The manifest below is "sha256  filename  url", derived from the recipes:
#   - shpack/packages/*/package.sh   (version/resource "sha256=.. url=..")
#   - shpack/bootstrap/*/sources.sha256 + their "# Source:" URLs
# Keep it in sync when bumping a version.
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
dest=distfiles
jobs=${JOBS:-8}
mkdir -p "$dest"

manifest=$(cat <<'EOF'
# packages
c24a37c63a67f53bdd09c5f287b5cff8e8b98f857bf348c577d454d3f74db049  Python-3.5.9.tar.xz                https://www.python.org/ftp/python/3.5.9/Python-3.5.9.tar.xz
8c3850195d1c093d290a716e20ebcaa72eda32abf5e3d8611154b39cff79e9ea  binutils-2.30.tar.gz              https://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.gz
0f3152632a2a9ce066f20963e9bb40af7cf85b9b6c409ed892fd0676e84ecd12  binutils-2.46.0.tar.bz2           https://ftp.gnu.org/gnu/binutils/binutils-2.46.0.tar.bz2
9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2  bison-3.8.2.tar.xz                https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz
d5f2489c4056a31528e3ada4adacc23d498532b0af1a980f2f76158162b139d6  diffutils-2.7.tar.gz              https://mirrors.kernel.org/gnu/diffutils/diffutils-2.7.tar.gz
813cd9405aceec5cfecbe96400d01e90ddad7b512d3034487176ce5258ab0f78  findutils-4.2.33.tar.gz           https://mirrors.kernel.org/gnu/findutils/findutils-4.2.33.tar.gz
5cc35def1ff4375a8b9a98c2ff79e95e80987d24f0d42fdbb7b7039b3ddb3fb0  gawk-3.0.4.tar.gz                 https://mirrors.kernel.org/gnu/gawk/gawk-3.0.4.tar.gz
694db764812a6236423d4ff40ceb7b6c4c441301b72ad502bb5c27e00cd56f78  gawk-5.3.1.tar.xz                 https://ftp.gnu.org/gnu/gawk/gawk-5.3.1.tar.xz
50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79  gcc-16.1.0.tar.xz                 https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz
27769f64ef1d4cd5e2be8682c0c93f9887983e6cfd1a927ce5a0a2915a95cf8f  gcc-9.5.0.tar.xz                  https://ftpmirror.gnu.org/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz
d0ea2c72ceb66d3851986840dd8962941824a2980a8aca2a800abb5b489acedf  gcc-linaro-4.7-2013.11.tar.bz2    https://launchpadlibrarian.net/156843777/gcc-linaro-4.7-2013.11.tar.bz2
d9c86c6b5dbddb43a3e08270c5844fc5177d19442cf5b8df4be7c07cd5fa3831  glibc-2.43.tar.xz                 https://ftp.gnu.org/gnu/glibc/glibc-2.43.tar.xz
7be3ad1641b99b17f6a8be6a976f1f954e997c41e919ad7e0c418fe848c13c97  gmp-4.3.2.tar.gz                  https://ftpmirror.gnu.org/gmp/gmp-4.3.2.tar.gz
498449a994efeba527885c10405993427995d3f86b8768d8cdf8d9dd7c6b73e8  gmp-6.1.0.tar.bz2                 https://ftpmirror.gnu.org/gmp/gmp-6.1.0.tar.bz2
ac28211a7cfb609bae2e2c8d6058d66c8fe96434f740cf6fe2e47b000d1c20cb  gmp-6.3.0.tar.bz2                 https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.bz2
a32032bab36208509466654df12f507600dfe0313feebbcd218c32a70bf72a16  grep-2.4.tar.gz                   https://mirrors.kernel.org/gnu/grep/grep-2.4.tar.gz
01b414ba98fd189ecd544435caf3860ae2a790e3ec48f5aa70fdf42dc4c5c04a  linux-6.9.1.tar.xz                https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.9.1.tar.xz
a88f3ddaa7c89cf4c34284385be41ca85e9135369c333fdfa232f3bf48223213  m4-1.4.7.tar.bz2                  https://mirrors.kernel.org/gnu/m4/m4-1.4.7.tar.bz2
dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3  make-4.4.1.tar.gz                 https://ftpmirror.gnu.org/make/make-4.4.1.tar.gz
617decc6ea09889fb08ede330917a00b16809b8db88c29c31bfbb49cbf88ecc3  mpc-1.0.3.tar.gz                  https://ftpmirror.gnu.org/mpc/mpc-1.0.3.tar.gz
ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8  mpc-1.3.1.tar.gz                  https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz
246d7e184048b1fc48d3696dd302c9774e24e921204221540745e5464022b637  mpfr-2.4.2.tar.gz                 https://ftpmirror.gnu.org/mpfr/mpfr-2.4.2.tar.gz
d3103a80cdad2407ed581f3618c4bed04e0c92d1cf771a65ead662cc397f7775  mpfr-3.1.4.tar.bz2                https://ftpmirror.gnu.org/mpfr/mpfr-3.1.4.tar.bz2
b9df93635b20e4089c29623b19420c4ac848a1b29df1cfd59f26cab0d2666aa0  mpfr-4.2.1.tar.bz2                https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.bz2
a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4  musl-1.2.5.tar.gz                 https://www.musl-libc.org/releases/musl-1.2.5.tar.gz
6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181  sed-4.9.tar.xz                    https://ftpmirror.gnu.org/sed/sed-4.9.tar.xz
14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e  tar-1.35.tar.gz                   https://ftpmirror.gnu.org/tar/tar-1.35.tar.gz

# bootstrap seed
ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269  bzip2-1.0.8.tar.gz                https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
c25b36b8af6e0ad2a875daf4d6196bd0df28a62be7dd252e5f99a4d5d7288d95  coreutils-5.0.tar.bz2             https://ftp.gnu.org/gnu/coreutils/coreutils-5.0.tar.bz2
6a474ac46e8b0b32916c4c60df694c82058d3297d8b385b74508030ca4a8f28a  dash-0.5.12.tar.gz                http://gondor.apana.org.au/~herbert/dash/files/dash-0.5.12.tar.gz
1ca41818a23c9c59ef1d5e1d00c0d5eaa2285d931c0fb059637d7c0cc02ad967  gzip-1.2.4.tar.gz                 https://ftp.gnu.org/gnu/gzip/gzip-1.2.4.tar.gz
e2c1a73f179c40c71e2fe8abf8a8a0688b8499538512984da4a76958d0402966  make-3.82.tar.bz2                 https://ftp.gnu.org/gnu/make/make-3.82.tar.bz2
1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3  musl-1.1.24.tar.gz                https://www.musl-libc.org/releases/musl-1.1.24.tar.gz
ecb5c6469d732bcf01d6ec1afe9e64f1668caba5bfdb103c28d7f537ba3cdb8a  patch-2.5.9.tar.gz                https://ftp.gnu.org/gnu/patch/patch-2.5.9.tar.gz
c365874794187f8444e5d22998cd5888ffa47f36def4b77517a808dec27c0600  sed-4.0.9.tar.gz                  https://ftp.gnu.org/gnu/sed/sed-4.0.9.tar.gz
c6c37e888b136ccefab903c51149f4b7bd659d69d4aea21245f61053a57aa60a  tar-1.12.tar.gz                   https://ftp.gnu.org/gnu/tar/tar-1.12.tar.gz
6b8cbd0a5fed0636d4f0f763a603247bc1935e206e1cc5bda6a2818bab6e819f  tcc-0.9.26.tar.gz                 https://lilypond.org/janneke/tcc/tcc-0.9.26-1147-gee75a10c.tar.gz
de23af78fca90ce32dff2dd45b3432b2334740bb9bb7b05bf60fdbfc396ceb9c  tcc-0.9.27.tar.bz2                https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27.tar.bz2
EOF
)

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
