"""Exercise packaging failure paths without compiling, mounting, or launching apps."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


REPOSITORY = Path(__file__).resolve().parents[2]
MOCK = r'''#!/usr/bin/env python3
import json, os
from pathlib import Path
import shutil, sys

command = Path(sys.argv[0]).name
arguments = sys.argv[1:]
failure = os.environ.get("PACKAGING_TEST_FAILURE")

def copy(source, target):
    if source.is_dir():
        shutil.copytree(source, target, symlinks=True, dirs_exist_ok=True)
    else:
        shutil.copy2(source, target)

if command in ("package_app.sh", "package_installer.sh"):
    if failure == "build":
        sys.exit(1)
    app = Path(os.environ["CODEX_ISLAND_APP_DIR"] if command == "package_app.sh" else arguments[0])
    executable = app / "Contents/MacOS" / ("Codex Island" if command == "package_app.sh" else "Install Codex Island")
    executable.parent.mkdir(parents=True)
    executable.write_text("#!/bin/sh\nexit 0\n")
    executable.chmod(0o755)
elif command == "hdiutil":
    if arguments[0] == "create":
        Path(arguments[-1]).write_text(json.dumps({"source": arguments[arguments.index("-srcfolder") + 1]}))
    elif arguments[0] == "convert":
        shutil.copyfile(arguments[1], arguments[arguments.index("-o") + 1])
    elif arguments[0] == "attach":
        mount = Path(arguments[arguments.index("-mountpoint") + 1])
        copy(Path(json.loads(Path(arguments[-1]).read_text())["source"]), mount)
    elif arguments[0] == "detach":
        mount = Path(arguments[1])
        shutil.rmtree(mount)
        mount.mkdir()
elif command == "ditto":
    source, target = map(Path, arguments)
    if failure == "publish" and source.name == "Codex-Island.dmg":
        target.write_text("incomplete copy")
        sys.exit(1)
    copy(source, target)
elif command == "mv":
    source, target = map(Path, arguments[-2:])
    if failure == "publish":
        # Model mv's cross-volume fallback: truncating the destination before a
        # failed copy. Publication must not depend on /tmp sharing dist's volume.
        target.write_text("incomplete copy")
        sys.exit(1)
    shutil.move(str(source), str(target))
'''


def check(name, *, failure=None, final_directory=False, symlink_dist=False):
    with tempfile.TemporaryDirectory(prefix="codex-island-packaging-check-") as temporary:
        root = Path(temporary).resolve()
        scripts = root / "scripts"
        scripts.mkdir()
        shutil.copy2(REPOSITORY / "scripts/package_dmg.sh", scripts / "package_dmg.sh")
        binary = root / "bin"
        binary.mkdir()
        for command in ["package_app.sh", "package_installer.sh", "hdiutil", "ditto", "mv",
                        "SetFile", "sips", "DeRez", "Rez", "codesign", "sync"]:
            target = (scripts if command.endswith(".sh") else binary) / command
            target.write_text(MOCK)
            target.chmod(0o755)
        packaging = root / "Packaging"
        packaging.mkdir()
        (packaging / "CodexIslandDMG.icns").write_bytes(b"fixture icon")
        dist = root / "dist"
        if symlink_dist:
            outside = root / "outside"
            outside.mkdir()
            dist.symlink_to(outside, target_is_directory=True)
        else:
            dist.mkdir()
        final = dist / "Codex-Island.dmg"
        if final_directory:
            final.mkdir()
            previous = final / "previous.txt"
        else:
            previous = final
        previous.write_bytes(b"previous verified artifact")
        (dist / "older.dmg").write_bytes(b"older artifact")
        (dist / "stale-build").mkdir()
        environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"])
        if failure:
            environment["PACKAGING_TEST_FAILURE"] = failure
        result = subprocess.run([str(scripts / "package_dmg.sh")], env=environment,
                                capture_output=True, text=True, timeout=30)
        if failure or final_directory or symlink_dist:
            assert result.returncode != 0, f"{name}: expected failure\n{result.stdout}\n{result.stderr}"
            assert previous.read_bytes() == b"previous verified artifact", f"{name}: previous artifact was damaged"
            assert (dist / "stale-build").is_dir(), f"{name}: failed packaging cleaned unrelated outputs"
        else:
            assert result.returncode == 0, f"{name}: {result.stdout}\n{result.stderr}"
            assert final.is_file() and final.read_bytes() != b"previous verified artifact"
            assert not (dist / "stale-build").exists(), "successful packaging cleans stale non-DMG outputs"
            assert result.stdout.strip() == str(final), f"successful packaging reports the final DMG: {result.stdout!r}"
        assert (dist / "older.dmg").read_bytes() == b"older artifact", f"{name}: older DMG was changed"
        assert not list(dist.glob(".codex-island-publish.*")), f"{name}: publication staging was not cleaned"
        print(f"PASS {name}", flush=True)


check("build failure preserves previous artifact", failure="build")
check("publish failure preserves previous artifact across volumes", failure="publish")
check("a directory at the final DMG path is preserved", final_directory=True)
check("symlinked output directory is refused", symlink_dist=True)
check("verified artifact replaces previous output")
print("All 5 packaging checks passed")
