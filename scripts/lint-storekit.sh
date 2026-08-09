#!/usr/bin/env bash
#
# Keeps the NEXT+ product identifiers in `NextPlusProducts` and in `NextApp/NEXT.storekit`
# identical.
#
# Why this exists: a typo in a product identifier compiles, passes every test that uses the Swift
# constant, and is invisible until a real purchase fails to resolve against App Store Connect —
# which is the worst possible moment to discover it. The two lists are written by hand in two
# formats, so nothing but a check keeps them in step.
#
# Run locally:  bash scripts/lint-storekit.sh

set -uo pipefail

SWIFT_SOURCE="NextKit/Sources/NextKit/Monetisation/NextPlusProducts.swift"
STOREKIT_FILE="NextApp/NEXT.storekit"

for path in "$SWIFT_SOURCE" "$STOREKIT_FILE"; do
    if [ ! -f "$path" ]; then
        echo "error: $path not found. Run this from the repository root."
        exit 1
    fi
done

# Identifiers as Swift declares them: ProductID("com.nextapp.next.plus.monthly")
declared=$(grep -oE 'ProductID\("[^"]+"\)' "$SWIFT_SOURCE" \
    | sed -E 's/ProductID\("(.*)"\)/\1/' | sort -u)

# Identifiers as the store configuration declares them: "productID" : "com.nextapp..."
configured=$(grep -oE '"productID"[[:space:]]*:[[:space:]]*"[^"]+"' "$STOREKIT_FILE" \
    | sed -E 's/.*"productID"[[:space:]]*:[[:space:]]*"(.*)"/\1/' | sort -u)

if [ -z "$declared" ]; then
    echo "FAIL [storekit] no product identifiers found in $SWIFT_SOURCE"
    echo "::error::[storekit] no product identifiers found in $SWIFT_SOURCE"
    exit 1
fi

if [ "$declared" != "$configured" ]; then
    echo "FAIL [storekit] the Swift catalogue and $STOREKIT_FILE disagree."
    echo "  declared in Swift:"
    echo "$declared" | sed 's/^/    /'
    echo "  configured in .storekit:"
    echo "$configured" | sed 's/^/    /'
    echo "::error::[storekit] NextPlusProducts and NEXT.storekit declare different products."
    exit 1
fi

count=$(echo "$declared" | wc -l | tr -d ' ')
echo "OK — $count NEXT+ product identifiers match between Swift and the .storekit file."
exit 0
