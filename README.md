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
- `INCLUDE_MACOS_THEME` — default `false`, macOS-style dock/theme (see "Deluxe build" below)
- `INCLUDE_WALLPAPER` — default `false`, matching default desktop wallpaper
- `INCLUDE_WELCOME_SCREEN` — default `false`, one-time first-login welcome dialog
- `INCLUDE_DESKTOP_APPS` — default `false`, Firefox + VLC + an archive manager

## 3. Build

Base (minimal, most reliable) build:
```bash
cd DMJ-OS
sudo ./build/build-dmj-os.sh
```

Deluxe build (macOS-style theme + wallpaper + welcome screen + desktop apps):
```bash
sudo -E env \
  INCLUDE_MACOS_THEME=true \
  INCLUDE_WALLPAPER=true \
  INCLUDE_WELCOME_SCREEN=true \
  INCLUDE_DESKTOP_APPS=true \
  ./build/build-dmj-os.sh
```

Takes anywhere from 15 minutes (base) to well over an hour (deluxe, since
it also clones and builds GTK themes and installs a browser) depending on
your connection and machine. Output ISO lands in `out/`, named with a
`-macos` suffix for deluxe builds so it never overwrites a base build.

## 4. Test it

Interactively, with a display:
```bash
qemu-system-x86_64 -m 2048 -cdrom out/dmjos-1.0-ashen.iso
# or, for a deluxe build:
qemu-system-x86_64 -m 2048 -cdrom out/dmjos-1.0-ashen-macos.iso
```

Headlessly (no display needed — see "Automated boot preview" below):
```bash
pip install --break-system-packages pillow
python3 tools/qemu-preview/capture_boot_screenshots.py out/dmjos-1.0-ashen.iso screenshots/
```

## Automated boot preview (no local machine, no display)

There's no realistic "paste your ISO into a website and watch it boot"
tool for a multi-GB custom Debian live image — the browser-based x86
emulators (copy.sh, v86, etc.) are built for tiny DOS/toy Linux images and
won't handle this. Instead, every GitHub Actions run boots the ISO
headlessly in QEMU right after building it and takes screenshots at a few
points during boot — proof the Plymouth splash is actually rendering,
with zero local setup.

After a workflow run finishes: **Artifacts** → download the
`*-boot-screenshots` artifact → a handful of PNGs showing the boot at
different timestamps. This step never fails the overall build (it's
`continue-on-error`) — if it has trouble, the ISO artifact is still there
as the source of truth.

The same script (`tools/qemu-preview/capture_boot_screenshots.py`) runs
identically on a local Linux machine with QEMU + Pillow installed — see
above.

For genuinely *interactive* live viewing (clicking around the actual
desktop from a browser, not just static screenshots), that needs a VNC
setup — not built here, but doable via a temporary cloud VM or GitHub
Codespaces running QEMU with a noVNC web viewer, if you want that next.

## What's included

- `build/build-dmj-os.sh` — main build script (debootstrap config, branding, Plymouth theme, live-build invocation)
- `config/plymouth/dmj-cinematic/` — the custom animated boot splash (wired in by default)
- `config/wallpaper/` — the deluxe build's default desktop wallpaper + generator script
- `config/welcome/` — the deluxe build's first-boot welcome dialog script
- `tools/qemu-preview/` — headless boot screenshot capture (see "Automated boot preview" above)
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
scales them to fit the screen automatically. If you also use the deluxe
wallpaper, rerun `python3 config/wallpaper/generate_wallpaper.py`
afterward so the wallpaper watermark matches.

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

## Deluxe build: macOS-style theme, wallpaper, welcome screen, desktop apps

All off by default in a plain `./build/build-dmj-os.sh` run, since together
they add real build time and a network-dependent theme-cloning step on top
of an already-tuned live-build pipeline. Enable them individually, or all
at once via the GitHub Actions `variant: macos-deluxe` option (see below).

- **`INCLUDE_MACOS_THEME=true`** — WhiteSur GTK theme (dark, macOS-styled), WhiteSur icons + cursors, and Plank as an auto-hiding dock along the bottom of the screen
- **`INCLUDE_WALLPAPER=true`** — the generated `config/wallpaper/wallpaper.png` (same dark gradient + glow language as the boot splash, with a small logo watermark) set as the default XFCE background
- **`INCLUDE_WELCOME_SCREEN=true`** — a one-time `zenity` dialog on first login (tracked via a marker file so it never shows twice), briefly orienting a new user to the dock and preinstalled apps
- **`INCLUDE_DESKTOP_APPS=true`** — Firefox ESR, VLC, and an archive manager (`xarchiver`) preinstalled

All of the above are applied via `/etc/skel`, so a fresh live session boots
straight into the fully configured desktop with no manual setup.

## History

This project originally included a CLI AI assistant (`dmj-ai`) backed by
a custom Saudade model checkpoint. That integration has been fully
removed — no `config/dmj-ai/`, no model files, no related packages —
to keep the build lean and focused on the base OS + boot experience.

## Versioning note

"DMJ OS" is the fixed product name. `VERSION_CODENAME` in the build
script is the separate release name — currently set to "Ashen".
The base build is tagged `v1.0.0` in this repo; the deluxe build shares
the same OS version (1.0) with a `-macos` suffix on the ISO filename,
since it's an edition, not a separate release line.

## Building in the cloud (GitHub Actions)

`.github/workflows/build-iso.yml` runs the entire build on GitHub's own
servers and uploads the finished ISO as a downloadable artifact — no
local machine needed. It builds `live-build` from source (see
`docs/build-troubleshooting/BUILD_HISTORY.md` for why) rather than
relying on the distro-packaged version.

**Running it:**
- Repo's **Actions** tab → **Build DMJ OS ISO** → **Run workflow**
  — set a release codename, and pick **variant**: `base` (default,
  fastest, most reliable) or `macos-deluxe` (theme + wallpaper +
  welcome screen + desktop apps)
- Or push a change under `build/`, `config/`, or the workflow file to
  `main` — triggers automatically, always as the `base` variant
- Base takes roughly 30–90 minutes; deluxe takes longer (extra package
  installs + theme cloning)
- When it finishes: open the run → **Artifacts** → download the ISO
  (named with a `-macos` suffix for deluxe runs)
