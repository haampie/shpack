# shpack

`shpack` bootstraps a basic, reproducible Linux environment natively from a few hundred bytes of
binary seed to a working GCC 4.7 (C and C++) in 2 minutes and 30 seconds.

Building on [MES replacement][1] and concepts from [live-bootstrap][2], shpack provides a fast,
natively 64-bit bootstrap path (currently targeting `x86_64` and `AArch64`, with RISC-V planned).

It borrows ideas from [Spack][4], Nix, and Guix, such as immutable store prefixes, Merkle-hashed
dependency graphs, and single, declarative `package.sh` recipes parametrized over all versions.
The main difference is that the language is POSIX shell, since that is one of the earliest
scripting languages available in the bootstrap chain.

Try it out:

```sh
git clone --recursive --depth=1 https://github.com/haampie/shpack.git
cd shpack
./build.sh amd64
./build.sh aarch64
```

Bootstrapping speed is achieved by:

* dropping the detour that GNU mes takes to Scheme: a small C compiler
  (`vendor/mes-replacement/tcc_cc.c`) plus a stack-machine transpiler
  (`vendor/mes-replacement/stack_c_*.c`) grow TCC and musl directly out of
  [stage0-posix][3]
* using early GNU make as a driver to expose package-level parallelism

Packages install into immutable per-package store prefixes
(`/opt/<name>-<version>[-<hash>]`), Spack-style, driven by two pieces:

* `shpack/bootstrap/` -- a static kaem script chain that takes the system from
  the stage0 seed tools to the first shell (dash);
* `shpack/` -- the package manager, which then builds everything up to GCC.


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
