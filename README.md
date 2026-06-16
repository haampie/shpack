# shpack

`shpack` is a fast, fully source-bootstrapping package manager for Linux. It starts from a few hundred bytes of trusted machine code (from [stage0-posix][3]) and builds everything above it from sources: from a basic shell, to increasinbly capable C compilers and libraries, up to a complete modern toolchain. The only binaries it trusts are that seed, `bwrap` to set up a sandbox, and the host kernel; everything else is compiled from checksummed sources.

The first C/C++ compiler, GCC 4.7, comes up in about **2 minutes and 30 seconds**, and a modern, dynamically linked toolchain (GCC 16, glibc 2.43, binutils 2.46) finishes in under 30 minutes total, benchmarked on an 8-core AMD Ryzen 7 3700X from 2019. It gets there by compiling natively the whole way, with no interpreter step: thanks to [MES replacement][1], the TCC C-compiler with musl libc is bootstrapped straight out of stage0-posix, and early GNU `make` then drives the package builds in parallel.

It targets `x86_64` and `AArch64` natively from the start. That matters on modern systems, where 32-bit support (x86, arm32) may be disabled in the kernel or missing from the CPU (e.g. Apple Silicon).

The package manager itself is written entirely in POSIX shell, running on an early `dash`, `make`, and minimal coreutils, bringing the package manager close to the bottom of the stack.

It features a simple dependency resolver that emits a `Makefile`, leading to package-level parallelism under a global jobserver.

`shpack` borrows ideas from [Spack][4], Nix, and Guix, such as immutable store prefixes and Merkle-hashed dependency graphs. Its small package recipe DSL stays easy to read, write, and maintain. It is no coincidence that the [declarative `package.sh` recipes][5] resemble Spack's: one motivation for the project is to bootstrap the Spack package manager itself. Thanks to Guix and [live-bootstrap][2] for showing that a full bootstrap is possible, and to [MES replacement][1] for making it fast.

A note on scope: `shpack` trusts the generated files that upstream ships in release tarballs, including `configure` scripts and pre-generated source files. live-bootstrap takes the stricter path and rebuilds those artifacts too; that rigor is its whole point. `shpack` makes the other tradeoff deliberately: optimizing for a modern, real-world toolchain that bootstraps quickly, and keeping the dependency set small -- regenerating those artifacts would otherwise pull flex, bison, autotools and texinfo into the chain.

## Bootstrapping a recent GNU compiler toolchain

Make sure you have `bwrap` available

```sh
git clone --recursive --depth=1 https://github.com/haampie/shpack.git
cd shpack
./fetch-distfiles.sh   # download sources of all packages
./build.sh amd64       # run the build up to latest GCC
./build.sh aarch64
```

This sets up the `rootfs/` directory, bootstraps `shpack` and then uses `shpack` to install
a modern GCC.

The packages are installed into immutable per-package store prefixes
(`/opt/<name>-<version>[-<hash>]`).

## Entering the rootfs

The `build.sh` script is a full demo that combines two steps:

1. bootstrapping `shpack`'s dependencies (`dash`, `make`, etc)
2. running `shpack install gcc`

You can run the bootstrap step manually and then start an interactive shell in the rootfs as
follows:

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

[1]: https://github.com/FransFaase/MES-replacement
[2]: https://github.com/fosslinux/live-bootstrap
[3]: https://github.com/oriansj/stage0-posix
[4]: https://github.com/spack/spack
[5]: shpack/packages