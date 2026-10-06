#!/usr/bin/env python3
"""Build a local Free app bundle. Does not install or launch it."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
identity = os.environ.get("SIGNING_IDENTITY", "-")
subprocess.run(["swift", "build", "-c", "release"], cwd=root, check=True)
bin_path = Path(subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path"], cwd=root, text=True).strip())
app = root / "build/Ordinary Notch Free.app"
if app.exists():
    shutil.rmtree(app)
contents = app / "Contents"
macos = contents / "MacOS"
macos.mkdir(parents=True)
resources = contents / "Resources"
shutil.copytree(root / "Resources", resources)
shutil.move(str(resources / "Info.plist"), contents / "Info.plist")
for name in ("OrdinaryNotch", "OrdinaryActivityBridge"):
    shutil.copy2(bin_path / name, macos / name)
subprocess.run([sys.executable, str(root / "scripts/build-media-adapter.py"), str(resources)], check=True)
options = ["--options", "runtime", "--timestamp"] if identity != "-" else []
for target in [macos / "OrdinaryActivityBridge", app]:
    subprocess.run(["codesign", "--force", "--sign", identity, *options, str(target)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(app)
