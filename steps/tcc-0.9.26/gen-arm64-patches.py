#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# gen-arm64-patches.py -- derive the in-chroot `simple-patch` fragments for the
# arm64 tcc backend fixes (patches/tcc-arm64-0{2,3,4}-*.patch) and verify each
# reproduces GNU patch's result byte-for-byte against the pristine tcc source.
#
# The chroot has no GNU patch, so tcc source edits are applied with `simple-patch
# FILE before after` (replaces the FIRST exact byte-match of `before`). Each hunk
# becomes one fragment pair  simple-patches/<patch>_<file>_<hunk>.{before,after}.
#
# Usage: gen-arm64-patches.py <pristine-tcc-srcdir>
#   (the unpacked tcc-0.9.26-1147-gee75a10c tree; e.g. from distfiles).

import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, "patches")
SPDIR = os.path.join(HERE, "simple-patches")
PATCHSET = ["tcc-arm64-02-codegen.patch",
            "tcc-arm64-03-varargs.patch",
            "tcc-arm64-04-long-double-suffix.patch",
            "tcc-arm64-05-aggregate-init.patch"]

HUNK_RE = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")
NUM_RE = re.compile(r"(tcc-arm64-\d+)")


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


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen-arm64-patches.py <pristine-tcc-srcdir>")
    tcc = sys.argv[1]
    os.makedirs(SPDIR, exist_ok=True)

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
    print("wrote %d fragment pairs" % len(fragments))
    for fid, target, _, _ in fragments:
        print("  %s  ->  %s" % (fid, target))

    # verify: simple-patch result == GNU patch result, per target file
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
    failures = 0
    for target, frags in byfile.items():
        buf = open(os.path.join(tcc, target), encoding="utf-8").read()
        for before, after in frags:
            idx = buf.find(before)
            if idx < 0:
                print("  FAIL %s: before not found" % target); failures += 1; break
            if buf.find(before, idx + 1) != -1 and before.count("\n") < 3:
                print("  WARN %s: before-fragment not unique" % target)
            buf = buf[:idx] + after + buf[idx + len(before):]
        want = open(os.path.join(reft, target), encoding="utf-8").read()
        if buf != want:
            print("  FAIL %s: simple-patch != patch" % target); failures += 1
        else:
            print("  ok   %s (%d hunk(s))" % (target, len(frags)))
    shutil.rmtree(ref)
    if failures:
        sys.exit("VERIFY FAILED: %d file(s)" % failures)
    print("verify OK")


if __name__ == "__main__":
    main()
