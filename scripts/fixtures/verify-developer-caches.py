#!/usr/bin/env python3
"""Generate, preserve, and regenerate disposable producer caches.

No current-user cache is read or changed. Every writable producer location is
explicitly placed under a new /private/tmp fixture. Cache files are preserved
with namespace moves; this harness never invokes a cache-cleaning command.
An optional Homebrew executable must belong to a disposable Homebrew checkout.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(path):
    return sorted(item for item in path.rglob("*") if item.is_file() and not item.is_symlink())


def run(arguments, cwd, environment=None):
    result = subprocess.run(arguments, cwd=cwd, env=environment, capture_output=True,
                            text=True, check=True, timeout=180)
    return (result.stdout + result.stderr).strip()


def npm_evidence(root, executable):
    work = root / "npm"
    work.mkdir()
    cache = root / "Home/.npm"
    cache.mkdir(parents=True)
    package = work / "racket-cache-evidence-1.0.0.tgz"
    metadata = json.dumps({"name": "racket-cache-evidence", "version": "1.0.0",
                           "main": "index.js"}, sort_keys=True).encode()
    payload = b"module.exports = 42;\n"
    with tarfile.open(package, "w:gz") as archive:
        for name, data in [("package/package.json", metadata), ("package/index.js", payload)]:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
    package_hash = digest(package)
    userconfig = work / "user.npmrc"
    globalconfig = work / "global.npmrc"
    userconfig.write_text("")
    globalconfig.write_text("")
    environment = os.environ.copy()
    environment.update({"npm_config_cache": str(cache), "npm_config_userconfig": str(userconfig),
                        "npm_config_globalconfig": str(globalconfig), "npm_config_update_notifier": "false"})
    common = [executable, "--cache", str(cache), "--userconfig", str(userconfig),
              "--globalconfig", str(globalconfig), "--offline", "--ignore-scripts",
              "--no-audit", "--no-fund", "--no-update-notifier"]

    def install(name):
        target = work / name
        target.mkdir()
        run(common + ["install", "--prefix", str(target), str(package)], work, environment)
        installed = target / "node_modules/racket-cache-evidence/index.js"
        assert installed.read_bytes() == payload
        return digest(installed)

    first = install("install-1")
    blobs = files(cache / "_cacache/content-v2")
    assert blobs, "npm did not create content-addressed cached data"
    missing_blob = blobs[0]
    blob_hash = digest(missing_blob)
    preserved = root / "preserved"
    preserved.mkdir(exist_ok=True)
    shutil.move(str(missing_blob), str(preserved / "npm-missing-content-blob"))
    second = install("install-2-missing-blob")
    assert missing_blob.exists() and digest(missing_blob) == blob_hash
    shutil.move(str(cache / "_cacache"), str(preserved / "npm-original-cacache"))
    third = install("install-3-empty-cache")
    verification = run(common + ["cache", "verify"], work, environment)
    assert files(cache / "_cacache/content-v2")
    assert first == second == third and digest(package) == package_hash
    return {"version": run([executable, "--version"], work, environment),
            "packageSHA256": package_hash, "installedPayloadSHA256": first,
            "missingBlobRefetched": True, "emptyCacheRegenerated": True,
            "cacheVerification": verification}


def clang_evidence(root, executable):
    work = root / "clang"
    work.mkdir()
    sources = work / "source"
    sources.mkdir()
    (sources / "evidence.h").write_text("static inline int evidence_value(void) { return 42; }\n")
    (sources / "module.modulemap").write_text('module RacketEvidence { header "evidence.h" export * }\n')
    (sources / "main.c").write_text('#include "evidence.h"\nint main(void) { return evidence_value() != 42; }\n')
    source_hashes = {file.name: digest(file) for file in files(sources)}
    cache = root / "Home/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"
    cache.parent.mkdir(parents=True)

    def compile_and_run(name):
        output = work / name
        run([executable, "-fmodules", "-fimplicit-module-maps", "-fmodules-cache-path=" + str(cache),
             "-I", str(sources), str(sources / "main.c"), "-o", str(output)], work)
        run([str(output)], work)
        modules = list(cache.rglob("*.pcm"))
        assert modules, "Clang did not generate a precompiled module"
        return digest(output), len(modules)

    first, count = compile_and_run("evidence-executable")
    shutil.move(str(work / "evidence-executable"), str(root / "preserved/clang-original-executable"))
    shutil.move(str(cache), str(root / "preserved/clang-original-module-cache"))
    second, regenerated_count = compile_and_run("evidence-executable")
    assert count == regenerated_count and first == second
    assert source_hashes == {file.name: digest(file) for file in files(sources)}
    return {"version": run([executable, "--version"], work).splitlines()[0],
            "sourceSHA256": source_hashes, "binarySHA256": first,
            "generatedModuleCount": count, "emptyCacheRegenerated": True,
            "executableBehaviorVerified": True}


def homebrew_evidence(root, executable):
    repository = Path(executable).resolve().parent.parent
    if not str(repository).startswith("/private/tmp/RACKET-"):
        raise ValueError("Homebrew must be a disposable /private/tmp/RACKET-* checkout")
    work = root / "homebrew"
    work.mkdir()
    cache = root / "Home/Library/Caches/Homebrew"
    cache.mkdir(parents=True)
    payload = work / "racket-cache-evidence-1.0.0.tar.gz"
    payload.write_bytes(b"RACKET disposable Homebrew download evidence\n")
    payload_hash = digest(payload)
    formula_directory = repository / "Library/Taps/racket/homebrew-evidence/Formula"
    formula_directory.mkdir(parents=True)
    formula = formula_directory / "racket-cache-evidence.rb"
    formula.write_text('class RacketCacheEvidence < Formula\n'
                       '  desc "Disposable RACKET cache evidence"\n'
                       '  homepage "https://github.com/iamcaglardogan/racket"\n'
                       f'  url "{payload.as_uri()}"\n'
                       '  version "1.0.0"\n'
                       f'  sha256 "{payload_hash}"\n'
                       'end\n')
    environment = os.environ.copy()
    temporary = work / "tmp"
    temporary.mkdir()
    environment.update({"HOMEBREW_CACHE": str(cache), "HOMEBREW_LOGS": str(work / "logs"),
                        "HOMEBREW_TEMP": str(temporary), "HOMEBREW_NO_ANALYTICS": "1",
                        "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_INSTALL_FROM_API": "1",
                        "HOMEBREW_NO_INSTALL_CLEANUP": "1", "HOMEBREW_NO_ENV_HINTS": "1"})
    command = [executable, "fetch", "--build-from-source", "--formula", "racket/evidence/racket-cache-evidence"]
    run(command, work, environment)
    downloads = files(cache / "downloads")
    matched = [file for file in downloads if digest(file) == payload_hash]
    assert len(matched) == 1, "Expected exactly one matching Homebrew download"
    downloaded = matched[0]
    shutil.move(str(downloaded), str(root / "preserved/homebrew-original-download"))
    run(command, work, environment)
    assert downloaded.exists() and digest(downloaded) == payload_hash
    assert digest(payload) == payload_hash
    return {"version": run([executable, "--version"], work, environment),
            "repositoryCommit": run(["git", "-C", str(repository), "rev-parse", "HEAD"], work),
            "downloadSHA256": payload_hash, "downloadRelativePath": str(downloaded.relative_to(cache)),
            "missingDownloadRegenerated": True, "installedAnyFormula": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--brew", help="Disposable Homebrew checkout's bin/brew, never an installed copy")
    arguments = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="RACKET-DeveloperCacheEvidence-", dir="/private/tmp"))
    (root / "preserved").mkdir()
    print("Evidence fixture: " + str(root), flush=True)
    npm = shutil.which("npm")
    clang = shutil.which("clang")
    if not npm or not clang:
        raise RuntimeError("npm and Clang are required; no category is silently skipped")
    evidence = {"fixture": str(root), "npm": npm_evidence(root, npm),
                "clang": clang_evidence(root, clang)}
    if arguments.brew:
        evidence["homebrew"] = homebrew_evidence(root, arguments.brew)
    output = root / "evidence.json"
    output.write_text(json.dumps(evidence, indent=2) + "\n")
    print(output.read_text(), flush=True)


if __name__ == "__main__":
    main()
