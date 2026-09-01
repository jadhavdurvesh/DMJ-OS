# DMJ OS — build kit

A custom Linux distro based on Debian 12 (Bookworm), built with
`debootstrap` + `live-build`, featuring a custom animated "DMJ Cinematic"
boot splash. (The earlier Saudade AI CLI integration has been removed —
see "History" below.)

## Where to run this

- **GitHub Actions (recommended, no local machine needed)** — see the
  section below; this is the environment the project has actually been
  tested and debugged against.
- **A real Linux machine or Debian/Ubuntu VM** — needs network access
  and root. `debootstrap`/`lb build` won't run inside a locked-down
  sandbox or container without privileged mount access.

If you hit build errors running locally that aren't covered here, check
`docs/BUILD_TROUBLESHOOTING.md` and `docs/build-troubleshooting/BUILD_HISTORY.md`
first — several real `live-build` bugs (unsupported options, a broken
repository path, a missing `gettext` dependency) have already been
diagnosed and fixed there. Notably: the `live-build` package shipped by
Ubuntu 24.04's apt repos was too old/buggy for this build, so the CI
workflow builds `live-build` from source instead of using
`apt install live-build`. If you build locally and hit similar errors,
you may need to do the same (see `.github/workflows/build-iso.yml` for
the exact steps).

## 1. Install prerequisites (local build only)

```bash
sudo apt update
sudo apt install debootstrap live-build
```

If this version of `live-build` throws `unrecognized option` errors or
404s on `Contents-amd64.gz`, build it from source instead — see the
"Install current Debian Live build tools" step in
`.github/workflows/build-iso.yml`.

## 2. Configure (optional)

Open `build/build-dmj-os.sh` and adjust the top `CONFIG` block:
- `VERSION_CODENAME` — release name (kept separate from "DMJ OS" the product name)
- `VERSION_NUMBER`
- `BASE_SUITE` — Debian release to base on (default: bookworm)
- `INCLUDE_PLYMOUTH_THEME` — default `true`, the custom boot splash
- `INCLUDE_MACOS_THEME` — default `false`, an optional macOS-style desktop (see below)

## 3. Build

```bash
cd DMJ-OS
sudo ./build/build-dmj-os.sh
```

Or with the optional macOS-style desktop theme enabled:
```bash
sudo -E INCLUDE_MACOS_THEME=true ./build/build-dmj-os.sh
```

Takes anywhere from 15 minutes to over an hour depending on your
connection and machine. Output ISO lands in `out/`.

## 4. Test it

```bash
qemu-system-x86_64 -m 2048 -cdrom out/dmjos-1.0-ashen.iso
```

## What's included

- `build/build-dmj-os.sh` — main build script (debootstrap config, branding, Plymouth theme, live-build invocation)
- `config/plymouth/dmj-cinematic/` — the custom animated boot splash (wired in by default)
- `docs/` — a running log of real build issues hit in CI and how they were fixed

## Boot splash: "DMJ Cinematic"

A custom Plymouth "script" theme built around the real DMJ OS logo:
background fades in, the glowing logo scales/fades in (auto-scaled to
fit the screen regardless of boot resolution), ambient particles drift
upward in the background, and a thin progress bar fills in sync with
real boot progress.

Files:
- `dmj-cinematic.plymouth` — theme metadata
- `dmj-cinematic.script` — the animation itself (Plymouth's script language)
- `images/logo.png`, `images/logo_glow.png` — the real DMJ OS logo + glow variant
- `images/particle.png` — ambient particle sprite
- `images/progress_dot.png` — used (stretched) to build the progress bar
- `generate_assets.py` — a **dev-only fallback** for prototyping a
  placeholder text logo; the shipped `images/` are the real hand-designed
  assets, don't rerun this against them unless you mean to replace them

**To swap in a different logo:** replace `images/logo.png` and
`images/logo_glow.png` (same dimensions/aspect ideally) — the script
scales them to fit the screen automatically.

**To preview without a full ISO build**, on a Linux machine with Plymouth
installed:
```bash
sudo cp -r config/plymouth/dmj-cinematic /usr/share/plymouth/themes/
sudo plymouth-set-default-theme -R dmj-cinematic
sudo plymouthd --debug --no-daemon &
sudo plymouth --show-splash
```
Building the ISO and booting it in QEMU is the most reliable way to see
real boot timing, though.

To disable it entirely: `INCLUDE_PLYMOUTH_THEME=false ./build/build-dmj-os.sh`.

## Optional: macOS-style desktop theme

Off by default (`INCLUDE_MACOS_THEME=false`) since it adds a
network-dependent build step (cloning theme repos from GitHub during the
chroot build) on top of an already fragile live-build pipeline. Enable
with `INCLUDE_MACOS_THEME=true` to get:
- **WhiteSur GTK theme** — dark GTK theme styled after macOS
- **WhiteSur icon theme** + **WhiteSur cursors**
- **Plank** — an auto-hiding dock along the bottom of the screen

Applied by default to every new user via `/etc/skel`, so a fresh live
session boots straight into the themed desktop with the dock running.

## History

This project originally included a CLI AI assistant (`dmj-ai`) backed by
a custom Saudade model checkpoint. That integration has been fully
removed — no `config/dmj-ai/`, no model files, no related packages —
to keep the build lean and focused on the base OS + boot experience.

## Versioning note

"DMJ OS" is the fixed product name. `VERSION_CODENAME` in the build
script is the separate release name — currently set to "Ashen".

## Building in the cloud (GitHub Actions)

`.github/workflows/build-iso.yml` runs the entire build on GitHub's own
servers and uploads the finished ISO as a downloadable artifact — no
local machine needed. It builds `live-build` from source (see
`docs/build-troubleshooting/BUILD_HISTORY.md` for why) rather than
relying on the distro-packaged version.

**Running it:**
- Repo's **Actions** tab → **Build DMJ OS ISO** → **Run workflow** (lets you set a release codename)
- Or push a change under `build/`, `config/`, or the workflow file to `main` — triggers automatically
- Takes roughly 30–90 minutes
- When it finishes: open the run → **Artifacts** → download the ISO
