#!/usr/bin/env python3
"""Composite the six captured app frames into the Chroma App Store layout.

The frames themselves come from the running app — `ScreenshotCaptureUITests` drives the six real
states and CI exports them (D-024: the real UI is the source of truth for anything representing
the product). This script does the one thing left: put each frame on its colour field. It draws
nothing that claims to be the app.

Run it:

    python scripts/compose-store-screenshots.py <exported-attachments-dir> [<more-dirs>…] <output-dir>

where each input directory is the `screenshots/` folder from a CI run's `app-store-screenshots`
artifact — the one holding `manifest.json` and six UUID-named PNGs. More than one may be given,
and later directories override earlier ones frame by frame, which is how a single changed screen
is recaptured without re-rolling the five that did not change. See `main`.

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
    from PIL import Image, ImageDraw, ImageFont
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


# --- The captions ---------------------------------------------------------------------------

# Approved wording. Every one describes what is visible in its own frame and claims nothing the
# frame cannot show — which is why frame 6 says only that late work is not lectured at, and makes
# no claim about recovering it.
#
# D-030 is **resolved**, and the caption survived it unchanged: the frame it sits on now reads
# "This is past its deadline." and carries "What can I still do?", which is still an absence of a
# telling-off and is if anything better evidence for the words than the frame they were written
# against. The claim it declines to make is still the right one to decline — Rescue re-ranks, so
# what it offers may belong to a different task, and no caption should promise the late work back.
#
# One line each, one size for all six, in the top margin the layout already had. A shopper meets
# these at thumbnail size in a search result, so the first two carry the whole proposition on
# their own: put everything down, get one thing and the reason for it.
CAPTIONS = {
    "01-capture": "Put it all down at once.",
    "02-today": "One thing, and why.",
    "03-why": "Not the project. The first move.",
    "04-focus": "Then it gets out of the way.",
    "05-stuck": "Say what's in the way.",
    "06-late": "Behind? No lecture.",
}

CAPTION_COLOUR = "#FFFFFF"

# The largest the type is allowed to be, before fitting. Every caption is set at the same size —
# the one that fits the longest of them — because six posters at six sizes is what "one geometry"
# is meant to prevent.
CAPTION_MAX_POINTS = 84

# Candidates, in preference order. Not one hardcoded path: this runs on whichever machine has the
# exported frames, and a silently substituted font would change the set without saying so. If none
# of these exists the script stops rather than falling back to Pillow's bitmap default.
CAPTION_FONTS = [
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


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


def packed(hex_colour: str) -> int:
    """`#RRGGBB` to the integer the contrast helpers below take."""
    return int(hex_colour.lstrip("#"), 16)


def luminance(colour: int) -> float:
    """WCAG relative luminance. The same formula `NextPaletteTests` holds the palette to."""
    total = 0.0
    for shift, weight in ((16, 0.2126), (8, 0.7152), (0, 0.0722)):
        value = ((colour >> shift) & 0xFF) / 255
        total += weight * (value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4)
    return total


def contrast(first: int, second: int) -> float:
    a, b = luminance(first), luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def load_font(points: int) -> ImageFont.FreeTypeFont:
    for candidate in CAPTION_FONTS:
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, points)
    sys.exit(
        "no caption font found. Tried:\n  " + "\n  ".join(CAPTION_FONTS) +
        "\nAdd this machine's font to CAPTION_FONTS rather than letting the set render in a "
        "substituted face."
    )


def caption_points(width: int, band: int) -> int:
    """The one size every caption is set at: the largest that fits the longest of them."""
    limit_width = width - INSET_POINTS * SCALE * 2
    limit_height = band - 44 * 2

    for points in range(CAPTION_MAX_POINTS, 23, -2):
        font = load_font(points)
        widest = max(font.getbbox(text)[2] - font.getbbox(text)[0] for text in CAPTIONS.values())
        tallest = max(font.getbbox(text)[3] - font.getbbox(text)[1] for text in CAPTIONS.values())
        if widest <= limit_width and tallest <= limit_height:
            return points

    sys.exit("no caption size fits — shorten the captions rather than shrinking them further")


def compose(frame: Image.Image, ground: str, caption: str, points: int) -> Image.Image:
    """One frame on one colour field, with one line of type above it."""
    canvas = Image.new("RGB", frame.size, ground)

    inset = INSET_POINTS * SCALE
    width = frame.width - inset * 2
    height = round(frame.height * (width / frame.width))
    shot = frame.resize((width, height), Image.LANCZOS)

    radius = round(DISPLAY_CORNER_RADIUS_POINTS * SCALE * (width / frame.width))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (width - 1, height - 1)], radius, fill=255)

    # The whole screen, and the leftover height split evenly — one geometry for all six.
    top = (canvas.height - height) // 2
    canvas.paste(shot, ((canvas.width - width) // 2, top), mask)

    # The caption sits in the margin the layout already had, so adding it moves nothing: the
    # screenshot is the same size in the same place as it was before there was any text.
    ImageDraw.Draw(canvas).text(
        (canvas.width // 2, top // 2), caption,
        font=load_font(points), fill=CAPTION_COLOUR, anchor="mm"
    )
    return canvas


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(
            __doc__.strip().splitlines()[0]
            + "\n\nusage: compose-store-screenshots.py <exported-attachments-dir> "
              "[<more-dirs>…] <output-dir>"
        )

    output = Path(sys.argv[-1])
    output.mkdir(parents=True, exist_ok=True)

    # More than one source directory, and a source may be narrowed to named frames.
    #
    # This exists because a product change usually alters *one* screen, and recapturing the set
    # from a fresh run re-rolls the frames it did not need to touch. Measured rather than assumed:
    # across runs 31455519694 and 31594674340, frames 02–05 came back **byte-identical**, and
    # frame 01 did not — iOS's QuickType bar offered three predictive suggestions in one run and
    # none in the other, which is Apple's keyboard state and nothing to do with NEXT. A whole-set
    # recapture would therefore have changed a locked frame for a reason outside the product.
    #
    # So "recapture only frame 6" is said in the command, where the next person can read it,
    # rather than by assembling a folder by hand and hoping they can tell which frame came from
    # where. Later sources win, and `#` narrows one to the frames named after it:
    #
    #     compose-store-screenshots.py approved/screenshots new/screenshots#06-late out
    #
    # takes 01–05 from the approved run byte-for-byte and 06 from the new one. Every frame is
    # still a real capture of the real app — nothing here edits an image (D-024). `#` is safe as
    # a separator where `:` and `=` are not: Windows paths carry a drive letter.
    frames: dict[str, Path] = {}
    provenance: dict[str, str] = {}

    for argument in sys.argv[1:-1]:
        directory, separator, wanted = argument.partition("#")
        source = Path(directory)
        available = load_manifest(source)

        names = [name.strip() for name in wanted.split(",")] if separator else list(available)
        for name in names:
            if name not in available:
                sys.exit(f"{source} has no frame named {name!r} — it holds {', '.join(sorted(available))}")
            frames[name] = available[name]
            provenance[name] = argument

    print("Frames taken from:")
    for name in sorted(provenance):
        print(f"  {name}  <-  {provenance[name]}")
    print()

    missing = [name for name in EXPECTED_FRAMES if name not in frames]
    if missing:
        # The same rule the CI export step already enforces: a step that hands back an incomplete
        # set must not look like one that succeeded.
        sys.exit(f"the export is missing {len(missing)} frame(s): {', '.join(missing)}")

    with Image.open(frames[EXPECTED_FRAMES[0]]) as first:
        band = (first.height - round(first.height * ((first.width - INSET_POINTS * SCALE * 2) / first.width))) // 2
        points = caption_points(first.width, band)
    print(f"Captions set at {points}pt in a {band}px margin.\n")

    sizes = set()
    for name in EXPECTED_FRAMES:
        # A caption a reader cannot read is decoration. Checked rather than eyeballed, with the
        # same 4.5:1 bar the app itself is held to.
        ratio = contrast(packed(CAPTION_COLOUR), packed(GROUNDS[name]))
        if ratio < 4.5:
            sys.exit(f"{name}: caption on {GROUNDS[name]} is {ratio:.2f}:1, below 4.5:1")

        with Image.open(frames[name]) as frame:
            composed = compose(frame.convert("RGB"), GROUNDS[name], CAPTIONS[name], points)
        # PNG without an alpha channel: App Store Connect rejects transparency.
        destination = output / f"{name}.png"
        composed.save(destination, "PNG")
        sizes.add(composed.size)
        print(
            f"{destination}  {composed.width} x {composed.height}  "
            f"on {GROUNDS[name]} at {ratio:.1f}:1  “{CAPTIONS[name]}”"
        )

    if len(sizes) != 1:
        sys.exit(f"the six frames did not compose to one size: {sorted(sizes)} — a listing needs one")

    print(f"\nComposed {len(EXPECTED_FRAMES)} frames at {sizes.pop()}.")


if __name__ == "__main__":
    main()
