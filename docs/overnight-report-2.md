# Overnight report #2 — the depth marathon (Aug 9, 2026)

Second autonomous night. **All ten depth systems shipped, plus the wife-requested
inventory system and perk rework.** 79 commits total in the repo, 220 tests green, zero
real money used anywhere (local StoreKit test config only), final build smoke-tested on
the simulator.

## Everything that shipped tonight (after the first report)

1. **Franchise Contracts** — pick 1 of 3 run modifiers after every reset, each a real
   trade (Double-Time, High Roller, Open Doors, Showtime, Night Owl, Investor Showcase),
   "Play It Straight" always offered. Badged on the HUD; run recap chains into the picker.
2. **Legacy tree** — every Legacy level pays its +20% AND one permanent perk pick (Seed
   Capital, Slow Cooker, Standing Night Shift, Crowd Favorite, Master Negotiator, with
   stack caps). Two Legacy-3 empires can now be genuinely different builds.
3. **Manager crews (synergies)** — five named crews; staff every member in one venue for
   +10-25% venue-wide. Live crew board on the Staff tab turns the bench into a hunt list.
4. **Station specialization** — Lv 500 perk tier that changes how a station *feels*:
   Batch Mode (×5 cycle/×6 payout), Rapid Fire, Tip Magnet, via a new `.tempo` effect.
5. **Season twists** — each carnival season carries one rotating gameplay modifier (Tap
   Frenzy / Overtime / Golden Week / Big Spender), badged with personal-best tier.
6. **Signature Dish (recipe fusion)** — fully 3-star a venue's set, crown one station for
   ×1.5, re-crownable anytime. The recipe album finally has an endgame.
7. **Food Court Face-Offs (expeditions)** — send your three best benched managers against
   a rival crew across three stake tiers; odds shown before committing, outcome fixed at
   departure, Grand tier can bring home an Epic recruit.
8. **Daily catering orders** — a composed multi-station order each day; the first goal
   that cares *which* counters run. Pays gems + income + tickets.
9. **Twist venues 6-7** — Midnight Diner (its stations earn at FULL offline rate) and
   Food Truck Rally (a rotating ×3 Daily Special truck). Old saves gain them
   automatically; "The Whole Court" achievement caps the venue track.
10. **Weekly Gauntlet (challenge mode)** — a ten-minute scored sprint on the live board
    under a weekly mutator; purse pays for beating your idle baseline, best-ever persists.

**Wife-requested, shipped in full:**
- **Kitchen Tools inventory** — seven items dropping from event moments (Rush 4%, VIP 3%,
  Face-Off win 20%, catering 12%), permanent once found, dupes convert to gems. The
  **GOLD SPATULA** is the rarest and best thing in the game — under 1% of already-rare
  drops (test-enforced), +25% profit everywhere +1s combo window, celebrated with the
  game's biggest moment. The tool shelf shows unfound tools as silhouettes: a visible chase.
- **Perk frequency fix** — four interactive choices per franchise run (was: unlimited,
  ~100+ interrupting sheets per patient run). Now "which four stations get a build?" is a
  strategy call that pairs with the run's Contract. Milestone auto-bonuses untouched.
- **Perk confirmation** — two-tap confirm (the established pattern) since choices are
  precious, plus "Decide later": the sheet is no longer un-dismissable, and a station
  keeps its offer.

Every system got the standard tutorial treatment: first-open IntroBanner, Help guide
section, and the established picker/celebration patterns. Balance passes ran alongside:
expedition purses trimmed against the bench-yield ledger; the award-proportional research
pricing self-absorbs the new star bonuses (bigger awards raise research budgets AND costs
together — that's the design working).

## Judgment calls to review (my numbers, all overridable)

1. Contract trade values (±25-80% swings) and the 2-of-6 rotating offer.
2. Legacy perk values and stack caps; Seed Capital capped at venue-2 price per stack.
3. Crew bonuses +10/+15/+25%; bond +2%/level at 1/3/7/14/30 days.
4. Tool effects and the four drop rates; Gold Spatula at weight 1/~109.
5. Gauntlet purse: 15 gems per baseline-multiple, cap 90/week.
6. Perk cap at exactly 4 (easy to change: `Balance.perkChoicesPerRun`).
7. Catering targets (~4h of each station's pace, 25 gems); Daily Special at ×3.
8. Twist venues share sibling prop art until the design pass (palettes are bespoke).

## PROMPTS — the final steps for everyone

### For a Sonnet High session (cleanup + coverage):
```
Read docs/overnight-report-2.md and docs/work-order.md in this repo. Two autonomous
sessions shipped ~30 systems; your job is consolidation, not features. 1) Write unit
tests for every judgment-call number in the report's list (contract trades, legacy perk
stacking, crew detection edge cases, tool drop table bounds, gauntlet purse math,
catering progress/expiry, daily-special rotation, diner offline split) - target +30
tests. 2) Sweep every Help/FAQ/IntroBanner string against the implemented mechanics for
drift. 3) Run the OVERNIGHT PROTOCOL's five verification passes from work-order.md
against the whole game. 4) Do NOT rebalance anything - log concerns as questions.
xcodegen generate if project.yml changed or files were added; xcodebuild -project
Fable.xcodeproj -scheme Fable -destination 'platform=iOS Simulator,name=iPhone 17 Pro
Max' build-for-testing / test-without-building green before every commit; no real money.
```

### For a Claude design session (the art pass):
```
Read docs/design-brief.md in this repo and execute the full remaining visual refresh of
Food Court Tycoon. Item 1's Theme depth tokens already shipped (Theme.topLight/
buttonLight/edgeLight) - build on them. Since the brief was written, the game gained
surfaces that need bespoke art, all in SwiftUI vector code (never image assets):
Sources/UI/Art/VenueProps.swift - the Midnight Diner and Food Truck Rally currently
share burger/taco prop sets and deserve their own (neon diner signage, parked trucks
with striped awnings); a Gold Spatula hero drawing for the tool-drop moment and tool
shelf (Sources/UI/Sheets/CollectionView.swift uses GlyphIcon placeholders); the Weekly
Gauntlet card (Sources/UI/Sheets/EventsView.swift) wants a stopwatch-urgency treatment;
prestige sign frames at 5/15/40 franchises (Sources/UI/VenueStageView.swift). Then the
original brief items: CustomerSprite silhouettes/uniforms/idle bob, FoodSprite per-item
shading, payout pop-scale + a prestige star-field moment in CoinBurst.swift, tab bar
active states + metallic HUD pills, app icon + launch screen last. One surface per
commit, before/after simulator screenshots every time, allocation-free animation,
respect accessibilityReduceMotion, keep all accessibility labels, tests green.
```

### For Robert (the only human steps):
1. Replace `SettingsView.privacyPolicyURL` with your real hosted policy; enter it in
   App Store Connect.
2. Create all 17 IAPs per docs/AppStoreConnect-IAP-Setup.md (unchanged tonight).
3. Run StoreKit tests once from Xcode (they skip on CLI).
4. Play it. Tonight's numbers are simulation-honest but hand-feel is yours to judge -
   the judgment-call list above is what to poke at. Your wife gets first Gold Spatula
   hunting rights.
