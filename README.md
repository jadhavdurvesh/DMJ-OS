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
python3 tools/qemu-preview/capture_boot_screenshots.py out/dmjos-1.0-ashen.iso boot-preview/ 240 3
# -> boot-preview/boot_video.mp4, plus boot-preview/milestone_*.png
```

## Automated boot preview (no local machine, no display)

There's no realistic "paste your ISO into a website and watch it boot"
tool for a multi-GB custom Debian live image — the browser-based x86
emulators (copy.sh, v86, etc.) are built for tiny DOS/toy Linux images and
won't handle this. Instead, every GitHub Actions run boots the ISO
headlessly in QEMU right after building it, presses Enter to get past the
GRUB menu (it waits indefinitely otherwise), samples the framebuffer every
few seconds for several minutes, and assembles those frames into an actual
**MP4 video** of the boot — plus a few named milestone stills — with zero
local setup.

After a workflow run finishes: **Artifacts** → download the
`*-boot-preview` artifact → `boot_video.mp4` (the real capture) and
`boot_video_boosted.mp4` (brightness/contrast pushed up — several of this
theme's own colors are intentionally very dark near-black gradients, which
is correct but can look like an empty black frame at a glance; the boosted
copy is a viewing aid only, never the source of truth). Same pairing for
the `milestone_*.png` / `milestone_*_boosted.png` stills.

**Known display-capture caveat:** the display device used for capture
(`-vga virtio`) was chosen after finding that the more common `-vga std`
gets stuck returning byte-identical stale frames for 30+ seconds during a
real Linux kernel's display mode transition — not a genuinely frozen boot,
just a capture-tooling limitation. The script now detects and logs this
("byte-identical to the previous N frames") if it ever recurs, so a future
run will say so directly in the log rather than requiring a manual pixel
diff to figure out. If you see that note in a run's log, treat that
stretch of the video with suspicion regardless of which device is in use.

This step never fails the overall build (it's `continue-on-error`) — if
it has trouble, the ISO artifact is still there as the source of truth.

The same script (`tools/qemu-preview/capture_boot_screenshots.py`) runs
identically on a local Linux machine with QEMU + Pillow + ffmpeg
installed — see above. Usage: `capture_boot_screenshots.py <iso>
<output-dir> [duration_s] [interval_s]`.

For genuinely *interactive* live viewing (clicking around the actual
desktop from a browser in real time, not a recording), that needs a VNC
setup — not built here, but doable via a temporary cloud VM or GitHub
Codespaces running QEMU with a noVNC web viewer, if you want that next.

## GRUB boot menu rebranding

`live-build`'s default GRUB menu shows "Debian GNU/Linux \<version\>
(\<codename\>)" — there's no reliable, version-agnostic way to override
that from the live-build config side (the exact template location differs
between live-build versions, and CI builds live-build from source, so
pinning to one version's internal paths is fragile). Instead,
`tools/iso-rebrand/rebrand_grub.sh` patches the text directly inside the
**finished ISO**: it finds every `grub.cfg` on the image, replaces
"Debian GNU/Linux" with "DMJ OS" (and the codename), and writes each file
back using `xorriso`'s `-boot_image any replay`, which explicitly
preserves the El Torito boot catalog (BIOS + UEFI boot images) unchanged.

This runs automatically as the last step of `build-dmj-os.sh` whenever
`INCLUDE_PLYMOUTH_THEME=true` (the default). Verified end-to-end —
including actually booting the patched ISO in QEMU to confirm it still
works — before being wired in. If it ever fails for any reason, it falls
back to copying the ISO through unbranded rather than breaking the build
(rebranding is cosmetic; it should never be why a build fails).

**Not yet done:** the yellow icon graphic shown in the GRUB menu itself
(separate from the text) isn't replaced yet — its exact filename inside
the ISO isn't known without seeing a real build. The rebrand script now
scans the patched `grub.cfg` for `background_image`/`set theme=`
references and logs them, so the next real CI log will show the actual
path, which is needed before that can be swapped for the DMJ OS mark too.

## System branding: menu icon + distributor logo

Beyond the boot splash and wallpaper watermark, the real logo mark (the
circular symbol, auto-cropped from `logo.png` — the wordmark text isn't
usable as a square icon) is installed system-wide:

- **`/usr/share/pixmaps/distributor-logo.png`** — the standard path many
  Linux "about this system" tools check for distro branding. Fixed path,
  placed directly at build time, no runtime discovery needed.
- **`/usr/share/icons/hicolor/*/apps/start-here.png`** at all standard
  sizes (16 through 256px) — the icon name most desktop environments,
  including XFCE's application menu button, fall back to for distro
  branding. This is how Ubuntu/Mint/etc. brand their start menu icon
  without per-app configuration.
- **The panel's whiskermenu button icon** specifically — XFCE assigns
  panel plugin IDs (e.g. `plugin-14`) per-install, not at a fixed path,
  so (same lesson as the wallpaper monitor-name bug) a build-time guess
  won't reliably match. `config/branding/dmj-set-menu-icon.sh` runs at
  login, discovers the real whiskermenu plugin ID via `xfconf-query`,
  and points its icon at the mark. Verified against a mock `xfconf-query`
  with realistic plugin IDs and mixed plugin types (systray, tasklist)
  before trusting it — confirmed it only touches the actual menu plugin.

Controlled by `INCLUDE_SYSTEM_BRANDING` (default `true` — this is basic
distro identity, not a deluxe extra, so it's on even in the base build).
Regenerate the icon set after changing the logo:
```bash
python3 config/branding/generate_icons.py
```

## What's included

- `build/build-dmj-os.sh` — main build script (debootstrap config, branding, Plymouth theme, live-build invocation)
- `config/plymouth/dmj-cinematic/` — the custom animated boot splash (wired in by default)
- `config/branding/` — system-wide logo/icon branding (menu icon, distributor logo) — see above
- `config/wallpaper/` — the deluxe build's default desktop wallpaper + generator script
- `config/welcome/` — the deluxe build's first-boot welcome dialog script
- `tools/qemu-preview/` — headless boot video/screenshot capture (see "Automated boot preview" above)
- `tools/iso-rebrand/` — GRUB menu text rebranding (see "GRUB boot menu rebranding" above)
- `docs/` — a running log of real build issues hit in CI and how they were fixed

## Boot splash: "DMJ Cinematic"

A custom Plymouth "script" theme built around the real DMJ OS logo:
background fades in, a two-layer parallax particle field drifts upward
(dim/slow "far" particles behind bright/fast "near" ones, for actual
depth rather than one flat layer), the glow blooms, and the logo pops
in with a slight overshoot-and-settle bounce rather than a flat linear
scale — the same reveal technique used in modern app/logo animations.
A soft light sweep passes once across the scene right after the logo
settles, and the glow keeps a slow "breathing" pulse for the rest of
the boot. A thin progress bar fills in sync with real boot progress.

Files:
- `dmj-cinematic.plymouth` — theme metadata
- `dmj-cinematic.script` — the animation itself (Plymouth's script language)
- `images/logo.png`, `images/logo_glow.png` — the real DMJ OS logo + glow variant
- `images/particle.png` — ambient particle sprite (reused for both depth layers)
- `images/progress_dot.png` — used (stretched) to build the progress bar
- `generate_assets.py` — a **dev-only fallback** for prototyping a
  placeholder text logo; the shipped `images/` are the real hand-designed
  assets, don't rerun this against them unless you mean to replace them

**Animation timing** (all driven by `ease_out`/`ease_out_back` — no fixed
frame sequence, computed live each frame from elapsed time, so it stays
correct regardless of actual boot speed):
- 0.0–1.0s: background fade-in
- 0.5–1.6s: glow bloom
- 0.9–2.3s: logo pop-in with overshoot (grows from 65% → ~110% peak → settles at 100%)
- 2.1–3.0s: one light-sweep pass across the scene
- 2.3s onward: glow settles into a continuous slow pulse

**On the "find something online" idea:** there's no way to legally embed
someone else's actual boot animation (copyrighted artwork/code), so
instead this was built by researching real cinematic reveal techniques
(overshoot/back-easing "pop" reveals, parallax depth layers, light-sweep
passes) and implementing them from scratch against our own logo and the
existing particle/glow assets — verified by hand-checking the easing
math (see the interpreter-free numeric check that produced the 0 → ~1.10
peak → 1.0 curve) before trusting it, since there's no local Plymouth
script interpreter to test against directly.

**To swap in a different logo:** replace `images/logo.png` and
`images/logo_glow.png` (same dimensions/aspect ideally) — the script
scales them to fit the screen automatically. If you also use the deluxe
wallpaper, rerun `python3 config/wallpaper/generate_wallpaper.py`
afterward so the wallpaper watermark matches, and
`python3 config/branding/generate_icons.py` to refresh the menu/distributor
icons too.

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

**Fixed bugs from real testing** (a deluxe build's screenshot showed the
welcome dialog working correctly, but the stock Debian wallpaper and
default icons instead of ours):

- **Wallpaper wasn't applying at all.** The original approach wrote a
  static `xfce4-desktop.xml` with guessed monitor property names
  (`monitor0`, `monitorVirtual1`). XFCE actually names these based on the
  real detected display hardware at runtime (varies by GPU driver/VM),
  so the guess essentially never matched anything. Fixed by replacing it
  with `config/wallpaper/dmj-set-wallpaper.sh`, which runs at login and
  asks `xfconf-query` directly what monitor/workspace properties exist
  right now, then sets the wallpaper on whichever ones actually do.
  Verified against a mock `xfconf-query` returning realistic
  (non-guessable) property names before trusting it.
- **Icon theme silently failing to install.** The `WhiteSur-icon-theme`
  install step had no failure fallback, unlike the GTK theme and cursor
  steps next to it — under the hook's `set -e`, if that one install
  failed for any reason, it silently killed the rest of the script
  before cursors ever got a chance to install too. Rewrote the hook so
  each of the three components (GTK theme, icons, cursors) installs
  independently with a clear `OK:`/`FAIL:` line, so one failing never
  blocks the others and a future log will show exactly which component
  had trouble instead of a silent partial failure.

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
