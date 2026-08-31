# DMJ OS Build Troubleshooting Log

This document records the build issues encountered while creating the first bootable DMJ OS ISO, what caused them, and how they were addressed.

## Project

- **Operating system:** DMJ OS
- **Version:** 1.0
- **Codename:** Ashen
- **Base:** Debian 12 (Bookworm)
- **Architecture:** amd64
- **Build system:** Debian live-build
- **CI environment:** GitHub Actions

---

## Issue 1: `lb config` rejected unsupported options

### Build output

```text
lb config: unrecognized option '--distribution-chroot'
lb config: unrecognized option '--distribution-binary'
lb config: unrecognized option '--updates'
```

The GitHub Actions build then stopped with:

```text
Process completed with exit code 1
```

### What was happening

The build script successfully reached the Debian `live-build` configuration stage. The required commands `lb` and `debootstrap` were found, and the working directories were created correctly.

The failure occurred when this command was executed:

```bash
lb config ...
```

The installed version of `live-build` did not recognize three options present in the script:

```bash
--distribution-chroot bookworm
--distribution-binary bookworm
--updates true
```

### Fix

These three unsupported options were removed from `build/build-dmj-os.sh`.

The corrected configuration keeps the supported Debian Bookworm configuration, including:

```bash
--ignore-system-defaults
--mode debian
--distribution "${BASE_SUITE}"
--architecture "${ARCH}"
--mirror-bootstrap "${DEBIAN_MIRROR}"
--mirror-chroot "${DEBIAN_MIRROR}"
--mirror-binary "${DEBIAN_MIRROR}"
--security true
--archive-areas "main contrib non-free non-free-firmware"
--debian-installer live
```

### Result

The build script was updated in the repository.

- **Commit:** `5a883f0ded41b1e5c45c0e44fbf07083075b2159`
- **Commit message:** `Fix unsupported live-build config options`

The next build should now proceed past this specific `lb config` error and reach the actual `lb build` stage.

---

## Issue 2: Preventing host distribution defaults from leaking into the build

### Risk

A CI runner can contain system-level `live-build` defaults that do not match the intended operating system base. For DMJ OS, the intended base is Debian Bookworm.

### Protection added

The build configuration explicitly uses:

```bash
--ignore-system-defaults
--mode debian
--distribution "${BASE_SUITE}"
```

A verification step was also added after configuration. It checks generated configuration files for Ubuntu repository settings such as:

```text
ubuntu/
security.ubuntu.com
ubuntu/24.04
```

If such settings are found, the script stops instead of accidentally building from the wrong distribution configuration.

---

## Issue 3: Build prerequisites

### What was checked

The script checks for these required commands before continuing:

```text
lb
debootstrap
```

If either command is missing, the build stops with a clear error.

### Why

This prevents the workflow from failing later with a less understandable command-not-found error.

---

## Current build workflow

The current build process is:

1. GitHub Actions starts the workflow.
2. The workflow checks the `build` directory.
3. The build script is made executable.
4. The script is run with `sudo`.
5. Required tools are checked.
6. A clean `live-build-work` directory is created.
7. `live-build` is configured for Debian Bookworm.
8. Generated configuration is checked for accidental Ubuntu settings.
9. DMJ OS package lists and branding files are prepared.
10. `lb build` creates the live system and ISO.
11. The generated ISO is copied to the `out` directory with the expected DMJ OS filename.

---

## Build status after the latest fix

**Resolved:** The three unsupported `lb config` options that caused the recorded failure have been removed.

**Next step:** Run the GitHub Actions workflow again and inspect the next build result. If another error appears, add it to this document with:

- the exact error message,
- the stage where it occurred,
- the likely cause,
- the change made to fix it,
- and the result after the fix.

---

## Troubleshooting record template

Use this format for future build issues:

```markdown
## Issue: <short description>

### Error

```text
<exact error output>
```

### Cause

<what caused the problem>

### Fix

<what was changed>

### Result

<what happened after the change>
```

This file should be updated as the DMJ OS build system evolves so the project keeps a clear history of problems and their solutions.
