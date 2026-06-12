This project builds on top of [MES replacement][1] and some (but not all) of
the ideas of [live-bootstrap][2], to bootstrap a Linux distro from a few
hundred bytes of binary seed, with a focus on speed.

It supports both `x86_64` and `AArch64`, whereas live-bootstrap is primarily
`x86`.

Bootstrapping speed is achieved by:

* dropping the detour that GNU mes takes to Scheme: a small C compiler
  (`src/tcc_cc.c`) plus a stack-machine transpiler (`src/stack_c_*.c`) grow
  TCC and musl directly out of [stage0-posix][3]
* using GNU make as a driver to expose package-level parallelism
* relaxing the requirement around generated scripts/sources (e.g. configure
  scripts bundled in release tarballs)

Packages install into immutable per-package store prefixes
(`/opt/<name>-<version>[-<hash>]`), Spack-style, driven by two pieces:

* **`shpack/bootstrap/`** -- a static kaem script chain that takes the
  system from the stage0 seed tools to the first shell (dash);
* **`shpack/`** -- a small Spack-shaped package manager in POSIX shell that
  concretizes a package DAG with Merkle-hashed store prefixes and builds
  everything up to GCC in parallel (see `shpack/README.md`). Recipes map
  1:1 to Spack `package.py`, so a bootstrapped Spack can later take over
  the store.

Run it with:

    ./build.sh amd64      # rootless (bwrap); ~2.5 min on a fast machine
    ./build.sh aarch64    # needs qemu-user-static binfmt with the F flag

[1]: https://github.com/FransFaase/MES-replacement
[2]: https://github.com/fosslinux/live-bootstrap/
[3]: https://github.com/oriansj/stage0-posix
