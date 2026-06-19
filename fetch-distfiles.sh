#!/bin/sh
# Fetch every source tarball the bootstrap needs into distfiles/, in parallel,
# and verify each against its sha256. Distfiles are no longer committed to the
# repo (see .gitignore); run this once before a build. Re-runs only download
# what is missing.
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
8c3850195d1c093d290a716e20ebcaa72eda32abf5e3d8611154b39cff79e9ea  binutils-2.30.tar.gz              https://mirrors.kernel.org/gnu/binutils/binutils-2.30.tar.gz
0f3152632a2a9ce066f20963e9bb40af7cf85b9b6c409ed892fd0676e84ecd12  binutils-2.46.0.tar.bz2           https://mirrors.kernel.org/gnu/binutils/binutils-2.46.0.tar.bz2
9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2  bison-3.8.2.tar.xz                https://mirrors.kernel.org/gnu/bison/bison-3.8.2.tar.xz
d5f2489c4056a31528e3ada4adacc23d498532b0af1a980f2f76158162b139d6  diffutils-2.7.tar.gz              https://mirrors.kernel.org/gnu/diffutils/diffutils-2.7.tar.gz
813cd9405aceec5cfecbe96400d01e90ddad7b512d3034487176ce5258ab0f78  findutils-4.2.33.tar.gz           https://mirrors.kernel.org/gnu/findutils/findutils-4.2.33.tar.gz
5cc35def1ff4375a8b9a98c2ff79e95e80987d24f0d42fdbb7b7039b3ddb3fb0  gawk-3.0.4.tar.gz                 https://mirrors.kernel.org/gnu/gawk/gawk-3.0.4.tar.gz
694db764812a6236423d4ff40ceb7b6c4c441301b72ad502bb5c27e00cd56f78  gawk-5.3.1.tar.xz                 https://mirrors.kernel.org/gnu/gawk/gawk-5.3.1.tar.xz
50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79  gcc-16.1.0.tar.xz                 https://mirrors.kernel.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz
27769f64ef1d4cd5e2be8682c0c93f9887983e6cfd1a927ce5a0a2915a95cf8f  gcc-9.5.0.tar.xz                  https://ftpmirror.gnu.org/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz
d0ea2c72ceb66d3851986840dd8962941824a2980a8aca2a800abb5b489acedf  gcc-linaro-4.7-2013.11.tar.bz2    https://launchpadlibrarian.net/156843777/gcc-linaro-4.7-2013.11.tar.bz2
d9c86c6b5dbddb43a3e08270c5844fc5177d19442cf5b8df4be7c07cd5fa3831  glibc-2.43.tar.xz                 https://mirrors.kernel.org/gnu/glibc/glibc-2.43.tar.xz
7be3ad1641b99b17f6a8be6a976f1f954e997c41e919ad7e0c418fe848c13c97  gmp-4.3.2.tar.gz                  https://ftpmirror.gnu.org/gmp/gmp-4.3.2.tar.gz
498449a994efeba527885c10405993427995d3f86b8768d8cdf8d9dd7c6b73e8  gmp-6.1.0.tar.bz2                 https://ftpmirror.gnu.org/gmp/gmp-6.1.0.tar.bz2
ac28211a7cfb609bae2e2c8d6058d66c8fe96434f740cf6fe2e47b000d1c20cb  gmp-6.3.0.tar.bz2                 https://mirrors.kernel.org/gnu/gmp/gmp-6.3.0.tar.bz2
a32032bab36208509466654df12f507600dfe0313feebbcd218c32a70bf72a16  grep-2.4.tar.gz                   https://mirrors.kernel.org/gnu/grep/grep-2.4.tar.gz
01b414ba98fd189ecd544435caf3860ae2a790e3ec48f5aa70fdf42dc4c5c04a  linux-6.9.1.tar.xz                https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.9.1.tar.xz
a88f3ddaa7c89cf4c34284385be41ca85e9135369c333fdfa232f3bf48223213  m4-1.4.7.tar.bz2                  https://mirrors.kernel.org/gnu/m4/m4-1.4.7.tar.bz2
dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3  make-4.4.1.tar.gz                 https://ftpmirror.gnu.org/make/make-4.4.1.tar.gz
617decc6ea09889fb08ede330917a00b16809b8db88c29c31bfbb49cbf88ecc3  mpc-1.0.3.tar.gz                  https://ftpmirror.gnu.org/mpc/mpc-1.0.3.tar.gz
ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8  mpc-1.3.1.tar.gz                  https://mirrors.kernel.org/gnu/mpc/mpc-1.3.1.tar.gz
246d7e184048b1fc48d3696dd302c9774e24e921204221540745e5464022b637  mpfr-2.4.2.tar.gz                 https://ftpmirror.gnu.org/mpfr/mpfr-2.4.2.tar.gz
d3103a80cdad2407ed581f3618c4bed04e0c92d1cf771a65ead662cc397f7775  mpfr-3.1.4.tar.bz2                https://ftpmirror.gnu.org/mpfr/mpfr-3.1.4.tar.bz2
b9df93635b20e4089c29623b19420c4ac848a1b29df1cfd59f26cab0d2666aa0  mpfr-4.2.1.tar.bz2                https://mirrors.kernel.org/gnu/mpfr/mpfr-4.2.1.tar.bz2
a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4  musl-1.2.5.tar.gz                 https://www.musl-libc.org/releases/musl-1.2.5.tar.gz
6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181  sed-4.9.tar.xz                    https://ftpmirror.gnu.org/sed/sed-4.9.tar.xz
14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e  tar-1.35.tar.gz                   https://ftpmirror.gnu.org/tar/tar-1.35.tar.gz
f6f4910fd033078738bd82bfba4f49219d03b17eb0794eb91efbae419f4aba10  xz-5.2.5.tar.gz                   https://downloads.sourceforge.net/project/lzmautils/xz-5.2.5.tar.gz

