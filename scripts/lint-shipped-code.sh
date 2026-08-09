#!/usr/bin/env bash
#
# Two invariants that hold across every shipped target, and that nothing else was checking.
#
#   No force unwraps.  RELEASE_CHECKLIST.md and ARCHITECTURE.md §10 both require it. The rule
#                      already held when this script was written — zero `!`, `try!` and `as!`
#                      across all four shipped roots — so this is not a cleanup, it is what stops
#                      the next one being added. Its two sibling invariants say "(CI-enforced)"
#                      and this one said nothing.
#
#   No networking.     NEXT makes no network request of its own, which is the substance behind
#                      "works offline", "no network request at launch" and the privacy promise
#                      that task text does not leave the device. URLSession comes from Foundation
#                      and needs no new import, so adding one would have passed every check that
#                      existed. This makes the claim mechanical instead of a matter of reading.
#
# What this does NOT prove, and the checklist must not claim it does:
#   - StoreKit talks to Apple through an out-of-process daemon. That is Apple's traffic, it is
#     confined to the paywall, and no grep can see it.
#   - It is a source check, not a runtime one. It proves no first-party file names a networking
#     API; it does not prove no packet left the device. Only a device can show that.
#
# Run locally:  bash scripts/lint-shipped-code.sh

set -uo pipefail

SHIPPED=(NextKit/Sources NextApp/Sources NextApp/Shared NextWidget/Sources)
failed=0

for root in "${SHIPPED[@]}"; do
    if [ ! -d "$root" ]; then
        echo "error: $root not found. Run this from the repository root."
        exit 1
    fi
done

# Drops `path:line:  // ...` and `path:line:  * ...` matches — i.e. hits inside comments.
# Identical to the helper in lint-nextkit.sh, and for the same reason: doc comments legitimately
# discuss the things being banned.
strip_comments() {
    grep -vE '^[^:]*:[0-9]+:[[:space:]]*(//|\*)'
}

report() {
    local rule="$1" message="$2" hits="$3"
    echo "FAIL [$rule] $message"
    echo "$hits" | sed 's/^/    /'
    echo "::error::[$rule] $message"
    failed=1
}

# --- No force unwraps ---------------------------------------------------------
#
# The load-bearing pattern is the last one: a `!` immediately preceded by an identifier
# character, `)`, `]` or `?`, and not followed by `=`. That single expression covers `x!`,
# `foo()!`, `array[0]!`, `a?.b!`, and both `try!` and `as!` — the `y` and the `s` are word
# characters. Prefix negation (`!isEmpty`) and `!=` are excluded by construction.
#
# The sed stages before it are what make that pattern usable on real Swift: escaped quotes,
# then raw strings, then ordinary string literals, then trailing comments, are neutralised so a
# `!` inside a message cannot be mistaken for code. The last stage rewrites implicitly-unwrapped
# type annotations (`var label: UILabel!`) to a token with no `!` in it — constrained to types
# that start uppercase or with `[` or `(`, because without that constraint it also swallowed
# `save(task: cached!)`, which is a genuine violation.
#
# Known limitation, stated rather than papered over: the body lines of a multi-line `"""`
# literal are not stripped, so a `!` preceded by a word character inside one would be a false
# positive. There are none today.
unwraps=$(
    grep -rn --include='*.swift' -e '!' "${SHIPPED[@]}" 2>/dev/null \
    | strip_comments \
    | sed -E \
        -e 's/\\"/@/g' \
        -e 's/#?"""/@@@/g' \
        -e 's/#"[^"]*"#/""/g' \
        -e 's/"[^"]*"/""/g' \
        -e 's@//.*@@' \
        -e 's/:[[:space:]]*(any[[:space:]]+|some[[:space:]]+)?(\[[^][]*\]|\([^()]*\)|[A-Z][A-Za-z0-9_.]*(<[^<>]*>)?(\[[^][]*\])?)\??!/: IUO/g' \
    | grep -E '[[:alnum:]_)]!|\]!|\?!' \
    | grep -vE '[[:alnum:]_)]!=|\]!=|\?!='
)

if [ -n "$unwraps" ]; then
    report force-unwrap "Shipped code must not force unwrap, force try or force cast. Handle the absence, or explain the crash." "$unwraps"
fi

# --- No networking ------------------------------------------------------------
#
# `Data(contentsOf:)` and `String(contentsOf:)` are here because both accept an http URL. NEXT
# uses neither; the widget snapshot is read through FileManager precisely so this list needs no
# exception.
NETWORK_SYMBOLS=(
    'import[[:space:]]+Network'
    'import[[:space:]]+CFNetwork'
    'import[[:space:]]+WebKit'
    'import[[:space:]]+SafariServices'
    'URLSession'
    'URLRequest'
    'URLProtocol'
    'NSURLConnection'
    'WKWebView'
    'CFSocket'
    'Data\(contentsOf:'
    'String\(contentsOf:'
)

for symbol in "${NETWORK_SYMBOLS[@]}"; do
    hits=$(grep -rnE "$symbol" --include='*.swift' "${SHIPPED[@]}" 2>/dev/null | strip_comments)
    if [ -n "$hits" ]; then
        report no-networking "NEXT does not make network requests. Found: $symbol" "$hits"
    fi
done

# --- No third-party dependency ------------------------------------------------
#
# D-010. Also the "no unnecessary SDKs" line on the release checklist: a package added here is
# code shipping in the binary that nobody in this repository reviewed.
hits=$(grep -nE '^[[:space:]]*\.package\(' NextKit/Package.swift 2>/dev/null)
if [ -n "$hits" ]; then
    report D-010 "NextKit must declare no external package dependency." "$hits"
fi

if [ "$failed" -eq 0 ]; then
    echo "OK — no force unwraps, no networking symbol, no external dependency in shipped code."
fi

exit "$failed"
