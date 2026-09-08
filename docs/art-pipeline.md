# Authoring art

All art in this game is vector, drawn in code, with **no bundled image assets** — the same
principle `SoundService` follows for audio (every sound is synthesized at launch; nothing is
bundled). That is deliberate: no licensing surface, no App Store payload, no `@2x`/`@3x`
variants, and every asset recolours per venue theme and scales to any size for free.

This document is about how to add to it without hand-transcribing Bezier control points.

## The old loop, and why it was a bottleneck

`Sources/UI/Art` was built by reading design SVGs and retyping their geometry as Swift — see
`CoinBurst.swift`, which still says "transcribed from `fx-coin-sparkle.svg`". None of those
source SVGs are in the repo. That made art slow to add, silently wrong when a number was
mistyped, and impossible to re-run when the artwork changed.

## The current loop

```
Figma / Illustrator  →  export SVG  →  Scripts/svg2swift.swift  →  Sources/UI/Art/*.swift
```

```bash
swift Scripts/svg2swift.swift ~/Desktop/ramen-bowl.svg RamenBowlArt \
    > Sources/UI/Art/RamenBowlArt.swift
```

The generated view is a `Canvas` in the same idiom as the hand-written art: a `p(x, y)` helper
maps the design frame onto the view's bounds, `w(_:)` scales stroke widths off width alone, and
the whole thing is `.accessibilityHidden(true)`. It has no intrinsic size — give it a `.frame`.

Transforms are **baked into the emitted coordinates**, so the output is a flat list of paths
with no matrix arithmetic left at runtime.

### What the converter handles

| | |
|---|---|
| Elements | `path`, `circle`, `ellipse`, `rect` (incl. `rx`/`ry`), `line`, `polygon`, `polyline`, `g` |
| Path data | `M m L l H h V v C c S s Q q T t A a Z z`, including elliptical arcs |
| Transforms | `translate`, `scale`, `rotate` (incl. about a point), `skewX`, `skewY`, `matrix` |
| Paint | `fill`, `stroke`, `stroke-width`, `opacity`, `fill-opacity`, `stroke-opacity`, `stroke-linecap`, `stroke-linejoin`, `fill-rule`/`clip-rule`, named + `#rgb` + `#rrggbb` + `rgb()` colours |
| Cascade | presentation attributes, inline `style="..."` (which wins), inherited through `<g>` |

### What it does not handle

Gradients and patterns (`fill="url(#…)"`), `clipPath`, `mask`, `filter`, `text`, and
`<use>`/`<defs>` instancing. It **warns on stderr and skips** rather than emitting silently
wrong geometry — flatten or expand these in the design tool before exporting.

### Two things to set in the design tool

- **Round caps and joins.** The converter honours `stroke-linecap` / `stroke-linejoin` and
  defaults to SVG's own `butt`/`miter`. This game's art is round-capped throughout, so set
  round in the tool rather than expecting the house style to be imposed.
- **Outline colour.** Everything drawn here strokes itself with `#2B1D14` (`Theme.outline`).

### Keeping the converter honest

```bash
./Scripts/test-svg2swift.sh
```

Golden-file test over two fixtures in `Scripts/svg2swift-fixtures/`, which between them exercise
every feature the script's header claims — arcs, skew and matrix transforms, a viewBox with a
non-zero origin, `rgb()`, even-odd fill, explicit caps and joins, and a stroke width that has to
be scaled by its group's transform. Each was checked once by hand against an independent
computation before being frozen.

This exists because geometry breaks quietly: an arc that bulges the wrong way still produces
valid Swift that compiles and renders. Nothing else covers the script — it's a dev tool, outside
the app target, so the XCTest suite never touches it. Run it after any change to the converter;
a diff means the geometry the game draws changed. `--update` accepts new output as the goldens,
but read the diff first.

### After generating

The generated file is a starting point, not a finished asset. Two edits are usually worth making
by hand:

