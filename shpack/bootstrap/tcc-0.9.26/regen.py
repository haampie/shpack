#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# regen.py -- derive the in-chroot `simple-patch` fragments for the aarch64 tcc
# backend fixes (patches/tcc-aarch64-0{2,3,4}-*.patch) and verify each reproduces
# GNU patch's result byte-for-byte against the pristine tcc source. (The patched
# files keep tcc's upstream names: arm64-gen.c, tccpp.c.)
#
# The chroot has no GNU patch, so tcc source edits are applied with `simple-patch
# FILE before after` (replaces the FIRST exact byte-match of `before`). Each hunk
# becomes one fragment pair  simple-patches/<patch>_<file>_<hunk>.{before,after}.
#
# Usage: regen.py <pristine-tcc-srcdir>
#   (the unpacked tcc-0.9.26-1147-gee75a10c tree; e.g. from distfiles).

import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, "patches")
SPDIR = os.path.join(HERE, "simple-patches")
PATCHSET = ["tcc-aarch64-02-codegen.patch",
            "tcc-aarch64-03-varargs.patch",
            "tcc-aarch64-04-long-double-suffix.patch"]

HUNK_RE = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")
NUM_RE = re.compile(r"(tcc-aarch64-\d+)")


def parse_patch(text):
    files, cur = [], None
    lines = text.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("--- ") and i + 1 < len(lines) \
                and lines[i + 1].startswith("+++ "):
            oldp = line[4:].split("\t")[0].strip()
            oldp = oldp[2:] if oldp.startswith(("a/", "b/")) else oldp
            cur = (oldp, [])
            files.append(cur)
            i += 2
            continue
        m = HUNK_RE.match(line) if cur is not None else None
        if m:
            old_left = int(m.group(1)) if m.group(1) is not None else 1
            new_left = int(m.group(2)) if m.group(2) is not None else 1
            before, after = [], []
            i += 1
            while i < len(lines) and (old_left > 0 or new_left > 0):
                h = lines[i]
                if h.startswith("\\"):
                    i += 1; continue
                tag, body = h[0], h[1:]
                if tag == " ":
                    before.append(body); after.append(body); old_left -= 1; new_left -= 1
                elif tag == "-":
                    before.append(body); old_left -= 1
                elif tag == "+":
                    after.append(body); new_left -= 1
                else:
                    break
                i += 1
            cur[1].append(("".join(before), "".join(after)))
            continue
        i += 1
    return files


ARCHES = ("amd64", "aarch64")

