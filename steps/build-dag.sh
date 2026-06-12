#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Shell-phase driver: hand over to shpack, which concretizes the package DAG
# from /shpack/packages and schedules it with make (see shpack/README.md).
# This file only still exists because the kaem-phase script-generator's
# generated driver execs it; the whole steps/ mechanism is replaced by a
# static kaem chain in a later stage.
exec sh /shpack/bin/shpack install gcc-linaro
