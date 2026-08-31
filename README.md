# DMJ OS — build kit

A Debian-based custom distro with your **Saudade v4** model baked in as a
CLI assistant (`dmj-ai`). Built with `debootstrap` + `live-build`.

## Where to run this

Run on a real Linux machine (bare metal or a Debian/Ubuntu VM) with
network access and root. It won't run inside a locked-down sandbox —
`debootstrap` and `lb build` need to reach Debian mirrors and use
privileged mount/chroot operations.

## 1. Install prerequisites

```bash
sudo apt update
sudo apt install debootstrap live-build
```

## 2. Add your Saudade v4 assets

Before building, drop these into `dmj-ai-assets/` (create the folder next
to this README):

```
dmj-os/
  dmj-ai-assets/
    saudade_v4.pt        <- your trained checkpoint
    tokenizer_32k.json   <- your tokenizer
```

Also **vendor your model class**: copy the `SaudadeGPT` model definition
from your `microgpt_by_DMJ` repo into
`config/includes.chroot/opt/dmj-ai/saudade_model.py` so
`dmj_ai_infer.py` can import it. The inference script currently has a
placeholder import — see the comment block near the top of
`config/dmj-ai/dmj_ai_infer.py`.

## 3. Edit config (optional)

Open `build/build-dmj-os.sh` and adjust the top `CONFIG` block:
- `VERSION_CODENAME` — your release name (kept separate from "DMJ OS" the product name)
- `VERSION_NUMBER`
- `BASE_SUITE` — Debian release to base on (default: bookworm)

## 4. Build

```bash
cd dmj-os
sudo build/build-dmj-os.sh
```

This takes anywhere from 15 minutes to over an hour depending on your
connection and machine, since it downloads and builds a full Debian base
system plus a desktop environment (XFCE).

Output ISO lands in `out/`.

## 5. Test it

```bash
qemu-system-x86_64 -m 2048 -cdrom out/dmjos-1.0-ashen.iso
```

Once booted, open a terminal and run:

```bash
dmj-ai "hello, who are you?"
```

## What's included

- `build/build-dmj-os.sh` — main build script (debootstrap config, branding, live-build invocation)
- `config/dmj-ai/dmj_ai_infer.py` — CPU inference script for Saudade v4
- `config/dmj-ai/dmj-ai` — CLI wrapper installed to `/usr/local/bin/dmj-ai`
- `config/plymouth/dmj-cinematic/` — custom animated boot splash (see below)

## Boot splash: "DMJ Cinematic"

A custom Plymouth "script" theme: background fades in, a glowing wordmark
scales/fades in, ambient particles drift upward in the background, and a
thin progress bar fills in sync with real boot progress.

Files:
- `dmj-cinematic.plymouth` — theme metadata
- `dmj-cinematic.script` — the animation itself (Plymouth's script language)
- `generate_assets.py` — regenerates the logo/glow/particle images with Pillow
- `images/` — the generated PNG assets (already built and included)

**To tweak the look:** edit `generate_assets.py` (colors, text, fonts) then
rerun `python3 generate_assets.py` before rebuilding the ISO. To tweak
timing/motion, edit the fade/scale windows (e.g. `(t - 0.6) / 1.6`) directly
in `dmj-cinematic.script`.

**To preview without a full ISO build**, on a Linux machine with Plymouth
installed:
```bash
sudo cp -r config/plymouth/dmj-cinematic /usr/share/plymouth/themes/
sudo plymouth-set-default-theme -R dmj-cinematic
sudo plymouthd --debug --no-daemon &
sudo plymouth --show-splash
# Ctrl+C the plymouthd process when done previewing
```
Or test it properly by rebuilding the ISO and booting it in QEMU — that's
the most reliable way to see real boot timing.

The build script installs this theme automatically and sets it as the
system default — no extra steps needed at build time beyond what's in
`build-dmj-os.sh`.

## What's still a placeholder / TODO

- **Model class import** in `dmj_ai_infer.py` — you must vendor your real `SaudadeGPT` class
- **Desktop wallpaper/icons** — not yet set; add files under `config/includes.chroot/usr/share/backgrounds/` and reference them in a default XFCE config
- **GPU inference / Hiraeth** — not included; Hiraeth (7B, QLoRA) is too heavy for a general live ISO. Could be added as an optional post-install package later if the machine has a capable GPU

## Versioning note

"DMJ OS" is the fixed product name. `VERSION_CODENAME` in the build
script is the separate release name — currently set to "Ashen" as a
placeholder, change it to whatever you want each release called.

## Building without a local machine (GitHub Actions)

You don't need a local Linux box or a Codespaces/Cloud Shell session for
this — `.github/workflows/build-iso.yml` runs the entire build
(debootstrap, Plymouth theme, live-build) on GitHub's own servers and
uploads the finished ISO as a downloadable artifact when done.

**Setup:**
1. Push this whole `dmj-os/` folder to the GitHub repo where your
   `saudade_v4.pt` checkpoint already lives (if the checkpoint is large,
   track it with [Git LFS](https://git-lfs.com/) — GitHub blocks files over 100MB otherwise)
2. Open `.github/workflows/build-iso.yml` and fix the **"Stage Saudade
   checkpoint"** step — replace `path/to/your/saudade_v4.pt` and
   `.../tokenizer_32k.json` with wherever those files actually sit in your repo
3. Also still vendor your real `SaudadeGPT` class into
   `config/includes.chroot/opt/dmj-ai/saudade_model.py` (see above) — the
   workflow doesn't do this for you, since I don't have your model class definition
4. Commit and push

**Running it:**
- Repo's **Actions** tab → **Build DMJ OS ISO** → **Run workflow** (lets you set a release codename, e.g. "Ashen")
- Or just push a change under `dmj-os/` to `main` — triggers automatically
- Takes roughly 30–60 minutes
- When it finishes: open the run → **Artifacts** → download `dmj-os-iso` — no local build tools needed at any point

**Disk space note:** GitHub's free runners have ~14GB free disk. A minimal
XFCE image should fit, but if you add many more packages and the build
starts failing on space, trim `config/package-lists/dmj-os.list.chroot`
or drop `task-xfce-desktop` for a lighter/terminal-only environment.
