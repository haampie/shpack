# shpack

`shpack` is a fast, bootstrappable package manager for Linux. It builds a complete modern compiler toolchain (GCC 16, glibc 2.43, binutils 2.46) from source, starting from a few hundred bytes of trusted machine code (from [stage0-posix][3]). The first C/C++ compiler, GCC 4.7, comes up in about **2 minutes 30 seconds**, and the full dynamically linked toolchain finishes in **15**[^fast] to **30**[^bench] minutes total.

The project has two parts: the package manager itself, and the bootstrapping path it follows. It bootstraps a basic shell first, then increasingly capable C compilers and libraries, and finally the complete toolchain. The only binaries it trusts are that seed, the host kernel, and `bwrap` to set up the sandbox[^bwrap]; everything else is compiled from checksummed sources. It features a new bootstrapping path where the TinyCC C compiler with musl libc is built straight out of stage0-posix using [MES replacement][1].

It targets `x86_64` and `AArch64` natively from the start. That matters on modern systems, where 32-bit support (x86, arm32) may be disabled in the kernel or missing from the CPU (e.g. Apple Silicon).

The package manager is written entirely in POSIX shell, so it runs on an early `dash`, `make`, and minimal coreutils; it can take over as soon as the first real shell exists. Packages are described by small [declarative `package.sh` recipes][5] that are easy to read and maintain.

Its simple dependency resolver emits a `Makefile`, so independent packages build in parallel under a single `make` jobserver.

`shpack` borrows ideas from [Spack][4], Nix, and Guix, such as immutable store prefixes and Merkle-hashed dependency graphs. It is no coincidence that the `package.sh` recipes resemble Spack's: one motivation for the project is to bootstrap the Spack package manager itself. Thanks to Guix and [live-bootstrap][2] for showing that a full bootstrap is possible, and to [MES replacement][1] for making it fast.

A note on scope: `shpack` trusts the generated files that upstream ships in release tarballs, including `configure` scripts and pre-generated source files. live-bootstrap takes the stricter path and rebuilds those artifacts too. `shpack` makes the other tradeoff deliberately: optimizing for a modern, real-world toolchain that bootstraps quickly, and keeping the dependency set small -- regenerating those artifacts would otherwise pull flex, bison, autotools and texinfo into the chain.

## Bootstrapping a recent GNU compiler toolchain

The following is an end-to-end demo that:

1. sets up a `rootfs/`
2. bootstraps `shpack`'s own dependencies
3. runs `shpack install gcc` to build a modern GCC toolchain

```sh
git clone --recursive --depth=1 https://github.com/haampie/shpack.git
cd shpack
./fetch-distfiles.sh   # download sources of all packages
./build.sh amd64       # run the build up to latest GCC
./build.sh aarch64
```

`shpack` needs unprivileged user namespaces for its rootless `bwrap` sandbox. These are
enabled by default on most distributions, but Debian and Ubuntu restrict them. If `bwrap`
fails with a permission error, enable them:

```sh
sudo sysctl -w kernel.unprivileged_userns_clone=1   # Debian
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0   # Ubuntu 24.04+
```

Once `shpack` is bootstrapped, you will see that it runs `shpack install gcc`, which resolves the
dependencies:

```
...
+ exec ./run.sh shpack install gcc
dc9a082    gcc@16.1.0
e71e7f1      gcc-boot-wrapper@16.1.0
8a8e2e0        gcc-boot@16.1.0
202a56d          gmake@4.4.1
1040673            tcc@0.9.27 (external)
694c904            musl@1.1.24 (external)
7c75644            grep@2.4
94f28c9            gawk@3.0.4
91673cc          diffutils@2.7
9f213b5          findutils@4.2.33
adbb728          gcc-boot@9.5.0
3c33c33            gcc-boot@4.7-2013.11
fdacfc7              binutils@2.30-musl
903463f                m4@1.4.7
665c835              gmp@4.3.2
c7eb8d3              mpfr@2.4.2
beede4f              mpc@1.0.3
1c37955            musl@1.2.5
9fc6fea              linux-headers@6.9.1
7ec5e07                sed@4.9
33a495a                  xz@5.2.5
e74b1e3            tar@1.35
5fc3c72          binutils@2.46.0-musl
1dd3fe1        glibc@2.43
92e2484          python@3.5.9
3b062e1          bison@3.8.2
062a430          gawk@5.3.1
df74cac      binutils@2.46.0
0ee9ae9        libstdcxx-boot1@16.1.0
```

The `(external)` nodes are part of the initial bootstrapping phase.

All installed packages are put into unique prefixes `/opt/<name>-<version>[-<hash>]`.

## Entering the rootfs

You can also use the `shpack` package manager interactively by bootstrapping up to `shpack`
itself:

```sh
$ ./fetch-distfiles.sh
$ PROVISION_ONLY=1 ./build.sh amd64   # or aarch64
$ ./run.sh
# shpack install xz
# shpack install gcc
```

## shpack packages

Paths in this section are relative to [shpack/](shpack/)

### Recipes

One directory per package name: `packages/<name>/package.sh`, with optional
`patches/` and `files/`. A recipe declares versions (with source checksums),
dependencies, patches and a build system via shell directives, and may override
build phases with hook functions:

