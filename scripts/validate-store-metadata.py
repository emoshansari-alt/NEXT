#!/usr/bin/env python3
"""Validate App Store listing metadata against Apple's current published limits.

Every limit here is quoted from Apple's own documentation rather than remembered, and the
source is named beside it. The point of the script is that no field is ever eyeballed: a
subtitle at 31 characters is rejected by App Store Connect, and finding that out during a
submission is the expensive way to find it out.

Sources, checked 2026-08-12:

  App name          2-30 characters
                    https://developer.apple.com/help/app-store-connect/reference/app-information/
                    "The name must be at least two characters and no more than 30 characters."
  Subtitle          <= 30 characters, optional
                    same page: "This can't be longer than 30 characters."
  Promotional text  <= 170 characters
  Description       <= 4000 characters, plain text, no HTML
  Keywords          <= 100 BYTES, comma separated, each term longer than two characters
                    https://developer.apple.com/help/app-store-connect/reference/platform-version-information/
                    "Up to 100 bytes of content." / "One or more keywords, each greater than
                    two characters." / "Your app is searchable by app name and company name,
                    so you shouldn't duplicate these values in the keyword list."
  Keyword hygiene   https://developer.apple.com/app-store/search/
                    "Don't repeat any words included in your app name, subtitle, or category."

The keyword field is measured in UTF-8 bytes because Apple states the limit in bytes. For
pure ASCII copy that equals the character count; for a curly apostrophe it does not, which is
exactly the case a person counting by eye gets wrong.

Standard library only, and **wired into the guardrails job** beside the other linters now that
the listing is approved and this file holds exactly one. Said as an installed fact rather than an
intention, because a guarantee described but never installed is exactly D-028.

The file is the copy of record for anything measurable. `PRODUCT_SPEC.md` §15 is the copy of
record for a human, and the two must agree — a change to one without the other is the drift this
script exists to make expensive.

    python scripts/validate-store-metadata.py

Exit code 1 if any field is over a limit or breaks a documented rule.
"""

import re
import sys
import unicodedata

# The approved listing. `PRODUCT_SPEC.md` §15 is the prose; this is the data.
DIRECTIONS = {}


def direction(key, name, subtitle, promotional, keywords, categories, description):
    DIRECTIONS[key] = {
        "name": name,
        "subtitle": subtitle,
        "promotional": promotional,
        "keywords": keywords,
        "categories": categories,
        "description": description,
    }


# --- The approved NEXT 1.0 listing ------------------------------------------------------------
#
# Approved by the owner on 2026-08-12 (DECISIONS.md D-038), from direction 2R of the three
# proposed in session 15, with one amendment to the promotional text. The three competing
# directions and the pre-audit version of this one were deleted rather than left here: a listing
# file holding four listings is a file where the wrong one gets copied into App Store Connect.
# Their reasoning is preserved in STORE_LISTING_PROPOSALS.md and D-038.

direction(
    "NEXT 1.0 — approved",
    name="NEXT: Homework & Deadlines",
    subtitle="Six things due? Start one.",
    # Amended by the owner from 2R's "New semester. Put the whole reading list in, …" for two
    # stated reasons, both about reach rather than taste: "New semester" makes evergreen copy
    # seasonal in a field that can be edited at any time but usually is not, and "reading list"
    # narrows the apparent use case below the positioning the name carries.
    promotional=(
        "Too much due at once? Put it all in, and NEXT will tell you what to do first."
    ),
    keywords=(
        "study,assignment,coursework,exam,essay,student,college,"
        "todo,task,procrastination,overwhelmed,school"
    ),
    categories=["Productivity", "Utilities"],
    description="""Six things due this week. NEXT gives you one of them — one task, one action, and the reason it picked that one.

Put it all in: type it, paste it, one line each or all in one go. NEXT reads it into separate tasks and asks you about any date it is not sure of, rather than guessing one.

WHAT IT ACTUALLY DOES
• Takes a whole brain dump at once, typed or pasted
• Reads the dates it recognizes, and asks instead of guessing when it does not
• Picks one thing to do now, and tells you why it picked it
• Breaks a task you are avoiding down to one physical first step
• Opens a single Focus screen with that one action on it and an optional timer, then leaves you alone
• Keeps the whole list in Everything, sorted into Overdue, Today, Upcoming and No deadline, for when you do want to see it

THE ESSAY YOU CANNOT FACE
Tap I'm stuck and say what is in the way.
• I don't know how to start — NEXT gives you the smallest physical action, one at a time, so you never see the whole mountain
• It's too much — it hides the mountain
• I don't have the time — say how much you have, five minutes or fifteen or thirty, and NEXT finds the most useful thing that genuinely fits, or tells you plainly that nothing does
• I just don't want to — no lecture. Do five minutes, then decide whether to carry on

WHEN IT IS TOO LATE TO DO IT PROPERLY
An assignment you can no longer finish in the time left gets a smaller version that is still worth doing — outline, then introduction, then first section — and a time to come back and reassess. One whose deadline has already passed says so, without a lecture, and still offers you something you can do now. Late work quietly stops shouting instead of pinning itself to your screen forever.

NO STREAKS, NO GUILT, NO ACCOUNT
NEXT never tells you that you have fallen behind, broken anything, or let yourself down. There is no sign-up, no email address, no tracking and no ads. It makes no network requests of its own, so it works with no signal at all, and nothing you write ever leaves your phone.

For high school and college.""",
)


