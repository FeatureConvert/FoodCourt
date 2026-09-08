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
| Paint | `fill`, `stroke`, `stroke-width`, `opacity`, `fill-opacity`, `stroke-opacity`, `stroke-linecap`, `stroke-linejoin`, `fill-rule`/`clip-rule`, `#rgb`/`#rrggbb`/`#rrggbbaa`, `rgb()`/`rgba()` (colour-carried alpha composes with the opacity attributes rather than being dropped), and ~25 named colours (anything else warns and falls back to black) |
| Cascade | presentation attributes, inline `style="..."` (which wins), inherited through `<g>` |
| Visibility | `display="none"` / `visibility="hidden"` skip the element and its subtree — design tools emit these for switched-off layers |
| Dashes | `stroke-dasharray` / `stroke-dashoffset`, scaled with the frame like any other geometry |

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
`SKEmitterNode` and hit two problems. It would not composite — it painted an opaque grey card
over the room, and none of `.allowsTransparency`, `SKView.isOpaque`, `SKView.backgroundColor` or
`SKScene.backgroundColor` shifted it. (That is what was observed in this configuration, not proof
transparent `SpriteView` can't work; assume it's findable if you return to it.) The second
problem is the decisive one: the budget never justified an engine. Measured, this layer costs
0.069ms/frame against 0.346ms for the six customers in front of it. If some future effect really
does need thousands of particles, revisit — but two dozen soft circles is not that.

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

> **This is research, not legal advice, and it was not verified by a lawyer.** It came out of a
> survey of the Unity Asset Store and the CC0 ecosystem done in one sitting. Treat it as a
> starting point that tells you which questions to ask, not as clearance to ship anything. The
> per-pack licence that ships *inside* the download always governs, and it can be stricter than
> the storefront implies.

- **The Unity Asset Store EULA appears not to be engine-restricted.** §2.2.1(a) grants
  incorporation into "an electronic application or digital media" — wording that does not
  mention Unity — and Unity's own support article states assets are usable with other engines.
  Both were read directly rather than taken second-hand. That said, "appears" is doing real work
  here: it is a reading of contract text, not a ruling.
- **The Unity Companion License is engine-restricted**, and this is the trap worth remembering,
  because it disproportionately covers the *best* free content — Unity's own published samples.
  UCL grants use only in connection with software built under a Unity engine licence, so it
  cannot ship in a SwiftUI app. Check for it before getting attached to a pack.
- **Prefer unambiguous licences for anything load-bearing.** Kenney.nl is CC0 and ships SVG;
  game-icons.net is CC BY 3.0 with roughly 4,000 SVGs and good prepared-food coverage, which is
  the one real gap in SF Symbols. CC0 asks nothing of you; CC BY needs an in-app
  acknowledgements screen naming creator, source, licence, and that the work was modified.
- **Screenshot the licence at download time**, and keep a `CREDITS.md` mapping each asset to
  source, licence, URL and date. Free packs get delisted and terms get edited; the cheapest
  insurance is evidence of what it said on the day.

Worth weighing against all of the above: every attempt to find external art for this game
concluded that the code-drawn system already in `Sources/UI/Art` was the better answer. Adopting
outside art buys a licensing surface this project currently does not have at all.
