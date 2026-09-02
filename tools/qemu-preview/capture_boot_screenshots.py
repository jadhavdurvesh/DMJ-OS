#!/usr/bin/env python3
"""
capture_boot_screenshots.py

Boots a DMJ OS ISO headlessly in QEMU, samples the framebuffer at a fixed
interval for the whole capture window, and produces:
  - frames/frame_XXXX.png   — every sampled frame, in order
  - boot_video.mp4          — those frames assembled into an actual video
  - a handful of named milestone PNGs (grub menu, post-boot-select, etc.)
    copied out of the frame sequence, for quick viewing without needing
    to open the video

This needs no display, no local machine, and no interactivity — designed
to run in CI right after the ISO is built, but works identically on a
local Linux machine with QEMU + Pillow + ffmpeg installed.

Usage:
    python3 capture_boot_screenshots.py <path-to-iso> <output-dir> [duration_s] [interval_s]

Requires: qemu-system-x86_64, ffmpeg on PATH; Pillow (pip install pillow).
"""
import socket
import subprocess
import sys
import time
import os
from pathlib import Path

MONITOR_PORT = 55555
MEMORY_MB = 2048

DEFAULT_DURATION_S = 180   # total capture window
DEFAULT_INTERVAL_S = 2     # seconds between frames
GRUB_SELECT_AT_S = 6       # when to send the Enter keypress to boot

# Milestone frames to also save under a human-readable name (approximate
# timestamps — actual content depends on real boot speed under emulation).
MILESTONES = {
    5: "grub_menu",
    15: "after_boot_select",
    30: "plymouth_window",
    60: "post_boot_1min",
    120: "post_boot_2min",
    180: "post_boot_3min",
}


def has_kvm():
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


def monitor_command(cmd, host="127.0.0.1", port=MONITOR_PORT, retries=15):
    last_err = None
    for _ in range(retries):
        try:
            with socket.create_connection((host, port), timeout=5) as s:
                time.sleep(0.2)
                s.recv(4096)  # QEMU monitor banner
                s.sendall((cmd + "\n").encode())
                time.sleep(0.2)
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


def assemble_video(frames_dir, out_path, fps_in, fps_out=10):
    """
    Encodes the numbered frame sequence into an MP4. fps_in is the rate that
    matches how frames were actually sampled (1/interval_s), so the video's
    real-time pacing matches the real boot; fps_out re-times it for smoother
    playback without changing frame content.
    """
    pattern = str(frames_dir / "frame_%04d.png")
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(fps_in),
        "-i", pattern,
        "-vf", f"fps={fps_out},format=yuv420p",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        str(out_path),
    ]
    print("Assembling video:", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("WARNING: ffmpeg failed:", result.stderr[-2000:], file=sys.stderr)
        return False
    return True


def main():
    if len(sys.argv) < 3:
        print(
            f"Usage: {sys.argv[0]} <iso-path> <output-dir> [duration_s] [interval_s]",
            file=sys.stderr,
        )
        sys.exit(1)

    iso_path = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2]).resolve()
    duration_s = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_DURATION_S
    interval_s = float(sys.argv[4]) if len(sys.argv) > 4 else DEFAULT_INTERVAL_S

    frames_dir = out_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    if not iso_path.exists():
        print(f"ERROR: ISO not found at {iso_path}", file=sys.stderr)
        sys.exit(1)

    kvm = has_kvm()
    print(f"KVM acceleration: {'available' if kvm else 'NOT available (will be slower)'}")
    print(f"Capturing for {duration_s}s at {interval_s}s intervals "
          f"({int(duration_s / interval_s)} frames)")

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
        start_new_session=True,
    )

    frame_count = 0
    milestones_saved = {}

    try:
        time.sleep(5)  # let the monitor socket come up
        elapsed = 0.0
        grub_select_sent = False

        n_frames = int(duration_s / interval_s)
        for i in range(n_frames):
            ppm_path = frames_dir / f"_tmp_{i:04d}.ppm"
            png_path = frames_dir / f"frame_{i:04d}.png"
            monitor_command(f"screendump {ppm_path}")
            if ppm_path.exists():
                if ppm_to_png(ppm_path, png_path):
                    frame_count += 1
            else:
                print(f"WARNING: frame {i} not produced at t={elapsed:.0f}s", file=sys.stderr)

            for m_time, m_name in MILESTONES.items():
                if m_time not in milestones_saved and elapsed >= m_time:
                    milestones_saved[m_time] = png_path
                    if png_path.exists():
                        (out_dir / f"milestone_{m_name}_t{m_time}s.png").write_bytes(
                            png_path.read_bytes()
                        )

            if not grub_select_sent and elapsed >= GRUB_SELECT_AT_S:
                print(f"[t={elapsed:.0f}s] sending Enter keypress to select boot entry")
                monitor_command("sendkey ret")
                grub_select_sent = True

            time.sleep(interval_s)
            elapsed += interval_s
    finally:
        monitor_command("quit")
        time.sleep(1)
        if proc.poll() is None:
            try:
                os.killpg(os.getpgid(proc.pid), 15)
                proc.wait(timeout=10)
            except (subprocess.TimeoutExpired, ProcessLookupError):
                try:
                    os.killpg(os.getpgid(proc.pid), 9)
                except ProcessLookupError:
                    pass

    print(f"\nCaptured {frame_count} frame(s) in {frames_dir}")

    if frame_count > 1:
        video_path = out_dir / "boot_video.mp4"
        fps_in = 1.0 / interval_s
        if assemble_video(frames_dir, video_path, fps_in=fps_in):
            print(f"Video written to {video_path}")
        else:
            print("Video assembly failed — individual frames are still available.")
    else:
        print("Not enough frames captured to assemble a video.")


if __name__ == "__main__":
    main()
