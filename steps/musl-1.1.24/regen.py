#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# regen.py -- derive the in-chroot `simple-patch` fragments from the canonical
# unified diffs in patches/, and verify each fragment reproduces GNU patch's
# result byte-for-byte.
#
# Why two representations:
#   - patches/*.patch     unified diffs; used where a real `patch` exists (Spack).
#   - simple-patches/*.{before,after}  one fragment pair per hunk; applied in the
#     kaem chain by the repo's `simple-patch` tool (no `patch` in the chroot).
#     `simple-patch FILE before after` replaces the FIRST exact byte-match of
#     `before` with `after`, erroring if absent -- so each fragment carries the
#     hunk's context lines to be a unique anchor.
#
# Per-arch: this repo bootstraps musl for both x86_64 and aarch64 from the SAME
# pristine tarball. The patch set is partitioned by filename:
#   - shared   (0006...)        apply to both arches
#   - x86_64   (0002/0030/0040) the SysV-AMD64 va_list + x86 syscall asm
#   - aarch64  (aarch64-0N...)  the AAPCS64 va_list + asm->C rewrites
# Fragments for both arches coexist in the one simple-patches/ dir (their ids are
# prefixed by the patch number, which is arch-unique), so a regen of one arch
# leaves the other arch's fragments untouched.
#
# Some hunks are deliberately NOT turned into fragments:
#   - arch/<arch>/bits/alltypes.h.in: the chroot uses the pre-generated
#     generated[/<arch>]/bits/alltypes.h (already in the __musl_va_list_t form),
#     so the .h.in edit is moot in-chroot.
#   - new files created from /dev/null: shipped as plain sources under newsrc/
#     and copied into the tree (x86_64: a single va_list.c, inline in pass1.kaem;
#     aarch64: the asm->C .c files, via the generated copy-newsrc.aarch64.kaem).
#   - file deletions (+++ /dev/null): the asm->C patch deletes every aarch64 .s
#     and adds a .c in its place; the .s is simply never compiled, so there is
#     nothing to patch.
#
# Usage: regen.py <arch> <pristine-musl-srcdir> [full.files]
#   arch in {x86_64, aarch64}. (re)writes the fragments/newsrc/kaem for that
#   arch under steps/musl-1.1.24/, then verifies.

import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, "patches")
SPDIR = os.path.join(HERE, "simple-patches")
NEWSRC = os.path.join(HERE, "newsrc")

# ---- per-arch configuration -------------------------------------------------
# suffix         appended to the generated kaem/manifest names ("" = x86_64).
# arch_dir       musl's arch/<arch_dir> include directory.
# subset_files   the hand-maintained tcc-surface file list for the SUBSET libc.
# skip_files     hunks we do NOT turn into fragments (handled another way).
# subset_targets the patched files a SUBSET source #includes/compiles, so their
#                fragments must be applied before the subset build (everything
#                else -- full-only sources, deletions -- is FULL-only).
ARCH_CFG = {
    "x86_64": {
        "suffix": "",
        "arch_dir": "x86_64",
        "subset_files": "musl-subset.files",
        "skip_files": {"arch/x86_64/bits/alltypes.h.in"},
        "subset_targets": {
            "src/internal/syscall.h",      # 0006 (the only 0006 hunk a subset file pulls in)
            "arch/x86_64/syscall_arch.h",  # 0030
            "include/stdarg.h",            # 0040
        },
    },
    "aarch64": {
        "suffix": ".aarch64",
        "arch_dir": "aarch64",
        "subset_files": "musl-subset.aarch64.files",
        "skip_files": {"arch/aarch64/bits/alltypes.h.in"},
        "subset_targets": {
            "src/internal/syscall.h",        # 0006
            "include/stdarg.h",              # aarch64-01 (va_* -> tcc builtins)
            "arch/aarch64/syscall_arch.h",   # aarch64-02 (extern __syscallN decls)
            "arch/aarch64/atomic_arch.h",    # aarch64-02 (LL/SC asm -> single-thread C)
            "arch/aarch64/crt_arch.h",       # aarch64-02 (_start asm -> C, used by crt1.c)
            "arch/aarch64/pthread_arch.h",   # aarch64-02 (mrs tpidr_el0 -> out-of-line)
        },
    },
}

