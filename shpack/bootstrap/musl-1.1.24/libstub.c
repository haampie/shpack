/* SPDX-License-Identifier: MIT */
/* Single dummy symbol so `tcc -ar` (which rejects empty archives) can build the
 * stub libm.a/libpthread.a/... archives. musl folds libm, librt, libpthread,
 * libdl, libutil, libresolv, libxnet and libcrypt into libc.a, but tcc and ld
 * still need the named archives to exist to satisfy -lm/-lpthread/etc. The real
 * symbols resolve from libc.a; these archives only need to exist. */
static int __musl_stub_lib;
