#!/usr/bin/env python3
"""
capture_boot_screenshots.py

Boots a DMJ OS ISO headlessly in QEMU and captures screenshots at a few
timestamps during boot — enough to see whether the Plymouth "DMJ
Cinematic" splash is actually rendering, without needing a GUI, a local
machine, or any interactive access. Designed to run in CI (GitHub
Actions) right after the ISO is built, but works identically on a local
Linux machine with QEMU installed.

Usage:
    python3 capture_boot_screenshots.py <path-to-iso> <output-dir>

Requires: qemu-system-x86_64 on PATH, Pillow (pip install pillow).
"""
import socket
import subprocess
import sys
import time
import os
from pathlib import Path

MONITOR_PORT = 55555
MEMORY_MB = 2048

# (label, seconds-to-wait-since-previous-capture)
# Tuned for the boot splash's own timing (fades/scales complete by ~2.6s)
# plus enough slack for slow, non-KVM emulation to actually reach that point.
CAPTURE_POINTS = [
    ("01_early_boot", 8),
    ("02_plymouth_start", 8),
    ("03_plymouth_mid_animation", 6),
    ("04_plymouth_late", 10),
    ("05_after_60s_total", 30),
    ("06_after_120s_total", 60),
]


def has_kvm():
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


def monitor_command(cmd, host="127.0.0.1", port=MONITOR_PORT, retries=15):
    last_err = None
    for _ in range(retries):
        try:
            with socket.create_connection((host, port), timeout=5) as s:
                time.sleep(0.3)
                s.recv(4096)  # QEMU monitor banner
                s.sendall((cmd + "\n").encode())
                time.sleep(0.3)
                return s.recv(4096)
        except OSError as e:
            last_err = e
            time.sleep(1)
    print(f"WARNING: monitor command '{cmd}' failed: {last_err}", file=sys.stderr)
    return None


def ppm_to_png(ppm_path, png_path):
    from PIL import Image
    try:
        Image.open(ppm_path).save(png_path)
        os.remove(ppm_path)
        return True
    except Exception as e:
        print(f"WARNING: failed to convert {ppm_path}: {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <iso-path> <output-dir>", file=sys.stderr)
        sys.exit(1)

    iso_path = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if not iso_path.exists():
        print(f"ERROR: ISO not found at {iso_path}", file=sys.stderr)
        sys.exit(1)

    kvm = has_kvm()
    print(f"KVM acceleration: {'available' if kvm else 'NOT available (will be slower)'}")

    cmd = [
        "qemu-system-x86_64",
        "-m", str(MEMORY_MB),
        "-smp", "2",
        "-cdrom", str(iso_path),
        "-boot", "d",
        "-display", "none",
        "-vga", "std",
        "-no-reboot",
        "-monitor", f"telnet:127.0.0.1:{MONITOR_PORT},server,nowait",
    ]
    if kvm:
        cmd += ["-enable-kvm", "-cpu", "host"]

    print("Launching QEMU:", " ".join(cmd))
    proc = subprocess.Popen(
        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,  # own process group, so cleanup is reliable
    )

    try:
        time.sleep(5)  # let the monitor socket come up
        elapsed = 0
        for label, wait_s in CAPTURE_POINTS:
            time.sleep(wait_s)
            elapsed += wait_s
            ppm_path = out_dir / f"{label}.ppm"
            png_path = out_dir / f"{label}_t{elapsed}s.png"
            print(f"[t={elapsed}s] capturing {label}")
            monitor_command(f"screendump {ppm_path}")
            time.sleep(0.5)
            if ppm_path.exists():
                ppm_to_png(ppm_path, png_path)
            else:
                print(f"WARNING: {ppm_path} was not produced", file=sys.stderr)
    finally:
        monitor_command("quit")
        time.sleep(1)
        if proc.poll() is None:
            try:
                os.killpg(os.getpgid(proc.pid), 15)  # SIGTERM to the whole group
                proc.wait(timeout=10)
            except (subprocess.TimeoutExpired, ProcessLookupError):
                try:
                    os.killpg(os.getpgid(proc.pid), 9)
                except ProcessLookupError:
                    pass

    pngs = sorted(out_dir.glob("*.png"))
    print(f"\nCaptured {len(pngs)} screenshot(s) in {out_dir}:")
    for p in pngs:
        print(f"  {p.name}")


if __name__ == "__main__":
    main()
