# shpack/bootstrap -- the kaem-phase package chain

This directory is the *pre-shell* half of the bootstrap: a static,
hand-written chain of kaem scripts that builds everything from the stage0
seed tools up to the first shell (dash), then execs `shpack install
gcc-linaro`. It replaces the live-bootstrap manifest/configurator/
script-generator machinery with ~nothing: the package order is fixed, so the
whole "manager" is `0.kaem.in` (staged as `/shpack/bootstrap/0.kaem` with
`@TOKEN@`s substituted by `build.sh`).

## Conventions

One directory per package, named `<name>-<version>` to match its store
prefix `/opt/<name>-<version>` (the kaem phase cannot compute spec hashes;
these prefixes are registered as shpack *externals* in `etc/externals.in`).

Each directory holds:

- `kaem.run` -- the build script, run by a child `kaem --strict` from
  `0.kaem`. It builds in `${TMPDIR}/build/${pkg}` and installs into
  `${PREFIX}`/`${BINDIR}`.
- `sources.sha256` -- `sha256sum -c` lines pinning the upstream tarball(s) in
  `${DISTFILES}`; checked first thing by `kaem.run`.
- package assets (`files/`, `patches/`, `mk/`, `simple-patches/`, the musl
  per-arch trees, ...) referenced as `${PKG}/...`. Some makefiles and patches
  are vendored from live-bootstrap (see the SPDX headers for provenance).

Environment contract (set in `0.kaem`, inherited by every `kaem.run`):

| var | value |
|---|---|
| `ARCH` | `amd64` / `aarch64` |
| `DISTFILES` | `/external/distfiles` |
| `TMPDIR` | `/tmp` |
| `BOOT` | `/shpack/bootstrap` |
| `LIBC_PREFIX`/`LIBDIR`/`INCDIR` | the musl store prefix and its lib/include |
| `pkg`, `PKG` | `<name-version>`, `${BOOT}/${pkg}` |
| `PREFIX`, `BINDIR` | `/opt/${pkg}`, `${PREFIX}/bin` |

`PATH` starts as the seed prefixes (`@SEED_PATH@`) and grows one
`/opt/<pkg>/bin` prepend per package, newest first -- the same composition
rule shpack uses later.

The `kaem.run` command sequences are dictated by what each package needs to
compile under tcc/musl (object lists, `-D` macros, boot stages); the
rationale lives in the comments of each script.

## Why this is not under `shpack/packages/`

shpack hashes a recipe directory's full contents into the spec hash of that
package (and, Merkle-style, of everything depending on it). Kaem-phase
assets are not inputs to the shell-phase recipes, so keeping them here
avoids a kaem.run comment edit rebuilding the entire gcc closure. The
shell-phase handoff sees these packages only as externals with fixed
prefixes.