# Glue compiled into the SUBSET libc only (HAVE_FLOAT=0 / TLS-free crutches);
# arch-neutral (errno is a plain global, start.c is portable envp math, etc.).
SUBSET_GLUE = ["glue/errno_loc.c", "glue/start.c", "glue/sigaction.c", "glue/float.c"]
CFLAGS = "-std=c99 -ffreestanding -D_XOPEN_SOURCE=700 -D SYSCALL_NO_TLS"


def iinc(arch_dir):
    # Include flags used to compile every musl object. The consumer side uses a
    # different, public-only set (see steps/tcc-0.9.26/pass1.kaem).
    return ("-nostdinc -I obj/include -I arch/%s -I arch/generic "
            "-I obj/src/internal -I src/include -I src/internal -I include"
            % arch_dir)


HUNK_RE = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")
NUM_RE = re.compile(r"(aarch64-\d+|tcc-arm64-\d+|\d+)")


def patch_arch(name):
    """Which arch a patch filename belongs to: 'shared', 'x86_64' or 'aarch64'."""
    if name.startswith("aarch64-"):
        return "aarch64"
    num = NUM_RE.match(name)
    if num and num.group(1) == "0006":
        return "shared"
    return "x86_64"


def select_patches(arch):
    return [n for n in sorted(os.listdir(PATCHES))
            if n.endswith(".patch") and patch_arch(n) in ("shared", arch)]


def parse_patch(text):
    """Yield (oldpath, newpath, [hunks]) where each hunk is (before, after).

    before/after are the exact original/patched byte spans for that hunk
    (context + removed -> before; context + added -> after). oldpath == /dev/null
    is a new file (before == hunk's after); newpath == /dev/null is a deletion.
    Leading prose / git headers between file sections are skipped.
    """
    files = []
    cur = None
    lines = text.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("--- ") and i + 1 < len(lines) \
                and lines[i + 1].startswith("+++ "):
            oldp = line[4:].split("\t")[0].strip()
            newp = lines[i + 1][4:].split("\t")[0].strip()
            oldp = oldp[2:] if oldp.startswith(("a/", "b/")) else oldp
            newp = newp[2:] if newp.startswith(("a/", "b/")) else newp
            cur = (oldp, newp, [])
            files.append(cur)
            i += 2
            continue
        m = HUNK_RE.match(line) if cur is not None else None
        if m:
            # Respect the @@ line counts: a hunk consumes exactly old_count
            # (context+removed) and new_count (context+added) lines. Reading
            # past that would slurp the git "-- \n<version>" signature trailer.
            old_left = int(m.group(1)) if m.group(1) is not None else 1
            new_left = int(m.group(2)) if m.group(2) is not None else 1
            before, after = [], []
            i += 1
            while i < len(lines) and (old_left > 0 or new_left > 0):
                h = lines[i]
                if h.startswith("\\"):  # "\ No newline at end of file"
                    i += 1
                    continue
                tag, body = h[0], h[1:]
                if tag == " ":
                    before.append(body); after.append(body)
                    old_left -= 1; new_left -= 1
                elif tag == "-":
                    before.append(body); old_left -= 1
                elif tag == "+":
                    after.append(body); new_left -= 1
                else:
                    break
                i += 1
            cur[2].append(("".join(before), "".join(after)))
            continue
        i += 1
    return files


def objname(f):
    return f.replace("/", "_").rsplit(".", 1)[0] + ".o"


