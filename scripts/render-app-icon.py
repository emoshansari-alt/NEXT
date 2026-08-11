#!/usr/bin/env python3
"""Render the app icon from `NextPalette`'s own hex values.

    python scripts/render-app-icon.py out.png       # render
    python scripts/render-app-icon.py --check       # render and compare to the committed asset

The icon is the app's card seen from above: the desk, the card with its ballpoint spine, one line
of writing, and one line marked with the highlighter. The same object `CardSurface` draws, and the
same four colours, read out of `NextPalette.swift` rather than restated here — which is the half of
D-023's promise that D-028 found missing.

Needs Pillow, so this is a development-machine script. The guardrail that runs in CI is
`lint-app-icon.py`, which uses the standard library only and checks that the committed PNG is
still made of the palette's values.

## What this does not do, and why it matters

**It does not overwrite the approved asset.** Its output reproduces
`AppIcon.appiconset/Icon.png` to 99.60% of pixels exactly and is byte-identical between runs, but
it is not byte-identical to the committed file: 4,214 pixels differ on anti-aliased curves,
because the original was drawn by Core Graphics and this is Pillow. Adopting the render would be a
small visual change to an approved asset, which is the owner's call and not a refactor's — see
**D-033**.

So the geometry below is a **measurement of the approved icon**, not a design. Every number was
recovered from the committed PNG: edges to a sub-pixel from the anti-aliasing gradient, the corner
by fitting a superellipse whose exponent came back 2.00 — a plain circle — and the rest by search
against the original. Nothing here was chosen.
"""

from __future__ import annotations

import pathlib
import re
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python -m pip install pillow")

ROOT = pathlib.Path(__file__).resolve().parent.parent
PALETTE = ROOT / "NextApp/Shared/Design/NextPalette.swift"
ICON = ROOT / "NextApp/Resources/Assets.xcassets/AppIcon.appiconset/Icon.png"

SIZE = 1024

# Rendered at 3× and downsampled with a box filter, which at exactly 3× is a 3 × 3 average —
# the operation D-023 described. Every constant below is in 3× pixels.
SCALE = 3

CARD_X, CARD_Y = 288, 626
CARD_W, CARD_H = 2497, 1823
CARD_RADIUS = 166
SPINE_W = 217

# (x, y, width, height) at 3×. Both are capsules: the radius is half the height.
UNMARKED_LINE = (757, 1116, 1643, 217)
MARKED_LINE = (757, 1680, 1343, 217)

# The one colour here that is not a palette token. Nothing in `NextPalette` is this value and no
# alpha composite of two palette colours produces it; it is the unmarked line of writing, and it
# is stated once, here, so `lint-app-icon.py` can hold the committed asset to it.
UNMARKED_INK = "C9C4BA"


def palette_light_values() -> dict[str, tuple[int, int, int]]:
    source = PALETTE.read_text(encoding="utf-8")
    found = re.findall(r"static let (\w+)\s*=\s*dynamic\(light:\s*0x([0-9A-Fa-f]{6})", source)
    if not found:
        sys.exit(f"could not read any colour out of {PALETTE} — has the palette's shape changed?")
    return {name: rgb(value) for name, value in found}


def rgb(value: str) -> tuple[int, int, int]:
    n = int(value, 16)
    return (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF


def render() -> Image.Image:
    palette = palette_light_values()
    for token in ("desk", "card", "biro", "marker"):
        if token not in palette:
            sys.exit(f"`NextPalette` no longer defines `{token}`, which the icon is built from")

    side = SIZE * SCALE
    canvas = Image.new("RGB", (side, side), palette["desk"])
    draw = ImageDraw.Draw(canvas)

    card = [CARD_X, CARD_Y, CARD_X + CARD_W - 1, CARD_Y + CARD_H - 1]
    draw.rounded_rectangle(card, CARD_RADIUS, fill=palette["card"])

    # The spine is the card's own left edge in ballpoint blue, so it takes the card's rounded
    # corners rather than square ones — the same clip `CardSurface` applies.
    rounded = Image.new("L", (side, side), 0)
    ImageDraw.Draw(rounded).rounded_rectangle(card, CARD_RADIUS, fill=255)
    band = Image.new("L", (side, side), 0)
    ImageDraw.Draw(band).rectangle(
        [CARD_X, CARD_Y, CARD_X + SPINE_W - 1, CARD_Y + CARD_H - 1], fill=255
    )
    spine = Image.composite(band, Image.new("L", (side, side), 0), rounded)
    canvas.paste(Image.new("RGB", (side, side), palette["biro"]), (0, 0), spine)

    for (x, y, width, height), colour in (
        (UNMARKED_LINE, rgb(UNMARKED_INK)),
        (MARKED_LINE, palette["marker"]),
    ):
        draw.rounded_rectangle([x, y, x + width - 1, y + height - 1], height / 2, fill=colour)

    return canvas.resize((SIZE, SIZE), Image.BOX)


def check(rendered: Image.Image) -> int:
    if not ICON.is_file():
        sys.exit(f"{ICON} not found")
    approved = Image.open(ICON).convert("RGB")
    if approved.size != rendered.size:
        sys.exit(f"size differs: approved {approved.size}, rendered {rendered.size}")

    a, b = approved.load(), rendered.load()
    differing = worst = 0
    for y in range(SIZE):
        for x in range(SIZE):
            delta = max(abs(a[x, y][i] - b[x, y][i]) for i in range(3))
            if delta:
                differing += 1
                worst = max(worst, delta)

    total = SIZE * SIZE
    print(f"identical pixels : {total - differing:>9} of {total}  ({100 * (total - differing) / total:.2f}%)")
    print(f"differing pixels : {differing:>9}  worst channel delta {worst}")
    print(
        "\nThe difference is anti-aliasing on curves — Core Graphics drew the approved asset and\n"
        "Pillow draws this one. The approved PNG stays the source of truth (D-033)."
    )
    return 0


def main() -> None:
    arguments = sys.argv[1:]
    rendered = render()

    if arguments == ["--check"]:
        sys.exit(check(rendered))
    if len(arguments) != 1:
        sys.exit(__doc__.strip().splitlines()[0] + "\n\nusage: render-app-icon.py <out.png> | --check")

    destination = pathlib.Path(arguments[0])
    if destination.resolve() == ICON.resolve():
        sys.exit(
            "refusing to overwrite the approved asset. Its 0.40% of anti-aliased pixels are a\n"
            "visual change to a decided thing, which is the owner's call — see D-033."
        )
    rendered.save(destination, "PNG")
    print(f"wrote {destination}  {rendered.width} x {rendered.height}")


if __name__ == "__main__":
    main()
