#!/usr/bin/env python3
"""Composite the six captured app frames into the Chroma App Store layout.

The frames themselves come from the running app — `ScreenshotCaptureUITests` drives the six real
states and CI exports them (D-024: the real UI is the source of truth for anything representing
the product). This script does the one thing left: put each frame on its colour field. It draws
nothing that claims to be the app.

Run it:

    python scripts/compose-store-screenshots.py <exported-attachments-dir> <output-dir>

where the input directory is the `screenshots/` folder from the CI run's `app-store-screenshots`
artifact — the one holding `manifest.json` and six UUID-named PNGs.

Needs Pillow, which is why this is a development-machine script and not a CI step: NEXT ships no
third-party dependency (D-010) and adding a `pip install` to the workflow to composite marketing
art would put one in the build for something the build does not need. It is committed because
**D-028** is what happens when it is not — that entry withdraws a guarantee about the app icon
that named a rendering script nobody ever wrote, and it survived several sessions of review by
reading as plausible.

## The layout, and how much of it is reconstructed

Chroma was selected by the owner in session 13, after the tilt and then the per-frame crops were
removed on request. What `SESSION_LOG.md` records of it is: *one geometry, whole screen, no crop,
32-point inset, six saturated grounds*, with the real light UI.

That is the whole specification that survives. **The six ground colours were never written down**
— they existed only in the published proposal artifact — so the values below are a reconstruction,
not a recovery, and they are the one thing here worth a second opinion. They are deliberately in a
single table so replacing them is one edit.

The geometry is not a reconstruction, it is arithmetic. A 32-point inset at 3× is 96 pixels; the
frame and the canvas are the same aspect ratio, so insetting all four edges and keeping the whole
screen means the frame is width-limited and the leftover height is split evenly. That yields one
geometry for all six, which is the property the owner asked for when the varying "chin" under each
screen was noticed.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - a missing dependency should say what to do about it
    sys.exit("Pillow is required: python -m pip install pillow")


# --- The layout -----------------------------------------------------------------------------

# 6.9-inch portrait, which Apple now wants as the primary size. The 6.7-inch 1290 × 2796 is the
# other accepted one; a frame captured at that size composes to a canvas of that size.
SCALE = 3
INSET_POINTS = 32

# The display's own corner radius, so the frame reads as a screen rather than as a pasted
# rectangle. The screenshot is a plain rectangle with the app drawn to its edges; rounding it is
# what the hardware does, not decoration added to the product.
DISPLAY_CORNER_RADIUS_POINTS = 55


# --- The six grounds ------------------------------------------------------------------------

# RECONSTRUCTED. See the module docstring: the selected values were never committed.
#
# What is deliberate about them, so that a replacement can keep it:
#
# - `02-today` carries ballpoint blue, which is `NextPalette.biro`'s light value exactly. It is
#   the hero frame and the one place the ground and the product share a colour.
# - The other five are spaced around the wheel at a similar depth, so the set reads as one system
#   rather than six posters, and every one of them is dark enough for NEXT's warm off-white UI to
#   sit on it as an object.
# - `06-late` is **not** red. The frame shows overdue work, and the product's whole position on
#   lateness is that it stops shouting rather than escalating (D-020). A red ground would
#   contradict the screenshot it is behind.
# - `05-stuck` is warm rather than alarmed, for the same reason: that screen is the empathetic
#   beat, not the error state.
GROUNDS = {
    "01-capture": "#B45309",
    "02-today": "#2438C8",
    "03-why": "#7C2D91",
    "04-focus": "#047857",
    "05-stuck": "#BE185D",
    "06-late": "#0E7490",
}

EXPECTED_FRAMES = sorted(GROUNDS)


def load_manifest(source: Path) -> dict[str, Path]:
    """Map `01-capture` … `06-late` to the UUID-named file each was exported as.

    Read from the manifest rather than from the filenames, because `xcresulttool export
    attachments` names the files by UUID and puts the name the test gave them in the manifest.
    Sorting the directory listing would order the set by a random identifier, which is a mistake
    that would look like a working script and produce a listing whose story is shuffled.
    """
    manifest_path = source / "manifest.json"
    if not manifest_path.is_file():
        sys.exit(f"no manifest.json in {source} — point this at the exported attachments directory")

    found: dict[str, Path] = {}

    def walk(node: object) -> None:
        if isinstance(node, dict):
            exported = node.get("exportedFileName")
            suggested = node.get("suggestedHumanReadableName")
            if isinstance(exported, str) and isinstance(suggested, str):
                # `01-capture_0_3CD5A7AC-….png` — the name the test gave, then XCTest's own suffix.
                found[suggested.split("_")[0]] = source / exported
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(json.loads(manifest_path.read_text()))
    return found


def compose(frame: Image.Image, ground: str) -> Image.Image:
    """One frame on one colour field."""
    canvas = Image.new("RGB", frame.size, ground)

    inset = INSET_POINTS * SCALE
    width = frame.width - inset * 2
    height = round(frame.height * (width / frame.width))
    shot = frame.resize((width, height), Image.LANCZOS)

    radius = round(DISPLAY_CORNER_RADIUS_POINTS * SCALE * (width / frame.width))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (width - 1, height - 1)], radius, fill=255)

    # The whole screen, and the leftover height split evenly — one geometry for all six.
    canvas.paste(shot, ((canvas.width - width) // 2, (canvas.height - height) // 2), mask)
    return canvas


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[0] + "\n\nusage: compose-store-screenshots.py <exported-attachments-dir> <output-dir>")

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)

    frames = load_manifest(source)

    missing = [name for name in EXPECTED_FRAMES if name not in frames]
    if missing:
        # The same rule the CI export step already enforces: a step that hands back an incomplete
        # set must not look like one that succeeded.
        sys.exit(f"the export is missing {len(missing)} frame(s): {', '.join(missing)}")

    sizes = set()
    for name in EXPECTED_FRAMES:
        with Image.open(frames[name]) as frame:
            composed = compose(frame.convert("RGB"), GROUNDS[name])
        # PNG without an alpha channel: App Store Connect rejects transparency.
        destination = output / f"{name}.png"
        composed.save(destination, "PNG")
        sizes.add(composed.size)
        print(f"{destination}  {composed.width} x {composed.height}  on {GROUNDS[name]}")

    if len(sizes) != 1:
        sys.exit(f"the six frames did not compose to one size: {sorted(sizes)} — a listing needs one")

    print(f"\nComposed {len(EXPECTED_FRAMES)} frames at {sizes.pop()}.")


if __name__ == "__main__":
    main()