def emit_apply(path, frags, header):
    """Write a kaem fragment of `simple-patch` calls (cwd = musl root; ${SP} =
    the simple-patches dir, set by the caller)."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("# %s\n# Generated by regen.py -- do not edit. Needs env: SP.\n" % header)
        for fid, target, _, _ in frags:
            f.write("simple-patch %s ${SP}/%s.before ${SP}/%s.after\n"
                    % (target, fid, fid))


def emit_build_libc(path, srcs, header, arch_dir):
    """Write a kaem fragment compiling `srcs` into ${LIBDIR}/libc.a with ${CC}
    (cwd = musl root; needs env CC, O, LIBDIR)."""
    inc = iinc(arch_dir)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# %s\n# Generated by regen.py -- do not edit. Needs env: CC, O, LIBDIR.\n"
                % header)
        objs = []
        for s in srcs:
            o = objname(s)
            f.write("${CC} -c %s %s %s -o ${O}/%s\n" % (inc, CFLAGS, s, o))
            objs.append("${O}/" + o)
        f.write("${CC} -ar cr ${LIBDIR}/libc.a" + "".join(" " + o for o in objs) + "\n")


def emit_copy_newsrc(path, newfiles, header):
    """Write a kaem fragment that mkdir+cp's the asm->C new sources into the musl
    tree (cwd = musl root; needs env MSRC). Used on aarch64, where the asm->C
    patch adds many .c files at nested paths (kaem has no globbing / cp -r)."""
    seen = []
    with open(path, "w", encoding="utf-8") as f:
        f.write("# %s\n# Generated by regen.py -- do not edit. Needs env: MSRC.\n" % header)
        for rel, _ in newfiles:
            d = os.path.dirname(rel)
            if d and d not in seen:
                f.write("mkdir -p %s\n" % d)
                seen.append(d)
            f.write("cp ${MSRC}/newsrc/%s %s\n" % (rel, rel))


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: regen.py <arch> <pristine-musl-srcdir> [full.files]")
    arch = sys.argv[1]
    if arch not in ARCH_CFG:
        sys.exit("unknown arch %r (want one of %s)" % (arch, ", ".join(ARCH_CFG)))
    cfg = ARCH_CFG[arch]
    musl = sys.argv[2]
    full_files = None
    if len(sys.argv) == 4:
        full_files = [l.strip() for l in open(sys.argv[3], encoding="utf-8")
                      if l.strip()]

    sfx = cfg["suffix"]
    arch_dir = cfg["arch_dir"]
    skip_files = cfg["skip_files"]
    subset_targets = cfg["subset_targets"]
    patchset = select_patches(arch)

    os.makedirs(SPDIR, exist_ok=True)
    os.makedirs(NEWSRC, exist_ok=True)

    # id -> (target_path_in_tree, before, after); ordered for in-file order.
    fragments = []
    newfiles = []  # (path_in_tree, content)

    for patchname in patchset:
        num = NUM_RE.match(patchname).group(1)
        text = open(os.path.join(PATCHES, patchname), encoding="utf-8").read()
        for oldp, newp, hunks in parse_patch(text):
            if newp == "/dev/null":
                continue                       # deletion: the .s is never compiled
            if oldp == "/dev/null":
                newfiles.append((newp, hunks[0][1]))  # new file: all '+' lines
                continue
            if oldp in skip_files:
                continue
            for hi, (before, after) in enumerate(hunks):
                fid = "%s_%s_%02d" % (num, oldp.replace("/", "_"), hi)
                fragments.append((fid, oldp, before, after))

    # Remove this arch's stale fragments (by id), then write fresh; leaves the
    # other arch's fragments (different patch-number prefixes) in place.
    for fid, _, _, _ in fragments:
        for ext in (".before", ".after"):
            p = os.path.join(SPDIR, fid + ext)
            if os.path.exists(p):
                os.remove(p)
    for fid, target, before, after in fragments:
        open(os.path.join(SPDIR, fid + ".before"), "w", encoding="utf-8").write(before)
        open(os.path.join(SPDIR, fid + ".after"), "w", encoding="utf-8").write(after)
    for path, content in newfiles:
        dst = os.path.join(NEWSRC, path)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, "w", encoding="utf-8").write(content)

    # write a manifest: fid <space> target
    with open(os.path.join(SPDIR, "MANIFEST" + sfx), "w", encoding="utf-8") as f:
        for fid, target, _, _ in fragments:
            f.write("%s %s\n" % (fid, target))

    print("[%s] wrote %d fragment pairs, %d new files" % (arch, len(fragments), len(newfiles)))

    # ---- emit the kaem fragments ----
    subset_frags = [fr for fr in fragments if fr[1] in subset_targets]
    emit_apply(os.path.join(HERE, "apply-subset%s.kaem" % sfx), subset_frags,
               "Apply the tcc-compat musl patches needed for the SUBSET libc.")
    emit_apply(os.path.join(HERE, "apply-full%s.kaem" % sfx), fragments,
               "Apply the tcc-compat musl patches needed for the FULL libc.")

    subset_files = [l.strip() for l in
                    open(os.path.join(HERE, cfg["subset_files"]), encoding="utf-8")
                    if l.strip() and not l.lstrip().startswith("#")]
    emit_build_libc(os.path.join(HERE, "build-libc-subset%s.kaem" % sfx),
                    subset_files + SUBSET_GLUE,
                    "Compile the musl 1.1.24 SUBSET (+glue) into libc.a.", arch_dir)

    if full_files is not None:
        emit_build_libc(os.path.join(HERE, "build-libc-full%s.kaem" % sfx), full_files,
                        "Compile FULL musl 1.1.24 (no glue) into libc.a.", arch_dir)

    # aarch64 ships its asm->C sources via a generated copy script (many nested
    # new files). x86_64's lone va_list.c is copied inline by pass1.kaem.
    if sfx and newfiles:
        emit_copy_newsrc(os.path.join(HERE, "copy-newsrc%s.kaem" % sfx), newfiles,
                         "Copy the aarch64 asm->C new sources into the musl tree.")

    print("[%s] emitted apply/build-libc%s kaem%s" %
          (arch, sfx, " + copy-newsrc" if (sfx and newfiles) else ""))

    # ---- verify: simple-patch(pristine_file) == patch(pristine_file) ----
    import tempfile
    ref = tempfile.mkdtemp()
    shutil.copytree(musl, os.path.join(ref, "m"))
    refm = os.path.join(ref, "m")
    for patchname in patchset:
        subprocess.run(["patch", "-p1", "--no-backup-if-mismatch", "-i",
                        os.path.join(PATCHES, patchname)],
                       cwd=refm, check=True, stdout=subprocess.DEVNULL)

    from collections import OrderedDict
    byfile = OrderedDict()
    for fid, target, before, after in fragments:
        byfile.setdefault(target, []).append((before, after))

    failures = 0
    for target, frags in byfile.items():
        orig = open(os.path.join(musl, target), encoding="utf-8").read()
        buf = orig
        for before, after in frags:
            idx = buf.find(before)
            if idx < 0:
                print("  FAIL %s: before-fragment not found" % target)
                failures += 1
                break
            buf = buf[:idx] + after + buf[idx + len(before):]
        if target in skip_files:
            continue
        refp = os.path.join(refm, target)
        want = open(refp, encoding="utf-8").read() if os.path.exists(refp) else orig
        if buf != want:
            print("  FAIL %s: simple-patch result != patch result" % target)
            failures += 1
        else:
            print("  ok   %s (%d hunk(s))" % (target, len(frags)))
    shutil.rmtree(ref)
    if failures:
        sys.exit("VERIFY FAILED: %d file(s)" % failures)
    print("[%s] verify OK" % arch)


if __name__ == "__main__":
    main()
