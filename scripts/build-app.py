#!/usr/bin/env python3
"""Build a local Free app bundle. Does not install or launch it."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
identity = os.environ.get("SIGNING_IDENTITY", "-")
scratch = Path(os.environ.get("ORDINARY_FREE_BUILD_DIR", str(root / ".build")))
flags = ["-c", "release", "--disable-sandbox", "--scratch-path", str(scratch)]
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
if "-Xclang-linker" in subprocess.check_output(["swiftc", "-help-hidden"], text=True):
    flags += ["-Xswiftc", "-Xclang-linker", "-Xswiftc", "-isysroot", "-Xswiftc", "-Xclang-linker", "-Xswiftc", sdk]
subprocess.run(["swift", "build", *flags], cwd=root, check=True)
bin_path = Path(subprocess.check_output(["swift", "build", *flags, "--show-bin-path"], cwd=root, text=True).strip())
app = Path(os.environ.get("ORDINARY_FREE_APP_OUTPUT", str(root / "build/Ordinary Notch Free.app")))
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
