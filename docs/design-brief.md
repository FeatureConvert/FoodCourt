# Design brief: visual refresh (Aug 2026)

Owner verdict driving this brief: **"The graphics look simple and dated."** The game reads
as clean flat-vector but sparse — single-tone fills, no lighting or depth, stubby geometric
characters, a bare stage. The goal is a modern, juicy casual-game look while keeping the
one hard constraint that makes this codebase special:

**Every piece of art is programmatic SwiftUI vector code. There are no bundled image
assets, and that stays true.** The art lives in `Sources/UI/Art/` (`Icons.swift`,
`FoodSprite.swift`, `CustomerSprite.swift`, `VenueProps.swift`, `CoinBurst.swift`) plus
`Theme.swift` (palette/typography) — extend these, don't replace them with PNGs.

## Current-state diagnosis (from live screenshots)

- Flat single-tone fills everywhere; zero gradients, lighting, rim highlights, or texture.
- Venue stage: one flat backdrop color, a counter band, string lights, sign — no depth
  layers, no ambient life beyond the customer queue.
- Characters: paper-doll geometric (rect torso, circle head), charming but crude; no idle
  motion; outfits barely vary.
- Food icons: recognizable flat glyphs (fries, burger, soda, corn dog) with no dimension
  or serving context.
- Cards/buttons: uniform dark rounded rects; green CTA pills with a hard offset shadow —
  functional, dated.
- Progress rings: plain 2-color strokes.
- Tab bar: icons read as stock-SF-symbol despite the bespoke glyph pass.

## Work items

1. **Theme foundation first.** Add gradient tokens (2-3 stop, per-hue), an elevation
   system (layered soft shadows, not single hard offsets), and glow accents to
   `Theme.swift`. Every later item consumes these tokens — build once, apply everywhere.
2. **Venue stage depth + life.** Three parallax-ish layers (back wall with venue-specific
   props, counter, floor); warm gradient lighting falling from the string lights (give the
   bulbs a real glow bloom + subtle pulse); slow ambient steam wisps over hot stations;
   customers that shuffle/bob rather than statically stand. Per-venue palette identity and
   a subtle time-of-day tint driven by the clock.
3. **Character upgrade.** Better silhouettes (necks, shoulders, hands holding tools),
   venue-themed uniforms, 2-3 keyframe idle bob/blink loops, and a polish pass on the
   rarity portrait frames so Legendary actually glitters.
4. **Food with dimension.** Gradient shading + specular highlight on every food sprite,
   serving context (basket, tray, cup sleeve), consistent viewing angle across the set.
5. **Cards, buttons, rings.** Material treatment for station cards (subtle top-light
   gradient, per-station accent tint), pressed/disabled states for CTAs, progress rings
   that glow briefly on cycle completion, and the buy button's ×N badge made legible.
6. **Juice the moments.** Payout numbers pop-scale then drift; prestige gets a
   full-screen star-field beat (it's the biggest decision in the game — item 63 in
   docs/work-order.md adds the info side; this adds the drama); IAP grants and legendary
   arrivals get an upgraded confetti/spotlight treatment distinct from routine rewards.
7. **Tab bar + HUD identity.** Unify the five tab icons as a true bespoke set with a
   distinctive active state (fill + glow, not just tint); give the coin/gem HUD pills a
   metallic/crystalline read via gradients.
8. **App icon + launch screen** refreshed to match the new look, same code-drawn pipeline.

## Ground rules

- Sweep one surface at a time; screenshot before/after in the simulator each time and
  compare — never batch-restyle blind.
- Performance: the engine ticks at 20Hz with `TimelineView` interpolation on top. Ambient
  animation must be cheap (TimelineView/Canvas, no per-frame allocations, nothing running
  when its view is off-screen).
- Respect `prefers-reduced-motion` (`accessibilityReduceMotion`) — every ambient/juice
  animation needs a static fallback.
- Don't undo the accessibility-label work (docs/work-order.md items 40-42); labels and
  contrast survive every restyle.
- Dark-theme-first (the game forces dark mode); nothing may assume a light background.
- `xcodegen generate` only if project.yml changes; build + full test suite green before
  each commit; one commit per work item.
