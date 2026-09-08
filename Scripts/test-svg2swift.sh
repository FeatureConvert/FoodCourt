#!/bin/bash
# Regression test for Scripts/svg2swift.swift.
#
#     ./Scripts/test-svg2swift.sh            # check against the committed goldens
#     ./Scripts/test-svg2swift.sh --update   # accept current output as the new goldens
#
# The converter emits geometry, and geometry breaks quietly: an arc that bulges the wrong way
# or a transform composed in the wrong order still produces valid Swift that compiles and runs.
# Nothing else in the repo covers this script - it is a dev tool, not part of the app target,
# so the app's XCTest suite never touches it. Golden files are the cheap way to notice.
#
# The fixtures are not decorative. Between them they exercise every feature the script's header
# claims, and each was checked once by hand against an independent computation before being
# frozen here:
#
#   shapes.svg               path curves, an elliptical arc, quadratics with smooth continuation,
#                            relative commands, rect with corner radii, circle, ellipse, line,
#                            polygon, polyline, nested translate + rotate-about-a-point, inline
#                            `style` beating a presentation attribute, group opacity inheritance,
#                            and a <defs> block that must be skipped
#   paint-and-transforms.svg viewBox with a non-zero origin, rgb() and rgba(), #rgb shorthand,
#                            an unknown colour name falling back with a warning, skewX, skewY,
#                            matrix, fill-rule=evenodd, explicit stroke-linecap/linejoin, and a
#                            stroke width that must be scaled by its group's transform
#
# If a diff shows up, read it before running --update. A changed number here means the geometry
# the game draws changed.
set -euo pipefail
cd "$(dirname "$0")/.."

FIXTURES="Scripts/svg2swift-fixtures"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

status=0
check() {
    local svg="$1" name="$2"
    local expected="$FIXTURES/$(basename "$svg" .svg).expected.swift"
    local actual
    actual="$(mktemp)"

    # stderr carries the deliberate warnings (unsupported <defs>, unknown colour); the golden
    # covers generated code, so warnings are dropped here rather than baked into the fixture.
    swift Scripts/svg2swift.swift "$svg" "$name" > "$actual" 2>/dev/null

    if $UPDATE; then
        mv "$actual" "$expected"
        echo "updated  $expected"
        return
    fi

    if diff -u "$expected" "$actual" > /dev/null; then
        echo "ok       $(basename "$svg")"
    else
        echo "FAILED   $(basename "$svg")"
        diff -u "$expected" "$actual" | head -40
        status=1
    fi
    rm -f "$actual"
}

check "$FIXTURES/shapes.svg" ShapesFixtureArt
check "$FIXTURES/paint-and-transforms.svg" PaintFixtureArt

if [[ $status -eq 0 ]]; then
    echo "svg2swift: goldens match"
else
    echo "svg2swift: output changed - review the diff above, then --update if intended"
fi
exit $status
