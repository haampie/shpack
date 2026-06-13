This project drives a Linux bootstrap from a few hundred bytes of binary seed up
to a real compiler toolchain, with a focus on speed. It supports both `x86_64`
and `AArch64` (live-bootstrap, whose ideas it borrows, is primarily `x86`).

The novel piece is **`shpack/`**: a Spack-shaped package manager, small enough
to run under the first shell a bootstrap has, that concretizes a package DAG
with Merkle-hashed store prefixes and builds everything up to GCC in parallel.
Recipes map 1:1 to Spack `package.py`, so a bootstrapped Spack can later take
over the store it built (see `shpack/README.md`).

Everything else is a **vendored layer of the software stack** that shpack grows
and drives -- the tcc/stack-machine seed compiler, a patched `kaem`, and the
upstream binary seeds -- each kept under `vendor/` with its provenance (see
`vendor/README.md`).

Bootstrapping speed is achieved by:

* dropping the detour that GNU mes takes to Scheme: a small C compiler
  (`vendor/mes-replacement/tcc_cc.c`) plus a stack-machine transpiler
  (`vendor/mes-replacement/stack_c_*.c`) grow TCC and musl directly out of
  [stage0-posix][3]
* using GNU make as a driver to expose package-level parallelism
* relaxing the requirement around generated scripts/sources (e.g. configure
  scripts bundled in release tarballs)

Packages install into immutable per-package store prefixes
(`/opt/<name>-<version>[-<hash>]`), Spack-style, driven by two pieces:

* **`shpack/bootstrap/`** -- a static kaem script chain that takes the
  system from the stage0 seed tools to the first shell (dash);
* **`shpack/`** -- the package manager described above, which then builds
  everything up to GCC.

## Layout

```
build.sh        the driver: stage a rootfs and run the seed
shpack/         the package manager (the contribution) + bootstrap/ kaem chain
vendor/         vendored stack layers, each with provenance:
  mes-replacement/  tcc_cc / stack_c seed compiler (+ committed *.sl64 seeds)
  kaem/             patched mescc-tools kaem
  stage0-posix/     upstream binary-seed submodule
distfiles/      upstream source tarballs for the shell phase
```

Run it with:

    ./build.sh amd64      # rootless (bwrap); ~2.5 min on a fast machine
    ./build.sh aarch64    # needs qemu-user-static binfmt with the F flag

[1]: https://github.com/FransFaase/MES-replacement
[2]: https://github.com/fosslinux/live-bootstrap/
[3]: https://github.com/oriansj/stage0-posix

This project builds on [MES replacement][1] (the seed compiler in
`vendor/mes-replacement/`) and some (but not all) of the ideas of
[live-bootstrap][2].