# The complete simple-patch sequence pass1.kaem applies, in order. Each entry is
# (fragment, target_file, arches). Fragments with a tcc-aarch64-NN name are
# GENERATED from patches/*.patch above (backend fixes that have a real unified-diff
# counterpart usable by Spack); the rest are hand-written .before/.after pairs --
# small tcc-compat edits (file-open shim, HAVE_FLOAT guards, x86_64 SSE opcodes,
# the aarch64 inline-asm include) with no standalone upstream diff. Keep this list
# in lockstep with pass1.kaem; it drives both the apply-order verify and MANIFEST.
SIMPLE_PATCH_OPS = [
    ("remove-fileopen",               "tcctools.c",   ("amd64", "aarch64")),
    ("addback-fileopen",              "tcctools.c",   ("amd64", "aarch64")),
    ("tccpp-have-float-strtof",       "tccpp.c",      ("amd64", "aarch64")),
    ("tccpp-have-float-ldexp",        "tccpp.c",      ("amd64", "aarch64")),
    ("static-plt",                    "tccelf.c",     ("amd64",)),
    ("x86_64-mxcsr",                  "x86_64-asm.h", ("amd64",)),
    ("aarch64-asm-defs",              "tcc.h",        ("aarch64",)),
    ("aarch64-asm-include",           "libtcc.c",     ("aarch64",)),
    ("tcc-aarch64-02_arm64-gen.c_00", "arm64-gen.c",  ("aarch64",)),
    ("tcc-aarch64-02_arm64-gen.c_01", "arm64-gen.c",  ("aarch64",)),
    ("tcc-aarch64-02_arm64-gen.c_02", "arm64-gen.c",  ("aarch64",)),
    ("tcc-aarch64-03_arm64-gen.c_00", "arm64-gen.c",  ("aarch64",)),
    ("tcc-aarch64-03_arm64-gen.c_01", "arm64-gen.c",  ("aarch64",)),
    ("tcc-aarch64-04_tccpp.c_00",     "tccpp.c",      ("aarch64",)),
]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: regen.py <pristine-tcc-srcdir>")
    tcc = sys.argv[1]
    os.makedirs(SPDIR, exist_ok=True)

    # 1. Generate the backend fragments from the canonical unified diffs.
    fragments = []  # (fid, target, before, after)
    for name in PATCHSET:
        num = NUM_RE.match(name).group(1)
        text = open(os.path.join(PATCHES, name), encoding="utf-8").read()
        for oldp, hunks in parse_patch(text):
            for hi, (before, after) in enumerate(hunks):
                fid = "%s_%s_%02d" % (num, oldp.replace("/", "_"), hi)
                fragments.append((fid, oldp, before, after))
    for fid, target, before, after in fragments:
        open(os.path.join(SPDIR, fid + ".before"), "w", encoding="utf-8").write(before)
        open(os.path.join(SPDIR, fid + ".after"), "w", encoding="utf-8").write(after)
    print("wrote %d generated fragment pairs from %d patch(es)" % (len(fragments), len(PATCHSET)))
    for fid, target, _, _ in fragments:
        print("  %s  ->  %s" % (fid, target))

    failures = 0

    # 2. Backend byte-equivalence: simple-patch result == GNU patch result.
    ref = tempfile.mkdtemp()
    shutil.copytree(tcc, os.path.join(ref, "t"))
    reft = os.path.join(ref, "t")
    for name in PATCHSET:
        subprocess.run(["patch", "-p1", "--no-backup-if-mismatch", "-i",
                        os.path.join(PATCHES, name)],
                       cwd=reft, check=True, stdout=subprocess.DEVNULL)
    from collections import OrderedDict
    byfile = OrderedDict()
    for fid, target, before, after in fragments:
        byfile.setdefault(target, []).append((before, after))
    for target, frags in byfile.items():
        buf = open(os.path.join(tcc, target), encoding="utf-8").read()
        for before, after in frags:
            idx = buf.find(before)
            if idx < 0:
                print("  FAIL %s: before not found" % target); failures += 1; break
            buf = buf[:idx] + after + buf[idx + len(before):]
        want = open(os.path.join(reft, target), encoding="utf-8").read()
        if buf != want:
            print("  FAIL %s: simple-patch != patch" % target); failures += 1
        else:
            print("  ok   patch-equiv %s (%d hunk(s))" % (target, len(frags)))
    shutil.rmtree(ref)

    # 3. Full apply-order verify: replay the entire per-arch simple-patch chain
    #    (every fragment, generated or hand-written) against fresh pristine source,
    #    exactly as pass1.kaem does -- each .before must match its target's current
    #    bytes. This is the only check the hand-written fragments get, so it must
    #    cover them; it also catches a fragment that drifts out of order.
    for arch in ARCHES:
        bufs = {}
        ok = True
        for frag, target, arches in SIMPLE_PATCH_OPS:
            if arch not in arches:
                continue
            before = open(os.path.join(SPDIR, frag + ".before"), encoding="utf-8").read()
            after = open(os.path.join(SPDIR, frag + ".after"), encoding="utf-8").read()
            if target not in bufs:
                bufs[target] = open(os.path.join(tcc, target), encoding="utf-8").read()
            idx = bufs[target].find(before)
            if idx < 0:
                print("  FAIL %s/%s: before not found in %s" % (arch, frag, target))
                failures += 1; ok = False; continue
            bufs[target] = bufs[target][:idx] + after + bufs[target][idx + len(before):]
        if ok:
            n = sum(1 for _, _, a in SIMPLE_PATCH_OPS if arch in a)
            print("  ok   apply-order %-7s (%d fragment(s))" % (arch, n))

    # 4. Emit the MANIFESTs (one complete per-arch set; common fragments in both),
    #    mirroring shpack/bootstrap/musl-1.1.24/simple-patches/MANIFEST{,.aarch64}.
    for arch in ARCHES:
        name = "MANIFEST" if arch == "amd64" else "MANIFEST." + arch
        with open(os.path.join(SPDIR, name), "w", encoding="utf-8") as f:
            for frag, target, arches in SIMPLE_PATCH_OPS:
                if arch in arches:
                    f.write("%s %s\n" % (frag, target))
        print("  wrote %s" % name)

    if failures:
        sys.exit("VERIFY FAILED: %d check(s)" % failures)
    print("verify OK")


if __name__ == "__main__":
    main()
