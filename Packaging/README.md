# DMG installer

Build the app, then package it on a Mac:

```sh
bash Source/build.sh
python3 -m venv .packaging-venv
.packaging-venv/bin/pip install -r Packaging/requirements.txt
.packaging-venv/bin/python Packaging/build_dmg.py --output dist/Terminal-First-1.2.dmg
```

Or run **Actions → Build Mac installer → Run workflow** on GitHub and download the installer artifact. The workflow runs only on manual dispatch and does not publish a release.

The DMG includes a custom app icon, a navy and mint Finder background, an Applications shortcut, and first-open instructions. Its app is signed locally after adding its icon. It remains unnotarized: recipients may need Privacy & Security → Open Anyway. Packaging requires access to macOS disk-image services, which may be unavailable in a sandbox.

The workflow verifies the disk image, app signature, both CPU architectures, Applications shortcut, and Finder layout metadata. Signing/notarization credentials are not used or stored. The resulting DMG can be shared directly; recipients do not need Python or any build tools.
