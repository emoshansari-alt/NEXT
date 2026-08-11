#!/usr/bin/env python3
"""The app icon cannot drift from the app's colours, and this is what makes that true.

D-023 claimed the icon was "rendered from the palette's own hex values by a script … so the asset
cannot drift from the app's colours". D-028 withdrew the claim, because the script did not exist
and nothing compared the committed PNG to `NextPalette`. This is the missing half: it reads the
hex values out of `NextPalette.swift` and checks that the shipped PNG is actually made of them.

Run it:

    python3 scripts/lint-app-icon.py

**Standard library only.** The other three guardrails are shell scripts that run in CI's Ubuntu
job, and a check that needs Pillow installed is a check that gets skipped. The PNG is decoded here
with `zlib` and `struct`, which is about forty lines and means this runs anywhere Python does —
including on the development machine, where the app layer cannot be compiled at all (D-001).

What it does **not** claim: that the icon's *shape* is generated. `scripts/render-app-icon.py`
renders it and reproduces the approved asset to 99.60% of pixels, but not byte-for-byte, so the
approved PNG remains the visual source of truth and is not overwritten. See D-033.
"""

from __future__ import annotations

import pathlib
import re
import struct
import sys
import zlib
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parent.parent
PALETTE = ROOT / "NextApp/Shared/Design/NextPalette.swift"
ICON = ROOT / "NextApp/Resources/Assets.xcassets/AppIcon.appiconset/Icon.png"

EXPECTED_SIZE = 1024

# The icon's fifth colour, and the one place it is written down.
#
# It is the unmarked line of writing on the card, and it is **not** a `NextPalette` token: nothing
# in the palette is this value and no alpha composite of two palette colours produces it. That is
# recorded rather than quietly folded in, because the interesting property of this guardrail is
# which colours it can trace to a source and which it cannot.
UNMARKED_LINE = "C9C4BA"

# Each palette token that must appear, with the share of the icon it must cover. The bounds are
# wide — this is a check that the icon is still made of these colours, not a pixel-count assertion
# that would fail on a one-pixel nudge.
REQUIRED = {
    "desk": (40.0, 65.0),
    "card": (25.0, 50.0),
    "biro": (1.0, 10.0),
    "marker": (1.0, 8.0),
}


def palette_light_values() -> dict[str, str]:
    """The `light:` half of every `dynamic(light:dark:)` in `NextPalette`."""
    source = PALETTE.read_text(encoding="utf-8")
    found = dict(
        re.findall(
            r"static let (\w+)\s*=\s*dynamic\(light:\s*0x([0-9A-Fa-f]{6})", source
        )
    )
    if not found:
        sys.exit(f"could not read any colour out of {PALETTE} — has the palette's shape changed?")
    return {name: value.upper() for name, value in found.items()}


def decode_png(path: pathlib.Path) -> tuple[int, int, list[tuple[int, int, int]]]:
    """A non-interlaced 8-bit PNG, as (width, height, pixels). Enough for this one file."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path} is not a PNG")

    width = height = depth = colour_type = interlace = None
    idat = bytearray()
    offset = 8
    while offset < len(data):
        (length,) = struct.unpack(">I", data[offset:offset + 4])
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour_type, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        offset += 12 + length

    if depth != 8 or interlace != 0 or colour_type not in (2, 6):
        sys.exit(
            f"{path}: expected an 8-bit non-interlaced RGB or RGBA PNG, got depth={depth} "
            f"colour_type={colour_type} interlace={interlace}"
        )

    channels = 3 if colour_type == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    pixels: list[tuple[int, int, int]] = []
    previous = bytearray(stride)

    at = 0
    for _ in range(height):
        filter_type = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                line[i] = (line[i] + left) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + up) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif filter_type == 4:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                nearest = left if (pa <= pb and pa <= pc) else (up if pb <= pc else upper_left)
                line[i] = (line[i] + nearest) & 0xFF
            elif filter_type != 0:
                sys.exit(f"{path}: unknown PNG filter {filter_type}")
        previous = line
        for x in range(width):
            base = x * channels
            pixels.append((line[base], line[base + 1], line[base + 2]))

    return width, height, pixels


def main() -> None:
    for path in (PALETTE, ICON):
        if not path.is_file():
            sys.exit(f"error: {path} not found. Run this from anywhere; it resolves its own paths.")

    palette = palette_light_values()
    width, height, pixels = decode_png(ICON)
    failed = False

    def fail(message: str) -> None:
        nonlocal failed
        print(f"FAIL {message}")
        print(f"::error::[app-icon] {message}")
        failed = True

    # Apple wants exactly this, unscaled, with no alpha channel.
    if (width, height) != (EXPECTED_SIZE, EXPECTED_SIZE):
        fail(f"the icon must be {EXPECTED_SIZE} x {EXPECTED_SIZE}; it is {width} x {height}")

    counts = Counter("%02X%02X%02X" % pixel for pixel in pixels)
    total = width * height

    for token, (low, high) in REQUIRED.items():
        expected = palette.get(token)
        if expected is None:
            fail(f"`NextPalette` no longer defines `{token}`, which the icon is built from")
            continue
        share = 100 * counts.get(expected, 0) / total
        if share < low or share > high:
            fail(
                f"{token} is #{expected} in the palette and covers {share:.2f}% of the icon, "
                f"outside the expected {low}–{high}%. Either the palette moved and the icon was "
                f"not re-rendered, or the icon was edited by hand."
            )
        else:
            print(f"  ok  {token:7} #{expected}  {share:5.2f}%")

    share = 100 * counts.get(UNMARKED_LINE, 0) / total
    if share < 1.0:
        fail(
            f"the unmarked line (#{UNMARKED_LINE}) covers {share:.2f}% of the icon. It is the one "
            f"colour here that is not a palette token — see D-033 — so if it has moved, it moved "
            f"by hand."
        )
    else:
        print(f"  ok  {'unmarked':7} #{UNMARKED_LINE}  {share:5.2f}%  (not a palette token)")

    # Anti-aliasing aside, this icon is five flat fills. A gradient, a shadow or a photograph
    # would push this into the thousands and is worth failing on: it would mean the asset is no
    # longer the thing `render-app-icon.py` knows how to rebuild.
    if len(counts) > 200:
        fail(f"the icon has {len(counts)} distinct colours; it is meant to be five flat fills")
    else:
        print(f"  ok  {len(counts)} distinct colours, five fills plus anti-aliasing")

    if failed:
        sys.exit(1)
    print("OK — the app icon is still made of the palette's own values.")


if __name__ == "__main__":
    main()
