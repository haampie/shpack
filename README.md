# shpack

`shpack` is a fast, bootstrappable package manager for Linux. It is capable of building a complete modern compiler toolchain (GCC 16, glibc 2.43, binutils 2.46) from sources, starting from a few hundred bytes of trusted machine code (from [stage0-posix][3]). The first C/C++ compiler, GCC 4.7, comes up in about **2 minutes 30 seconds**, and the full dynamically linked toolchain finishes in **15 to 30 minutes**[^fast][^bench] total. It runs rootless and the default launcher does not require user namespaces.

The build itself trusts only a single binary seed. Everything else is compiled from checksummed sources. It bootstraps a basic shell first, then increasingly capable C compilers and libraries, and finally the complete toolchain using a new bootstrapping path where the TinyCC C compiler with musl libc is built straight out of stage0-posix via [MES replacement][1]. It targets `x86_64` and `AArch64` natively from the start, which matters on modern systems where 32-bit support (x86, arm32) may be disabled in the kernel or missing from the CPU (e.g. Apple Silicon).

`shpack` borrows ideas from [Spack][4], Nix, and Guix, such as immutable store prefixes and Merkle-hashed dependency graphs. It is no coincidence that the [`package.sh` recipes][5] resemble Spack's: one motivation for the project is to [bootstrap the Spack package manager itself](#shpack-install-spack). Thanks to Guix and [live-bootstrap][2] for showing that a full bootstrap is possible, and to [MES replacement][1] for making it fast.

## Quick start

### Setup

Clone the repository and download the package sources once:

```sh
git clone --recursive --depth=1 https://github.com/haampie/shpack.git
cd shpack
./fetch-distfiles.sh     # download the sources of every package
```

### Two ways to run

There are two launchers. Both provision the bootstrap base once (the stage0 seed up
through `dash`) and then drive `shpack` like any package manager. Pass a command to
run it directly, `sh` to drop into a shell with `shpack` on `PATH`, or nothing at all
(the default is `shpack install gcc`).

#### `run-local.sh`

`run-local.sh` builds directly on the host, without a chroot. This method should
work almost everywhere as it doesn't require user namespaces. It install into a local
`./store` (or any dir specified by `--store DIR`):

```console
$ ./run-local.sh shpack install gcc
...
[+] a062f54 gcc@16.1.0 /home/you/shpack/store/gcc-16.1.0-a062f54
```

and the installed compiler can be used directly without chroot:

```console
$ /home/you/shpack/store/gcc-16.1.0-a062f54/bin/g++ hello.cc -o hello
$ ./hello
hello world
```

