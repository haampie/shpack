This project builds on top of [MES replacement][1] and some (but not all) of
the ideas of [live-bootstrap][2], to bootstrap a Linux distro, with a focus on
speed.

It supports both `x86_64` and `AArch64`, whereas live-bootstrap is primarily
`x86`.

This is achieved by:

* dropping the detour that GNU mes takes to Scheme
* using gmake as a driver to expose package level parallelism
* dropping the requirement that generated scripts/sources are not allowed (e.g.
  configure scripts)

Further, it installs packages in a more nix-like style, with an immutable
prefix per package `/opt/pkg-1.2.3`.

[1]: https://github.com/FransFaase/MES-replacement
[2]: https://github.com/fosslinux/live-bootstrap/
