#!/usr/bin/env bash
#
# Enforces the two architectural invariants that keep NextKit testable off-device.
#
#   D-002  NextKit depends on Foundation and nothing else. No Apple UI framework, no
#          persistence framework, no third-party package. If it ever needs one, the design
#          is wrong — the dependency belongs in NextApp, behind a protocol.
#
#   D-007  NextKit never reads the clock or mints an identifier. Both are injected. A hidden
#          Date() makes every deadline test time-dependent and therefore dishonest.
#
# Doc comments legitimately mention these names, so comment lines are excluded.
#
# Run locally:  bash scripts/lint-nextkit.sh

set -uo pipefail

SRC="NextKit/Sources"
failed=0

if [ ! -d "$SRC" ]; then
    echo "error: $SRC not found. Run this from the repository root."
    exit 1
fi

# Drops `path:line:  // ...` and `path:line:  * ...` matches — i.e. hits inside comments.
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

# --- D-002: forbidden imports -------------------------------------------------
FORBIDDEN_IMPORTS=(
    SwiftUI UIKit AppKit SwiftData CoreData WidgetKit StoreKit
    UserNotifications CoreHaptics Observation
)

for module in "${FORBIDDEN_IMPORTS[@]}"; do
    hits=$(grep -rnE "^[[:space:]]*import[[:space:]]+${module}([[:space:]]|$)" \
        --include='*.swift' "$SRC" 2>/dev/null | strip_comments)
    if [ -n "$hits" ]; then
        report D-002 "NextKit must not import $module — it belongs in NextApp, behind a protocol." "$hits"
    fi
done

# --- D-007: no ambient clock or identity --------------------------------------
hits=$(grep -rnE '\bDate\(\)' --include='*.swift' "$SRC" 2>/dev/null | strip_comments)
if [ -n "$hits" ]; then
    report D-007 "NextKit must not call Date(). Take 'now' as a parameter instead." "$hits"
fi

hits=$(grep -rnE '\bUUID\(\)' --include='*.swift' "$SRC" 2>/dev/null | strip_comments)
if [ -n "$hits" ]; then
    report D-007 "NextKit must not call UUID(). Identifiers are minted by an IDProvider at the app boundary." "$hits"
fi

if [ "$failed" -eq 0 ]; then
    echo "OK — NextKit purity invariants hold (D-002, D-007)."
fi

exit "$failed"
