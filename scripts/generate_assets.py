#!/usr/bin/env python3
"""Extract frame binary and AAC audio assets from a source video for BadAppleSB."""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import zlib

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEO_EXTENSIONS = (".webm", ".mp4", ".mkv", ".mov")


def find_default_input():
    """Return the first video file found in the repository root, if any."""
    for name in sorted(os.listdir(REPO_ROOT)):
        if name.lower().endswith(VIDEO_EXTENSIONS):
            return os.path.join(REPO_ROOT, name)
    return None


def stretch_tv_luma(raw: bytes) -> bytes:
    # Build lookup table that crushes near-black (<=20 -> 0) and near-white (>=235 -> 255)
    # so black background cells are completely transparent and white cells are solid icons.
    lut = bytearray(256)
    for v in range(256):
        if v <= 20:
            lut[v] = 0
        elif v >= 235:
            lut[v] = 255
        else:
            lut[v] = round((v - 20) * 255.0 / (235 - 20))
    return bytes(lut[b] for b in raw)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate 72x54 frame binary and AAC audio assets for BadAppleSB."
    )
    parser.add_argument(
        "--input",
        default=None,
        help="Path to the source video file (defaults to a video file in the repo root).",
    )
    parser.add_argument(
        "--out-dir",
        default=os.path.join(REPO_ROOT, "layout", "Library", "Application Support", "BadAppleSB"),
        help="Output directory for badapple.bin and badapple.m4a.",
    )
    parser.add_argument("--width", type=int, default=72)
    parser.add_argument("--height", type=int, default=54)
    parser.add_argument("--fps", type=int, default=30)
    args = parser.parse_args()

    if not shutil.which("ffmpeg"):
        print("Error: ffmpeg is required on PATH.", file=sys.stderr)
        sys.exit(1)

    input_path = os.path.abspath(os.path.expanduser(args.input)) if args.input else find_default_input()
    if not input_path or not os.path.isfile(input_path):
        print(
            "Error: Source video not found. Pass --input <video_path> or place a video file in the repo root.",
            file=sys.stderr,
        )
        sys.exit(1)
    args.input = input_path

    os.makedirs(args.out_dir, exist_ok=True)
    bin_path = os.path.join(args.out_dir, "badapple.bin")
    audio_path = os.path.join(args.out_dir, "badapple.m4a")

    print(f"Extracting {args.width}x{args.height} @ {args.fps}fps grayscale frames...")
    raw = subprocess.check_output(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            args.input,
            "-vf",
            f"fps={args.fps},scale={args.width}:{args.height}:flags=area",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "gray",
            "-",
        ]
    )

    frame_size = args.width * args.height
    frame_count = len(raw) // frame_size
    trimmed = stretch_tv_luma(raw[: frame_count * frame_size])
    compressed = zlib.compress(trimmed, 9)

    # Header: magic "BA01" (4B), width (u16), height (u16), fpsNum (u16), fpsDen (u16), frameCount (u32), rawSize (u32)
    header = struct.pack(
        "<4sHHHHII",
        b"BA01",
        args.width,
        args.height,
        args.fps,
        1,
        frame_count,
        len(trimmed),
    )
    with open(bin_path, "wb") as f:
        f.write(header)
        f.write(compressed)

    print(
        f"Wrote {bin_path}: {frame_count} frames ({args.width}x{args.height}), "
        f"raw={len(trimmed)} bytes, compressed={len(compressed)} bytes"
    )

    print("Extracting AAC audio...")
    subprocess.check_call(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-i",
            args.input,
            "-vn",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
            "-ar",
            "44100",
            "-ac",
            "2",
            "-movflags",
            "+faststart",
            audio_path,
        ]
    )
    print(f"Wrote {audio_path}: {os.path.getsize(audio_path)} bytes")


if __name__ == "__main__":
    main()
