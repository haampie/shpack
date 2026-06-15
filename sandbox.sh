# SPDX-License-Identifier: MIT
#
# sandbox.sh -- shared rootless-bwrap launcher, sourced by both phases:
#   build.sh (provision: run the kaem chain over the seed tree)
#   run.sh   (launch:    run shpack over the provisioned base)
#
# Both bind the rootfs at / with /dev, /proc and a RAM-backed build-scratch
# tmpfs at /tmp/shpack/stage; each caller adds its own --bind/--ro-bind, a
# --chdir and the command to exec. bwrap is rootless (unprivileged user
# namespaces), so nothing here needs sudo.

# sandbox ROOTFS [bwrap-arg...] -- everything after ROOTFS (extra binds, the
# --chdir, the command and its args) is passed straight to bwrap after the
# common prefix. Returns bwrap's exit status (so `set -e` callers abort on
# failure).
sandbox() {
    local rootfs
    rootfs=$1
    shift
    bwrap --unshare-all --bind "$rootfs" / --dev /dev --proc /proc \
        --tmpfs /tmp/shpack/stage "$@"
}
