# shpack

`shpack` is a fully self-bootstrappable package manager that builds a reproducible software stack from a few hundred bytes of binary seed. 

It bootstraps a working C and C++ compiler (GCC 4.7) in just 2 minutes and 30 seconds. From there, it continues to build a modern, dynamically linked toolchain (GCC 16, glibc 2.43, and binutils 2.46.0) in under 30 minutes total (benchmarked on an AMD Ryzen 7 3700X CPU from 2019).

It targets `x86_64` and `AArch64` natively from the start. This is critical for modern systems where 32-bit support (x86, arm32) is either disabled in the kernel or unsupported by the CPU (e.g., Apple Silicon).

Written entirely in POSIX shell (running on early `dash`, `make`, and minimal coreutils), it brings package management to the absolute bottom of the stack. Because it evaluates dependency DAGs and emits parallelizable Makefiles, it can be used to bootstrap a much wider ecosystem of software beyond just a base compiler. It provides a simple DSL for package recipes, making it incredibly easy to read, write, and maintain packages.

`shpack` borrows ideas from [Spack][4], Nix, and Guix, such as immutable store prefixes and Merkle-hashed dependency graphs. It is not a coincidence that the [declarative `package.sh` recipes][5] are reminiscent of the Spack package manager: a motivation for this project is to bootstrap the Spack package manager itself.

Thanks to Guix and [live-bootstrap][2] for showing a full bootstrap is possible, and to [MES replacement][1] for making it fast.

Bootstrapping speed is achieved by:

* Compiling natively the whole way, with no interpreter step (GNU mes runs a Scheme interpreter): a small C compiler (`vendor/mes-replacement/tcc_cc.c`) plus a stack-machine transpiler (`vendor/mes-replacement/stack_c_*.c`) grow TCC and musl directly out of [stage0-posix][3].
* Using early GNU make as a driver to expose package-level parallelism.

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

Paths in this section are relative to `shpack/`.

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