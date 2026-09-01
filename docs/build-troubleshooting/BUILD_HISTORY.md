# DMJ OS Build History and Troubleshooting

This document records build failures encountered while creating the DMJ OS ISO, their causes, and the changes made to resolve them.

## Project Build Environment

- Distribution base: Debian Bookworm
- Architecture: amd64
- Build system: Debian live-build
- CI environment: GitHub Actions on Ubuntu 24.04
- ISO name: DMJ OS
- Version: 1.0
- Codename: Ashen

---

## Issue 1: Unsupported `lb config` options

### Error

The initial build failed with errors similar to:

```text
lb config: unrecognized option '--distribution-chroot'
lb config: unrecognized option '--distribution-binary'
lb config: unrecognized option '--updates'
```

### Cause

The version of Debian `live-build` available in the GitHub Actions runner did not support all of the command-line options used by the DMJ OS build script.

### Action taken

The unsupported options were removed from the build configuration so that the script could continue with the supported `live-build` interface.

### Result

The build progressed further and exposed the next repository/build-system issue.

---

## Issue 2: Debian repository 404 while fetching `Contents-amd64.gz`

### Error

The build attempted to download:

```text
https://deb.debian.org/debian//dists/bookworm/Contents-amd64.gz
```

and received:

```text
404 Not Found
```

The build then failed with an incomplete gzip input and dependency processing errors.

### Cause

The Ubuntu-provided `live-build` version used by the GitHub Actions runner was incompatible with the expected current Debian live-build behavior and generated a request that did not work with the repository path used during the build.

### Action taken

The GitHub Actions workflow was changed to build and install the current Debian `live-build` directly from the Debian live-build source repository instead of relying on the older runner package.

Additional build tools and utilities were installed, and the workflow now verifies the active `lb` executable and version before starting the DMJ OS build.

### Result

The workflow successfully progressed past the earlier repository configuration failure and started installing the current Debian live-build tools.

---

## Issue 3: `msgfmt: command not found`

### Error

During installation of the current Debian live-build tools, the workflow failed with:

```text
msgfmt: command not found
make[1]: *** [Makefile:24: check] Error 1
make: *** [Makefile:56: install] Error 2
```

### Cause

`msgfmt` is required while processing translation files and is provided by the Debian/Ubuntu package `gettext`. The package was not included in the GitHub Actions build dependencies.

### Action taken

Added `gettext` to the workflow dependency installation step:

```text
sudo apt-get install -y \
  git \
  make \
  gettext \
  debootstrap \
  debian-archive-keyring \
  xorriso \
  isolinux \
  syslinux-common \
  wget \
  rsync \
  cpio \
  bzip2 \
  xz-utils \
  gzip
```

### Result

The next GitHub Actions build should now be able to run `msgfmt` and continue past the live-build installation stage.

---

## Issue 4: `make install` fails building manpages — `po4a: command not found`

### Error

```text
make[1]: Entering directory '/tmp/live-build/manpages'
Checking the integrity of .po files .................. done!
E: po4a - command not found
I: po4a can be obtained from https://po4a.org
I: On Debian based systems, po4a can be installed with 'apt-get install po4a'.
make[1]: *** [Makefile:42: build] Error 1
make[1]: Leaving directory '/tmp/live-build/manpages'
make: *** [Makefile:56: install] Error 2
```

### Cause

`live-build`'s `make install` target also builds and installs translated
manpages, which requires `po4a` to process the `.po` translation files.
The GitHub Actions workflow installed `gettext` (fixing Issue 2's
`msgfmt` error) but not `po4a`, which is a separate package.

### Fix

Added `po4a` to the workflow's dependency installation step:

```text
sudo apt-get install -y \
  git \
  make \
  gettext \
  po4a \
  debootstrap \
  debian-archive-keyring \
  xorriso \
  isolinux \
  syslinux-common \
  wget \
  rsync \
  cpio \
  bzip2 \
  xz-utils \
  gzip
```

### Result

Pending — next workflow run should get past the `live-build`
installation stage.

---


The DMJ OS GitHub Actions workflow now:

1. Checks out the DMJ OS repository.
2. Installs required system dependencies, including `gettext`.
3. Clones the current Debian `live-build` source.
4. Installs live-build with `make install`.
5. Verifies the installed `lb` executable and version.
6. Runs the DMJ OS build script.
7. Checks that an ISO was generated.
8. Uploads the generated ISO as a GitHub Actions artifact.

---

## Future Build Issues

For every significant build failure encountered in the DMJ OS project, add a new section containing:

- The exact error or important log excerpt.
- The root cause, if identified.
- The change made to fix or investigate it.
- The result of the next build.
- Any remaining follow-up work.

This creates a running engineering history for the DMJ OS build system.
