#!/usr/bin/env python3
"""
capture_boot_screenshots.py

Boots a DMJ OS ISO in QEMU under a virtual X display, samples the actual
QEMU graphical framebuffer from the very beginning of boot, and produces:
  - frames/frame_XXXX.png   — every sampled frame, in order
  - boot_video.mp4          — those frames assembled into an actual video
  - named milestone PNGs for quick inspection

Designed for GitHub Actions. The workflow provides Xvfb; locally this also
works on Linux with a normal DISPLAY.

Usage:
    python3 capture_boot_screenshots.py <path-to-iso> <output-dir> [duration_s] [interval_s]

Requires: qemu-system-x86_64, ffmpeg on PATH; Pillow (pip install pillow).
"""
import socket
import subprocess
import sys
import time
import os
import hashlib
from pathlib import Path

MONITOR_PORT = 55555
MEMORY_MB = 2048
DEFAULT_DURATION_S = 120
DEFAULT_INTERVAL_S = 1
GRUB_SELECT_AT_S = 4

MILESTONES = {
    2: "early_boot",
    5: "grub_menu",
    8: "post_boot_select",
    12: "plymouth_window",
    20: "plymouth_late",
    45: "desktop_or_login",
    90: "post_boot_90s",
    120: "post_boot_2min",
}


def has_kvm():
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


def monitor_command(cmd, host="127.0.0.1", port=MONITOR_PORT, retries=15):
    last_err = None
    for _ in range(retries):
        try:
            with socket.create_connection((host, port), timeout=5) as s:
                time.sleep(0.1)
                s.recv(4096)
                s.sendall((cmd + "\n").encode())
                time.sleep(0.15)
                return s.recv(4096)
        except OSError as e:
            last_err = e
            time.sleep(0.5)
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
    pattern = str(frames_dir / "frame_%04d.png")
    cmd = [
        "ffmpeg", "-y", "-framerate", str(fps_in), "-i", pattern,
        "-vf", f"fps={fps_out},format=yuv420p",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("WARNING: ffmpeg failed:", result.stderr[-2000:], file=sys.stderr)
        return False
    return True


def assemble_boosted_video(frames_dir, out_path, fps_in, fps_out=10):
    pattern = str(frames_dir / "frame_%04d.png")
    cmd = [
        "ffmpeg", "-y", "-framerate", str(fps_in), "-i", pattern,
        "-vf", f"fps={fps_out},eq=brightness=0.15:contrast=1.6,format=yuv420p",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("WARNING: boosted ffmpeg encode failed:", result.stderr[-1000:], file=sys.stderr)
        return False
    return True


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <iso-path> <output-dir> [duration_s] [interval_s]", file=sys.stderr)
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

    if not os.environ.get("DISPLAY"):
        print("WARNING: DISPLAY is not set. QEMU will fall back to its available display backend.", file=sys.stderr)

    kvm = has_kvm()
    print(f"KVM acceleration: {'available' if kvm else 'NOT available (will be slower)'}")
    print(f"Capturing for {duration_s}s at {interval_s}s intervals")

    cmd = [
        "qemu-system-x86_64",
        "-m", str(MEMORY_MB),
        "-smp", "2",
        "-cdrom", str(iso_path),
        "-boot", "d",
        # IMPORTANT: use a real graphical display under Xvfb. This makes the
        # capture exercise the same GRUB/Plymouth/KMS framebuffer path the
        # user sees instead of hiding QEMU's display with -display none.
        "-display", "gtk,show-cursor=off",
        "-vga", "virtio",
        "-no-reboot",
        "-monitor", f"telnet:127.0.0.1:{MONITOR_PORT},server,nowait",
    ]
    if kvm:
        cmd += ["-enable-kvm", "-cpu", "host"]

    print("Launching QEMU:", " ".join(cmd))
    proc = subprocess.Popen(
        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        start_new_session=True,
    )

    frame_count = 0
    milestones_saved = {}
    last_hash = None
    stuck_run = 0
    stuck_reported = False

    try:
        # Wait only for the monitor socket, not a fixed five-second delay.
        # Plymouth's reveal animation is intentionally concentrated in the
        # first few seconds, so the old delay could miss the entire animation.
        time.sleep(1)
        start = time.monotonic()
        grub_select_sent = False
        next_sample = start

        n_frames = int(duration_s / interval_s) + 1
        for i in range(n_frames):
            now = time.monotonic()
            elapsed = now - start
            if elapsed > duration_s + interval_s:
                break

            ppm_path = frames_dir / f"_tmp_{i:04d}.ppm"
            png_path = frames_dir / f"frame_{i:04d}.png"
            monitor_command(f"screendump {ppm_path}")

            if ppm_path.exists():
                frame_hash = hashlib.sha1(ppm_path.read_bytes()).hexdigest()
                if frame_hash == last_hash:
                    stuck_run += 1
                else:
                    stuck_run = 0
                last_hash = frame_hash

                if stuck_run * interval_s >= 15 and not stuck_reported:
                    print(
                        f"NOTE: QEMU returned byte-identical frames for about {stuck_run * interval_s:.0f}s. "
                        "If this matches a guest mode switch, inspect the milestone stills before treating it as a boot freeze.",
                        file=sys.stderr,
                    )
                    stuck_reported = True

                if ppm_to_png(ppm_path, png_path):
                    frame_count += 1
            else:
                print(f"WARNING: frame {i} not produced at t={elapsed:.1f}s", file=sys.stderr)

            for m_time, m_name in MILESTONES.items():
                if m_time not in milestones_saved and elapsed >= m_time:
                    milestones_saved[m_time] = png_path
                    if png_path.exists():
                        (out_dir / f"milestone_{m_name}_t{m_time}s.png").write_bytes(png_path.read_bytes())

            if not grub_select_sent and elapsed >= GRUB_SELECT_AT_S:
                print(f"[t={elapsed:.1f}s] sending Enter keypress to select boot entry")
                monitor_command("sendkey ret")
                grub_select_sent = True

            next_sample += interval_s
            sleep_for = next_sample - time.monotonic()
            if sleep_for > 0:
                time.sleep(sleep_for)
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

        stderr = b""
        if proc.stderr is not None:
            try:
                stderr = proc.stderr.read() or b""
            except Exception:
                pass
        if stderr:
            print("QEMU stderr (tail):", stderr.decode(errors="replace")[-4000:], file=sys.stderr)

    print(f"\nCaptured {frame_count} frame(s) in {frames_dir}")

    if frame_count > 1:
        fps_in = 1.0 / interval_s
        video_path = out_dir / "boot_video.mp4"
        boosted_path = out_dir / "boot_video_boosted.mp4"
        if assemble_video(frames_dir, video_path, fps_in=fps_in):
            print(f"Video written to {video_path}")
        if assemble_boosted_video(frames_dir, boosted_path, fps_in=fps_in):
            print(f"Brightness-boosted viewing copy written to {boosted_path}")

    from PIL import Image, ImageOps
    for milestone_png in out_dir.glob("milestone_*.png"):
        try:
            im = Image.open(milestone_png).convert("RGB")
            boosted = ImageOps.autocontrast(im, cutoff=0)
            boosted.save(milestone_png.with_name(milestone_png.stem + "_boosted.png"))
        except Exception as e:
            print(f"WARNING: could not create boosted still for {milestone_png.name}: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