1. **Swap literal hex for theme tokens.** The converter emits `Color(hex: "#F5C242")` because
   that is what the SVG said; `Theme.coin` is what the codebase means. Palette-driven art (see
   `FoodSprite`, which recolours 12 food archetypes across 7 venue themes) should take its
   colours as parameters rather than baking them.
2. **Re-run it, don't patch it.** If the artwork changes, regenerate — the command is in a
   comment at the top of every generated file. Anything you want to survive regeneration belongs
   in a wrapper view, not in the generated one.

## Motion

Animated art follows one rule, established by the queue's idle bob and now also by the blink:
**animate a small layer over a cached figure; never redraw the figure.**

`CustomerSprite` is ~40 filled and stroked paths and is `.equatable()`, so it renders once and
stays cached. The bob is an `.offset(y:)` on that cached layer. The blink (`BlinkOverlay`) is a
separate four-path overlay quantised to three states, so a customer redraws its eyelids about six
times per blink rather than 30 times a second. Folding either into `CustomerSprite` would
invalidate its equatability and redraw the whole rig every frame.

Two supporting conventions:

- **One clock per view, shared.** `BobbingSprite` drives both the bob and the blink off a single
  `TimelineView` at 30fps. `BlinkingSprite` exists separately only for lone, short-lived figures
  (the golden VIP) that have no clock to borrow. Manager portraits deliberately do not blink —
  they sit in scrolling lists, and that is the same trade `ManagerRarityFrame` already declined
  for its rarity ring.
- **Reduce-motion drops the layer, it does not freeze it.** A parked wisp of steam is worse than
  no steam, and dropping the view avoids creating the timeline at all.

## Particles

`StageAtmosphere` draws the venue's steam and light motes. Every particle is a pure function of
`(index, time)` — no array to mutate, nothing to spawn or reap, no per-frame allocation. A
particle "respawns" because its progress wraps past 1.

**It is a `Canvas`, not SpriteKit, and that was a reversal.** The first version used
`SKEmitterNode`. Two things killed it: `SpriteView`'s backing stays opaque whatever you do to it
(`.allowsTransparency` in its options, `isOpaque` and `backgroundColor` on the `SKView`,
`backgroundColor` on the `SKScene`), so it painted a grey card over the room; and the budget
never justified an engine anyway — this stage is ~374×168pt carrying about two dozen particles,
while one queued customer already redraws ~40 paths. If a future effect genuinely needs
thousands of particles, revisit it, but expect to solve the transparency problem first.

## Testing art

Art is `accessibilityHidden` `Canvas` drawing with no assertable output, so the tests use two
techniques, both already established:

- **Contact sheets.** `SpriteSeedTests.testRenderContactSheet` and
  `SpriteBlinkTests.testRenderBlinkContactSheet` render a `VStack` of every variant with
  `ImageRenderer`, write a PNG to the simulator's tmp, and print the path. Not assertions — the
  real acceptance test is looking at it.
- **Pixel probes.** `SpriteBlinkTests` renders the sprite at a known size and samples design-space
  *regions* (never single pixels — a one-pixel probe beside a 1.7px catch-light is a coin flip
  against antialiasing). This is what actually proves `SpriteFaceRig` has not drifted from the
  geometry `CustomerSprite` draws from inline literals, since there is no shared constant to
  compare against.

## Sourcing art from outside

If you ever do bring in external art, two findings from a survey of the Unity Asset Store and the
CC0 ecosystem are worth recording:

- The **Unity Asset Store EULA is not engine-restricted** — §2.2.1(a) grants incorporation into
  "an electronic application or digital media", and Unity's own support article confirms assets
  are usable outside Unity. But the **Unity Companion License is**, and it covers most
  Unity-published free sample content (Dragon Crashers, Happy Harvest, the official Particle
  Pack). UCL content cannot ship in this app.
- For unambiguous licences prefer **Kenney.nl** (CC0, ships SVG) and **game-icons.net** (CC BY
  3.0, ~4,000 SVGs, strong prepared-food coverage — which is the one real gap in SF Symbols).
  Anything CC BY needs an in-app acknowledgements screen naming creator, source, licence, and
  the fact that it was modified.