# bootstrap seed
ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269  bzip2-1.0.8.tar.gz                https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
c25b36b8af6e0ad2a875daf4d6196bd0df28a62be7dd252e5f99a4d5d7288d95  coreutils-5.0.tar.bz2             https://mirrors.kernel.org/gnu/coreutils/coreutils-5.0.tar.bz2
6a474ac46e8b0b32916c4c60df694c82058d3297d8b385b74508030ca4a8f28a  dash-0.5.12.tar.gz                http://ftp.debian.org/debian/pool/main/d/dash/dash_0.5.12.orig.tar.gz
1ca41818a23c9c59ef1d5e1d00c0d5eaa2285d931c0fb059637d7c0cc02ad967  gzip-1.2.4.tar.gz                 https://mirrors.kernel.org/gnu/gzip/gzip-1.2.4.tar.gz
e2c1a73f179c40c71e2fe8abf8a8a0688b8499538512984da4a76958d0402966  make-3.82.tar.bz2                 https://mirrors.kernel.org/gnu/make/make-3.82.tar.bz2
1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3  musl-1.1.24.tar.gz                https://www.musl-libc.org/releases/musl-1.1.24.tar.gz
ecb5c6469d732bcf01d6ec1afe9e64f1668caba5bfdb103c28d7f537ba3cdb8a  patch-2.5.9.tar.gz                https://mirrors.kernel.org/gnu/patch/patch-2.5.9.tar.gz
c365874794187f8444e5d22998cd5888ffa47f36def4b77517a808dec27c0600  sed-4.0.9.tar.gz                  https://mirrors.kernel.org/gnu/sed/sed-4.0.9.tar.gz
c6c37e888b136ccefab903c51149f4b7bd659d69d4aea21245f61053a57aa60a  tar-1.12.tar.gz                   https://mirrors.kernel.org/gnu/tar/tar-1.12.tar.gz
6b8cbd0a5fed0636d4f0f763a603247bc1935e206e1cc5bda6a2818bab6e819f  tcc-0.9.26.tar.gz                 https://lilypond.org/janneke/tcc/tcc-0.9.26-1147-gee75a10c.tar.gz
de23af78fca90ce32dff2dd45b3432b2334740bb9bb7b05bf60fdbfc396ceb9c  tcc-0.9.27.tar.bz2                https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27.tar.bz2

