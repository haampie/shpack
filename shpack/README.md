# shpack

A package manager shaped like [Spack](https://spack.io), implemented in
portable POSIX shell, sized for the earliest moment a bootstrap has a shell
at all. It drives this repository's build chain from the first `/bin/sh`
(dash, built by the kaem phase) up to a real compiler toolchain — and is
designed so that once Python and Spack's other dependencies are bootstrapped,
the actual Spack can take over the store it built.

shpack is an original work (MIT). It deliberately borrows Spack's *model* —
recipes per package, declared dependencies, hashed per-package install
prefixes, build-system base classes, externals — and none of anyone's code.

## The model

- **One directory per package name**: `packages/<name>/package.sh`, with
  optional `patches/` and `files/`. A recipe declares versions (with source
  checksums), dependencies, patches and a build system via shell directives,
  and may override build phases with hook functions:

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

- **Concretization**: `shpack install <name>` resolves names to concrete
  versions (newest wins; `name@version` pins; the externals table wins ties),
  walks `depends_on` into a DAG, and assigns every node a **Merkle hash**:
  sha256 over the recipe text, auxiliary files, source checksums, target
  arch, and the hashes of all direct dependencies. Anything changing anywhere
  in a package's closure changes its hash.

- **Store**: every package installs into its own prefix
  `$STORE/<name>-<version>-<hash7>`, with metadata in `.shpack/` (spec, dep
  edges, the hash manifest, the recipe, the build log) — exactly what a
  future `spack reindex` needs to reconstruct concrete specs from the store.

- **Externals**: packages the kaem phase already installed (unhashed
  `/opt/<name>-<version>` prefixes) are registered in `etc/externals`,
  Spack-`packages.yaml`-style. They resolve like any other candidate and
  contribute their identity to dependents' hashes.

- **Scheduling**: concretization emits `dag.mk` (one stamp target per node,
  direct deps as prerequisites) and GNU make runs the DAG in parallel. Each
  build is its own process with a **precomposed PATH**: own prefix, then the
  dependency closure most-derived-first, then `BASEPATH` (the kaem-phase base
  layer + stage0 seed dirs). No runtime PATH composition, exactly one
  provider per tool. Logs are per-package; a failure prints the log tail and
  stops. When the DAG contains `SHPACK_BOOTSTRAP_MAKE` (gmake@4.4.1), it is
  built first serially under the race-prone bootstrap make 3.82, and
  everything else runs `-j$JOBS` under the new make's fifo jobserver.

## Build systems and phases

Every build runs: `fetch` (sha256-verify distfiles) → `stage` (unpack to a
scratch dir) → `patch` → build-system phases → `finalize` (write `.shpack/`
metadata). The build-system phases, each overridable by defining a function
of the same name in the recipe:

| build_system | phases | argument hooks |
|---|---|---|
| `generic` | `install` (required) | — |
| `makefile` | `edit build install` | `build_targets`, `install_targets` |
| `autotools` | `configure build install` | `configure_args`, `build_args`, `install_targets` |

Argument hooks emit **one argument per output line** (so arguments may
contain spaces: `printf '%s\n' 'AR=tcc -ar'`). Plus `setup_build_environment`,
run before the first phase. Recipes see:
`name`, `version`, `id`, `PREFIX`, `package_dir`, `stage_dir`, `ARCH`,
`JOBS`, `MAKEJOBS`, and `prefix_of <dep-name>`. `parallel false` disables
`-j` for the package's make. Caveat: a recipe that overrides `install()` and
needs the coreutils binary of the same name must call `command install`.

## CLI

```
shpack install <spec>...     concretize + build (spec: name or name@version)
shpack concretize <spec>...  resolve and emit dag.mk only
shpack build-one <id>        build one node (internal, called from dag.mk)
shpack env <name|id>         print a node's composed environment
shpack find                  list concretized/installed packages
```

State lives under `$SHPACK_VAR` (default `/tmp/shpack`): `spec/<id>/` node
dirs, `topo`, `index`, `dag.mk`, `stamps/`, `logs/`, `stage/`. The store
itself is the only persistent output; `build-one` short-circuits when a
node's prefix already carries `.shpack/spec`.

## The tool budget

shpack core runs under the first bootstrap shell: **dash 0.5.12, coreutils
5.0, sed 4.0.9, make 3.82, and the stage0 `sha256sum`**. There is no grep,
awk, find, xargs or mktemp at that point, and `expr`/`cut`/`tac` are avoided
to keep the budget small; `tests/t-lint.sh` enforces this. Configuration
(`etc/config`: ARCH, JOBS, STORE, DISTFILES, BASEPATH) is substituted on the
host by `build.sh` when staging the rootfs — there is no in-chroot
configurator.

## Tests

`tests/run.sh` runs the suite on the host under dash: version comparison,
resolution/concretization, Merkle-hash propagation, end-to-end installs of
toy packages (real tarballs, patches, all three build systems, two-stage
make bring-up), and the tool-budget lint. No chroot required.