```sh
description "GNU binary utilities"
version 2.30 sha256=8c38... url=https://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.gz
build_system autotools
depends_on tcc musl gmake@4.4.1
patch arm64-elfnn-howto.patch arch=aarch64

configure_args() {
    printf '%s\n' --with-sysroot="$(prefix_of musl)" --disable-nls
}
```

A `version` line is repeatable, and `depends_on ... when=VER` ties a dependency
to one declared version (no `when=` means all versions), so one recipe can carry
several versions with different pinned deps:

```sh
version 4.7-2013.11 sha256=... url=...
version 8.5.0       sha256=... url=...
depends_on mpfr@2.4.2 when=4.7-2013.11
depends_on mpfr@3.1.6 when=8.5.0
```

### Concretization and store

`shpack install <name>` resolves names to concrete versions (newest wins;
`name@version` pins; the externals table wins ties), walks `depends_on` into a
DAG, and assigns every node a Merkle hash: sha256 over the recipe text,
auxiliary files, source checksums, target arch, and the hashes of all direct
dependencies. Anything changing anywhere in a package's closure changes its
hash.

Every package installs into its own prefix `$STORE/<name>-<version>-<hash7>`,
with metadata in `.shpack/` (spec, dep edges, the hash manifest, the recipe, the
build log) -- what a future `spack reindex` needs to reconstruct concrete specs
from the store. Packages the kaem phase already installed (unhashed
`/opt/<name>-<version>` prefixes) are registered in `etc/externals`,
Spack-`packages.yaml`-style; they resolve like any other candidate and
contribute their identity to dependents' hashes.

### Scheduling

Concretization emits `dag.mk` (one stamp target per node, direct deps as
prerequisites) and GNU make runs the DAG in parallel. Each build is its own
process with a precomposed PATH: own prefix, then the dependency closure
most-derived-first, then `BASEPATH` (the kaem-phase base layer plus stage0 seed
dirs). No runtime PATH composition, exactly one provider per tool. Logs are
per-package; a failure prints the log tail and stops. When the DAG contains
`SHPACK_BOOTSTRAP_MAKE` (gmake@4.4.1), it is built first serially under the
race-prone bootstrap make 3.82, and everything else runs `-j$JOBS` under the new
make's fifo jobserver.

### Build systems and phases

Every build runs: `fetch` (sha256-verify distfiles) -> `stage` (unpack to a
scratch dir) -> `patch` -> build-system phases -> `finalize` (write `.shpack/`
metadata). The build-system phases, each overridable by defining a function of
the same name in the recipe:

| build_system | phases | argument hooks |
|---|---|---|
| `generic` | `install` (required) | -- |
| `makefile` | `edit build install` | `build_targets`, `install_targets` |
| `autotools` | `configure build install` | `configure_args`, `build_args`, `install_targets` |

Argument hooks emit one argument per output line (so arguments may contain
spaces: `printf '%s\n' 'AR=tcc -ar'`). Plus `setup_build_environment`, run
before the first phase. Recipes see: `name`, `version`, `id`, `PREFIX`,
`package_dir`, `stage_dir`, `ARCH`, `JOBS`, `MAKEJOBS`, and `prefix_of
<dep-name>`. `parallel false` disables `-j` for the package's make. A recipe
that overrides `install()` and needs the coreutils binary of the same name must
call `command install`.

### CLI

```
shpack install <spec>...     concretize + build (spec: name or name@version)
shpack concretize <spec>...  resolve and emit dag.mk only
shpack build-one <id>        build one node (internal, called from dag.mk)
shpack env <name|id>         print a node's composed environment
shpack find                  list concretized/installed packages
```

State lives under `$SHPACK_VAR` (default `/tmp/shpack`): `spec/<id>/` node dirs,
`topo`, `index`, `dag.mk`, `stamps/`, `logs/`, `stage/`. The store itself is the
only persistent output; `build-one` short-circuits when a node's prefix already
carries `.shpack/spec`.

### Tool budget

shpack core runs under the first bootstrap shell: dash 0.5.12, coreutils 5.0,
sed 4.0.9, make 3.82, and the stage0 `sha256sum`. There is no grep, awk, find,
xargs or mktemp at that point, and `expr`/`cut`/`tac` are avoided to keep the
budget small; `tests/t-lint.sh` enforces this. Configuration (`etc/config`:
ARCH, JOBS, STORE, DISTFILES, BASEPATH) is substituted on the host by `build.sh`
when staging the rootfs -- there is no in-chroot configurator.

### Tests

`tests/run.sh` runs the suite on the host under dash: version comparison,
resolution/concretization, Merkle-hash propagation, end-to-end installs of toy
packages (real tarballs, patches, all three build systems, two-stage make
bring-up), and the tool-budget lint. No chroot required.

[^fast]: 14 minutes 9 seconds on an Intel Core Ultra 9 285 from 2025.
[^bench]: 28-29 minutes on an 8-core AMD Ryzen 7 3700X from 2019.
[^bwrap]: `bwrap` is used for convenience today; this may be replaced with a simpler `chroot`/`unshare`-based sandbox later.

[1]: https://github.com/FransFaase/MES-replacement
[2]: https://github.com/fosslinux/live-bootstrap
[3]: https://github.com/oriansj/stage0-posix
[4]: https://github.com/spack/spack
[5]: shpack/packages