# --- Limits, each traceable to the source above ------------------------------------------------

NAME_MIN, NAME_MAX = 2, 30
SUBTITLE_MAX = 30
PROMOTIONAL_MAX = 170
DESCRIPTION_MAX = 4000
KEYWORDS_MAX_BYTES = 100
KEYWORD_MIN_LENGTH = 3          # "each greater than two characters"

# Words too common to be worth flagging as a name/subtitle/keyword collision.
STOP_WORDS = {
    "a", "an", "and", "at", "for", "in", "it", "of", "on", "or", "the", "to", "you", "your",
    "do", "is", "not", "with",
}


def words(text):
    """Lowercased word set, apostrophes folded, so You're and youre collide."""
    return {
        w for w in re.findall(r"[a-z0-9']+", text.lower().replace("’", "'"))
        if w not in STOP_WORDS
    }


def report(label, value, limit, unit="characters"):
    size = len(value.encode("utf-8")) if unit == "bytes" else len(value)
    ok = size <= limit
    print(f"  {'PASS' if ok else 'FAIL'}  {label:<16} {size:>4} / {limit} {unit}")
    return ok


def check(key, listing):
    print(f"\n{key}")
    ok = True

    name = listing["name"]
    ok &= report("app name", name, NAME_MAX)
    if len(name) < NAME_MIN:
        print(f"  FAIL  app name is shorter than the {NAME_MIN}-character minimum")
        ok = False

    ok &= report("subtitle", listing["subtitle"], SUBTITLE_MAX)
    ok &= report("promotional", listing["promotional"], PROMOTIONAL_MAX)
    ok &= report("description", listing["description"], DESCRIPTION_MAX)
    ok &= report("keywords", listing["keywords"], KEYWORDS_MAX_BYTES, unit="bytes")

    keywords = listing["keywords"]

    # Apple's format: comma separated, no space after the comma. A space there is not an error
    # App Store Connect rejects, which is worse: it silently spends a byte of the hundred.
    if " ," in keywords or ", " in keywords:
        print("  FAIL  keywords contain a space beside a comma — each one costs a byte")
        ok = False

    terms = [t for t in keywords.split(",")]
    for term in terms:
        if not term:
            print("  FAIL  keywords contain an empty term")
            ok = False
        elif len(term) < KEYWORD_MIN_LENGTH:
            print(f"  FAIL  keyword {term!r} is not longer than two characters")
            ok = False
        if term != term.strip():
            print(f"  FAIL  keyword {term!r} has leading or trailing whitespace")
            ok = False

    seen = set()
    for term in terms:
        if term.lower() in seen:
            print(f"  FAIL  keyword {term!r} is duplicated")
            ok = False
        seen.add(term.lower())

    # Non-ASCII is legal but costs more than one byte per character, which is the whole reason
    # the limit is stated in bytes. Say so rather than letting it be discovered by arithmetic.
    for field in ("name", "subtitle", "promotional", "keywords"):
        for ch in listing[field]:
            if ord(ch) > 127:
                print(
                    f"  NOTE  {field} contains {unicodedata.name(ch, repr(ch))}, "
                    f"{len(ch.encode('utf-8'))} bytes"
                )

    # "Don't repeat any words included in your app name, subtitle, or category."
    indexed = words(name) | words(listing["subtitle"])
    for category in listing["categories"]:
        indexed |= words(category)

    wasted = sorted(w for term in terms for w in words(term) if w in indexed)
    if wasted:
        print(f"  FAIL  keywords repeat indexed words: {', '.join(sorted(set(wasted)))}")
        ok = False

    if "’" in listing["name"] or "’" in listing["subtitle"]:
        print("  NOTE  curly apostrophe in a searchable field — a typed one will not match it")

    return ok


def main():
    print("App Store metadata — validated against Apple's published limits, 2026-08-12")
    ok = True
    for key, listing in DIRECTIONS.items():
        ok &= check(key, listing)
    print()
    if not ok:
        sys.exit("at least one field is over a limit or breaks a documented rule")
    print("all fields within Apple's limits")


if __name__ == "__main__":
    main()
