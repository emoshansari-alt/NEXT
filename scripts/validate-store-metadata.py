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

Standard library only, so it *could* run in the guardrails job beside the other linters — it is
deliberately not wired in yet, because it currently holds three competing proposals and a lint
that fails on an unchosen option is noise. It is wired into CI when the listing is chosen and
this file is reduced to that one listing. Said plainly here rather than implied, because a
guarantee described but not installed is exactly D-028.

    python scripts/validate-store-metadata.py

Exit code 1 if any field is over a limit or breaks a documented rule.
"""

import re
import sys
import unicodedata

# The three proposed directions. STORE_LISTING_PROPOSALS.md is the prose; this is the data.
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


# --- Direction 1: one thing at a time ---------------------------------------------------------

direction(
    "1 — One thing at a time",
    name="NEXT: One Thing at a Time",
    subtitle="Stop deciding. Start doing.",
    promotional=(
        "No account, no sign-up, and no internet needed. Everything you write stays on your "
        "phone, and everything NEXT does is free."
    ),
    keywords=(
        "todo,task list,homework,assignment,deadline,study,revision,student,"
        "procrastination,overwhelmed,focus"
    ),
    categories=["Productivity", "Utilities"],
    description="""You have too much to do and no idea where to start. NEXT gives you one thing.

Put everything on your mind into it — one line each, or all in one go. NEXT works out what matters right now and shows you a single card: one task, one action, and one sentence saying why it chose that one. Start it, finish it, get the next one.

ONE CARD, NOT A LIST
NEXT never shows you a wall of work and asks you to pick. There is one card. If it is the wrong one, say so — can't do it right now, need something shorter, haven't got what I need — and NEXT chooses again, and does not offer that one back to you straight away.

IT TELLS YOU WHY
Every card carries its reason. Due in two days. Finishing this unblocks three other tasks. Nothing to decide before you start. You never have to trust a ranking you cannot see.

WHEN YOU ARE STUCK, SAY SO
Tap I'm stuck and pick what is actually in the way: you don't know how to start, it's too much, you haven't got the time, or you just don't want to. NEXT does not tell you to try harder. It makes the thing smaller and gives you one physical first step — open the assignment, find one source — or asks how long you have got and finds something that fits it.

WHEN THE WHOLE THING NO LONGER FITS
Work you cannot finish before its deadline gets a smaller version that is still worth doing, and a time to come back and reassess. Work whose deadline has already gone says so plainly, and still offers you something you can do now.

THEN IT GETS OUT OF THE WAY
START opens one screen with one action on it and a timer you do not have to use. No dashboard, no streak, no badge counting how far behind you are. Nothing here is designed to keep you in the app — a good session lasts twenty seconds.

NOTHING LEAVES YOUR PHONE
There is no account and no sign-up. NEXT makes no network requests of its own: what it suggests is worked out on your phone, by ordinary code. No tracking, no ads, no analytics. It works on a train, in a basement, and in aeroplane mode.

Light and dark. Reminders only if you want them, for deadlines you set yourself.

Made for students who are drowning in coursework and cannot face the list.""",
)


# --- Direction 2: homework and deadlines ------------------------------------------------------

direction(
    "2 — Homework and deadlines",
    name="NEXT: Homework & Deadlines",
    subtitle="Six things due? Start one.",
    promotional=(
        "Term has started. Put the whole reading list in, and NEXT will tell you which part of "
        "it to do first."
    ),
    keywords=(
        "study,revision,assignment,coursework,exam,essay,student,college,"
        "todo,task,procrastination,planner"
    ),
    categories=["Productivity", "Utilities"],
    description="""Six things due this week. A reading list you have not opened. An essay you have been not-starting for four days. NEXT is for that.

Put it all in — type it, paste it, one line each or all in one go. NEXT reads it into separate tasks, asks you about any date it is not sure of, and then shows you one card: one task, one action, and why that one and not the others.

WHAT IT ACTUALLY DOES
• Reads a brain dump into separate tasks with deadlines
• Picks one thing to do now, and tells you why it picked it
• Breaks a task you are avoiding into a first step you can do in five minutes
• Opens a single Focus screen with an optional timer
• Keeps the whole list in Everything, sorted into Overdue, Today, Upcoming and No deadline, for when you do want to see it

THE ESSAY YOU CANNOT FACE
Tap I'm stuck and say what is in the way. Don't know how to start: NEXT gives you the smallest physical action, one at a time, so you never see the whole mountain. It's too much: it hides the mountain. Haven't got the time: it asks how long you have got — five minutes, fifteen, thirty — and finds the most useful thing that genuinely fits.

WHEN IT IS TOO LATE TO DO IT PROPERLY
An assignment you can no longer finish in the time left gets a smaller version that is still worth handing in the work for: outline, then introduction, then first section, with a time to reassess. One whose deadline has already passed says so, without a lecture, and still offers you something you can do now. Late work quietly stops shouting instead of pinning itself to your screen for ever.

NO STREAKS, NO GUILT, NO ACCOUNT
NEXT never tells you that you have fallen behind, broken anything, or let yourself down. There is no sign-up, no email address, no tracking and no ads. It makes no network requests of its own, so it works with no signal at all, and nothing you write ever leaves your phone.

For sixth form, college and university.""",
)


# --- Direction 3: for when you cannot start ---------------------------------------------------

direction(
    "3 — For when you cannot start",
    name="NEXT: When You're Stuck",
    subtitle="Too much to do? Do one thing.",
    promotional=(
        "Free, offline, and no account. If you have opened five apps today and still not "
        "started anything, this is the one to try."
    ),
    keywords=(
        "procrastination,overwhelmed,homework,assignment,deadline,study,"
        "student,focus,todo,task list,planner"
    ),
    categories=["Productivity", "Utilities"],
    description="""Knowing what you have to do is not the problem. Starting is.

NEXT is a task app built around the moment you are stuck. You put everything on your mind into it, and it gives you one thing — one task, one action, and one line saying why that one. Not a list. Not a schedule. One thing.

I'M STUCK IS THE MAIN FEATURE
It is on every screen, including inside Focus, and it asks the only question that matters: what is actually in the way?

• I don't know how to start — NEXT gives you the smallest physical action there is, one step at a time. Open the assignment instructions. Find one source.
• It's too much — the whole thing goes away and one small piece of it stays.
• I haven't got the time — say how long you have got. NEXT finds the most useful thing that genuinely fits in it, and tells you plainly when nothing does.
• I just don't want to — no diagnosis, no pep talk. Do five minutes, then decide whether to carry on.

NOTHING TO DECIDE BEFORE YOU START
Every card carries the reason it was chosen — due in two days, this unblocks three other tasks, nothing else is more pressing — so you are never being asked to trust something you cannot see. If the card is wrong, say why, and NEXT picks again.

IT NEVER TELLS YOU OFF
No streaks. No badge counting what you owe. Nothing that calls you behind. Work you are late with stops shouting instead of pinning itself to the top of the screen for ever, and a deadline you have already missed is stated as a fact, once, with something you can still do about it.

THEN IT LEAVES YOU ALONE
START opens one screen with the one action on it and a timer you do not have to use. Nothing in NEXT is built to keep you in NEXT.

PRIVATE BY CONSTRUCTION
No account, no sign-up, no email address. NEXT makes no network requests of its own — what it suggests is worked out on your phone — so there is no tracking, no ads, no analytics, and nothing you write ever leaves the device.

Written for students, and for anyone who has read the same to-do list eleven times today.""",
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