# spack bootstrap (cpython + clingo + spack)
f9c65aa9c852eb8255b636fd9f07ce1c406f061ec19a2e7d508b318ca0c907d1  zlib-ng-2.3.3.tar.gz             https://github.com/zlib-ng/zlib-ng/archive/2.3.3.tar.gz
b3babbbb1461e13fe22c630a40c43885efcfbbbb585830c6f4c0d791cf82ba0b  re2c-3.0.tar.xz                  https://github.com/skvadrik/re2c/releases/download/3.0/re2c-3.0.tar.xz
c0a3b3f2912b2166f522d5010ffb6029d8454ee635f5ad7a3247e0be7f9a15c9  cmake-3.31.11.tar.gz             https://github.com/Kitware/CMake/releases/download/v3.31.11/cmake-3.31.11.tar.gz
b0dea9df23c863a7a50e825440f3ebffabd65df1497108e5d437747843895a4e  libffi-3.4.6.tar.gz              https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz
10d4647cfbb543a7f9ae3e5f6851ec49305232ea7621aed24c7cfbb0bef4b70d  perl-5.40.2.tar.gz               https://www.cpan.org/src/5.0/perl-5.40.2.tar.gz
b1bfedcd5b289ff22aee87c9d600f515767ebf45f77168cb6d64f231f518a82e  openssl-3.6.1.tar.gz             https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz
64dfd5b1026700e0a0a324964749da9adc69ae5e51e899bf16ff47d6fd0e9a5e  cacert-2025-08-12.pem            https://curl.se/ca/cacert-2025-08-12.pem
7e32597b99e5d9a39abed35de4693fa169df3e5850d4c334337ffd6a19a36db6  Python-3.14.5.tar.xz             https://www.python.org/ftp/python/3.14.5/Python-3.14.5.tar.xz
7818eef2296c17ad38a57a77f7925c8df41744c4e736ab81042df95c1330f43b  clingo-2a025667.tar.gz           https://github.com/potassco/clingo/archive/2a025667090d71b2c9dce60fe924feb6bde8f667.tar.gz
ab2ac6601292619f94831065ee5c009f3168e14be52a65df7b9abdc20a1fc33f  clasp-b089aa15.tar.gz            https://github.com/potassco/clasp/archive/b089aa1509511ab403c0b9abd0d13eb9e873af44.tar.gz
41eb8b7d87ecea48392de4ada455cda179cbd62fd63496355dea87e1e44b599f  libpotassco-2f9fb7ca.tar.gz      https://github.com/potassco/libpotassco/archive/2f9fb7ca2c202f1b47643aa414054f2f4f9c1821.tar.gz
aeda9424b679cbbbc338bc55fd93a95b9c2eb24a010d4ea701f0d60c416f4e28  spack-packages-119680ae.tar.gz   https://github.com/spack/spack-packages/archive/119680aeee8ea802c6111b7167583bddef97e82f.tar.gz
518474f546e87723c43b80143d83a51c065a8d54333c8140da6f48bc7d9e50c1  spack-1.1.0.tar.gz               https://github.com/spack/spack/releases/download/v1.1.0/spack-1.1.0.tar.gz

# spack gcc-16 userland (bzip2-1.0.8 + cacert pem above; sed-4.9 + tar-1.35 reuse
# the musl-build distfiles already listed; -musl/glibc share one tarball)
e8bb26ad0293f9b5a1fc43fb42ba970e312c66ce92c1b0b16713d7500db251bf  coreutils-9.7.tar.xz             https://ftpmirror.gnu.org/coreutils/coreutils-9.7.tar.xz
1f31014953e71c3cddcedb97692ad7620cb9d6d04fbdc19e0d8dd836f87622bb  grep-3.11.tar.gz                 https://ftpmirror.gnu.org/grep/grep-3.11.tar.gz
f8c3486509de705192138b00ef2c00bbbdd0e84c30d5c07d23fc73a9dc4cc9cc  gawk-5.3.2.tar.xz                https://ftpmirror.gnu.org/gawk/gawk-5.3.2.tar.xz
33bf69c0d6c698e83a68f77e6c1f465778e418ca0b3d59860d3ab446f4ac99a6  xz-5.8.3.tar.bz2                 https://github.com/tukaani-project/xz/releases/download/v5.8.3/xz-5.8.3.tar.bz2
613d6ea44f1248d7370c7ccdeee0dd0017a09e6c39de894b3c6f03f981191c6b  gzip-1.14.tar.gz                 https://ftpmirror.gnu.org/gzip/gzip-1.14.tar.gz
f87cee69eec2b4fcbf60a396b030ad6aa3415f192aa5f7ee84cad5e11f7f5ae3  patch-2.8.tar.xz                 https://ftpmirror.gnu.org/patch/patch-2.8.tar.xz
036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37  unzip60.tar.gz                   https://downloads.sourceforge.net/infozip/unzip60.tar.gz
37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3  zstd-1.5.7.tar.gz                https://github.com/facebook/zstd/archive/v1.5.7.tar.gz
429dc0f5fe5f14109930cdbbb588c5d6ef5b8528910f0d738040744bebdc6275  git-2.53.0.tar.gz                https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.53.0.tar.gz
da8d640f55036b1f5c9cd950083248ec956256959dc74584e12c43550d6ec0ef  nghttp2-1.67.1.tar.gz            https://github.com/nghttp2/nghttp2/releases/download/v1.67.1/nghttp2-1.67.1.tar.gz
f5833dd2e1cd7739ec9182804a1a29c4f0cc7c2f26b633d3a2188b7766a88ecb  expat-2.8.1.tar.bz2              https://github.com/libexpat/libexpat/releases/download/R_2_8_1/expat-2.8.1.tar.bz2
d34f02e113cf7193a1ebf2770d3ac527088d485d4e047ed10e5d217c6ef5de96  pcre2-10.44.tar.bz2              https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.bz2
4be48e69cf467246cb97d369b85d78a08528f2b37cffef2418ee16e6a4eb596e  curl-8.20.0.tar.bz2              https://curl.se/download/curl-8.20.0.tar.bz2
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
