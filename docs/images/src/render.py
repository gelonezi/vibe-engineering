#!/usr/bin/env python3
"""Renders the image sources in this folder.

    banner.html -> docs/images/banner.jpg      1280 x 640, saved at 1.5x
    flow.html   -> docs/images/flow.png        1280 x 372, saved at 2x, transparent corners
    icon.svg    -> .claude-plugin/icon.png     1024 x 1024

Needs Chrome or Edge (set CHROME to its path if it isn't found) and Pillow.
Usage: python docs/images/src/render.py [banner] [flow] [icon]
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

SRC = Path(__file__).resolve().parent
IMAGES = SRC.parent
REPO = IMAGES.parent.parent

BROWSERS = [
    os.environ.get("CHROME", ""),
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    shutil.which("google-chrome") or "",
    shutil.which("chromium") or "",
    shutil.which("msedge") or "",
]


def browser():
    for path in BROWSERS:
        if path and Path(path).exists():
            return path
    sys.exit("Chrome or Edge not found. Set CHROME to the browser's path.")


def screenshot(source, width, height, scale, transparent=False):
    """Returns the source rendered by a headless browser, as a Pillow image."""
    with tempfile.TemporaryDirectory() as tmp:
        shot = Path(tmp) / "shot.png"
        args = [browser(), "--headless=new", "--disable-gpu", "--hide-scrollbars",
                f"--force-device-scale-factor={scale}", f"--window-size={width},{height}",
                f"--screenshot={shot}"]
        if transparent:
            args.append("--default-background-color=00000000")
        subprocess.run(args + [source.as_uri()], check=True, timeout=120,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        image = Image.open(shot)
        image.load()
        return image


def banner():
    out = IMAGES / "banner.jpg"
    screenshot(SRC / "banner.html", 1280, 640, 1.5).convert("RGB").save(
        out, quality=90, subsampling=0, optimize=True)
    return out


def flow():
    out = IMAGES / "flow.png"
    image = screenshot(SRC / "flow.html", 1280, 372, 2, transparent=True)
    # The diagram uses flat colours, so 256 of them keep it sharp at a tenth of the size.
    image.quantize(256, method=Image.Quantize.FASTOCTREE).save(out, optimize=True)
    return out


def icon():
    out = REPO / ".claude-plugin" / "icon.png"
    screenshot(SRC / "icon.svg", 1024, 1024, 1).convert("RGB").save(out, optimize=True)
    return out


TARGETS = {"banner": banner, "flow": flow, "icon": icon}

if __name__ == "__main__":
    names = sys.argv[1:] or list(TARGETS)
    unknown = [n for n in names if n not in TARGETS]
    if unknown:
        sys.exit(f"Unknown target: {', '.join(unknown)}. Choose from: {', '.join(TARGETS)}.")
    for name in names:
        path = TARGETS[name]()
        with Image.open(path) as image:
            print(f"{name}: {path.relative_to(REPO)}  {image.width} x {image.height}  {path.stat().st_size // 1024} KB")