Building without chroot might sound "nonreproducible", but builds are confined by a
[Linux Landlock][7] sandbox regardless of launcher, which itself is bootstrapped
early on, and packages bootstrapped prior to that do not use system file paths.
See [Sandboxing](#sandboxing) for more information.

#### `run-rootfs.sh`

`run-rootfs.sh` builds inside a changed root. It currently depends on
`bwrap`[^bwrap], for bind mounting in and change of root to `rootfs/`.  It is
more hermetic, but needs (unprivileged) user namespaces. It installs packages
to `/opt` inside the rootfs:

```console
$ ./run-rootfs.sh shpack install gcc
...
[+] a062f54 gcc@16.1.0 /opt/gcc-16.1.0-a062f54
```

User namespaces are enabled by default on most distributions, but Debian and
Ubuntu restrict them. If `run-rootfs.sh` fails with a permission error, either
use `run-local.sh` (which needs no namespaces) or enable them:

```sh
sudo sysctl -w kernel.unprivileged_userns_clone=1  # Debian
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0  # Ubuntu 24.04+
```

### Running interactively

Both `./run-local.sh CMD...` and `./run-rootfs.sh CMD...` execute the given command
after the shell is bootstrapped, which means you can use `shpack` interactively by
dropping in the just-built shell:

```sh
./run-local.sh sh    # drops you in bootstrapped dash
$ shpack install xz  # shpack is in PATH
```

### What `shpack install gcc` resolves

`shpack install gcc` resolves the dependency graph and builds it:

```
...
==> shpack install gcc
a062f54    gcc@16.1.0
b66470f      gcc-boot-wrapper@16.1.0
7218c8a        gcc-boot@16.1.0
43d2deb          gmake@4.4.1
055307c            tcc@0.9.27 (external)
9d99eb9            musl@1.1.24 (external)
91ab285            grep@2.4-musl
219a904              dash@0.5.12 (external)
646eea2            gawk@3.0.4
7ebe88e          diffutils@2.7
18a175e          findutils@4.2.33
d3b0c23          gcc-boot@9.5.0
2badc02            gcc-boot@4.7-2013.11
12ec57a              binutils@2.30-musl
81a84cb                m4@1.4.7
c61dffd              gmp@4.3.2
54f8c21              mpfr@2.4.2
57e6257              mpc@1.0.3
87b37c9            musl@1.2.5
07ee55e              linux-headers@6.9.1
5c56299                sed@4.9-musl
909212f                  xz@5.2.5-musl
1aeee0b            tar@1.35-musl
682b995          binutils@2.46.0-musl
eb38678        glibc@2.43
2881b9b          python@3.8.20
ccd90d5          bison@3.8.2
75c303a          gawk@5.3.1
f1e744e          dash@0.5.13.4
7ec050b            glibc@2.43-boot
cfe2ea5      binutils@2.46.0
287cc6b        libstdcxx-boot1@16.1.0
7c51198        zlib-ng@2.3.3-boot
d18a43d        zstd@1.5.7-boot
```

The `(external)` nodes are part of the initial bootstrapping phase. All installed
packages are put into unique prefixes `/opt/<name>-<version>[-<hash>]`.

### `shpack install spack`

`shpack install spack` continues past the toolchain and builds [Spack][4] 1.2.0
with its runtime: CPython 3.14 (including the `_ssl`, `_ctypes`, `zlib` and
`_bz2`/`_lzma`/`_zstd` modules), the clingo solver, and supporting tools such as
`git` and `curl`. It resolves and builds the same way as `gcc`, into its own
store prefix.

## Scope and trust

By design, `shpack` bootstraps *on top of a running Linux*: the build does syscalls (`execve` and friends), so it depends on the kernel's ABI, and getting it started leans on the ordinary userland (a shell, `sed`, coreutils) the launcher uses to stage and kick off the bootstrap. This is a deliberate scope, not full bare-metal trustlessness -- for that you would boot into the bootstrap and run it directly on hardware. What `shpack` aims for instead is reproducibility: the same seed and sources should yield the same toolchain across different Linux machines, so a [Thompson-style][6] compromise would have to be present on *every* host you compare to go unnoticed. `shpack` also trusts the generated files that upstream ships in release tarballs, including `configure` scripts and pre-generated source files. live-bootstrap takes the stricter path and rebuilds those artifacts too; `shpack` makes the other tradeoff deliberately, optimizing for a modern, real-world toolchain that bootstraps quickly and keeping the dependency set small -- regenerating those artifacts would otherwise pull flex, bison, autotools and texinfo into the chain.

---

# How it works

`shpack` is written entirely in POSIX shell, so it runs on an early `dash`, `make`,
and minimal coreutils; it can take over as soon as the first real shell exists. Its
simple dependency resolver emits a `Makefile`, so independent packages build in
parallel under a single `make` jobserver.

Paths in this section are relative to [shpack/](shpack/).

## Recipes

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

## Build systems and phases

Every build runs: `fetch` (sha256-verify distfiles) -> `stage` (unpack to a
scratch dir) -> `patch` -> build-system phases -> `finalize` (write `.shpack/`
metadata). The build-system phases, each overridable by defining a function of
the same name in the recipe:

| build_system | phases | argument hooks |
|---|---|---|
| `generic` | `edit install` (install required) | -- |
| `makefile` | `edit build install` | `build_targets`, `install_targets` |
| `autotools` | `edit configure build install` | `configure_args`, `build_args`, `install_targets` |

Argument hooks emit one argument per output line (so arguments may contain
spaces: `printf '%s\n' 'AR=tcc -ar'`). The `edit` phase (no-op by default;
makefile's default copies `files/Makefile`) is the home for programmatic source
mutation -- the `replace_bin_sh` repoint, in-tree resource relocation, stamp
rewrites -- so `setup_build_environment` (also run before the first phase) only
ever sets environment variables.

Recipes see lowercase shpack metadata and helpers -- `name`, `version`, `id`,
`package_dir`, `stage_dir`, `source_dir`, `sh` (the store shell), `makejobs`
(the `-jN` for make), `prefix_of <dep-name>`, `triple [libc] [vendor]`,
`replace_bin_sh FILE...` -- plus the UPPER env-var/config constants tools
consume: `PREFIX`, `ARCH`, `JOBS`. `parallel false` disables `-j` for the
package's make. A recipe that overrides `install()` and needs the coreutils
binary of the same name must call `command install`.

## Concretization and store

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

## Scheduling

Concretization emits `dag.mk` (one stamp target per node, direct deps as
prerequisites) and GNU make runs the DAG in parallel. Each build is its own
process with a precomposed PATH: own prefix, then the dependency closure
most-derived-first, then `BASEPATH` (the kaem-phase base layer plus stage0 seed
dirs). No runtime PATH composition, exactly one provider per tool. Logs are
per-package; a failure prints the log tail and stops. When the DAG contains
`SHPACK_BOOTSTRAP_MAKE` (gmake@4.4.1), it is built first serially under the
race-prone bootstrap make 3.82, and everything else runs `-j$JOBS` under the new
make's fifo jobserver.

## CLI

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

## Sandboxing

The launcher choice (host vs. chroot) is orthogonal to per-build isolation: both
launchers sandbox every build the same way. Every individual package build is
wrapped in a **Landlock sandbox** that restricts filesystem access to just that
build's declared inputs and its output prefix. That sandbox is a tiny
self-contained C program (`sandbox-1.0`) bootstrapped early in the chain -- right
after `tcc`+`musl` -- so it covers the entire shell phase. There is no `/bin/sh`
anywhere: the `shpack` wrapper and every build invoke the store `dash`
explicitly, so the host shell is never picked up.

This is what makes `run-local.sh` safe to run directly on the host: even with no
chroot, a build cannot read or write outside its declared inputs and output
prefix. `run-rootfs.sh` adds a change of root on top, hiding the host `/usr`
entirely, but the per-build confinement is identical either way.

## Tool budget

shpack core runs under the first bootstrap shell: dash 0.5.12, coreutils 5.0,
sed 4.0.9, make 3.82, and the stage0 `sha256sum`. There is no grep, awk, find,
xargs or mktemp at that point, and `expr`/`cut`/`tac` are avoided to keep the
budget small; `tests/t-lint.sh` enforces this. Configuration (`etc/config`:
ARCH, JOBS, STORE, DISTFILES, BASEPATH) is substituted on the host by the
launchers (`stage.sh`) when staging -- there is no in-chroot configurator.

## Tests

`tests/run.sh` runs the suite on the host under dash: version comparison,
resolution/concretization, Merkle-hash propagation, end-to-end installs of toy
packages (real tarballs, patches, all three build systems, two-stage make
bring-up), and the tool-budget lint. No chroot required.

[^fast]: 14 minutes 9 seconds on an Intel Core Ultra 9 285 from 2025.
[^bench]: 28-29 minutes on an 8-core AMD Ryzen 7 3700X from 2019.
[^bwrap]: `bwrap` is used for convenience today (only by `run-rootfs.sh`); this may be replaced with a simpler `chroot`/`unshare`-based sandbox later.

[1]: https://github.com/FransFaase/MES-replacement
[2]: https://github.com/fosslinux/live-bootstrap
[3]: https://github.com/oriansj/stage0-posix
[4]: https://github.com/spack/spack
[5]: shpack/packages
[6]: https://dl.acm.org/doi/10.1145/358198.358210
[7]: https://docs.kernel.org/userspace-api/landlock.html
