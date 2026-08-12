# Overnight autonomous session log

Robert went to bed ~01:57, granted full autonomous control for ~8h: keep doing QOL/bug-fix/balance
passes, log open questions rather than blocking on them, don't spend money on credits.

## Open questions for Robert (not yet decided/implemented)

1. **Venue 5→6 unlock gap dominates every prestige cycle.** In every simulated cycle, opening the
   last venue (Food Truck Rally) alone eats 33-47% of that cycle's total duration (cycle 0: 7h54m
   of 17h6m; cycles 1-3: 3-4h of 8.5-10.5h). The venueEscalation=1.8 formula is mathematically
   identical at every step by design (Balance.swift VenueSpec.unlockCost/venueEscalation docs -
   deliberately upward-sloping to push a plateaued player toward prestige), but the doc comment's
   own tuning data only shows gaps through venue 3-4, never the venue 5-6 tail specifically - so
   this compounding endpoint may never have been eyeballed. NOT changed - this is a real economy
   number with wide blast radius, needs Robert's taste-check, not a unilateral 3am change.
   Data: see chat transcript ~01:56 for the full per-cycle table.

## Shipped this session (before bed)

- Second QOL/perf pass: batched saves in bulk-claim methods (was up to 90 synchronous full-state
  JSON writes per tap), cloud-conflict tap-to-confirm, staff list sorts benched-first, 2 more
  .lineLimit(1) fixes, onboarding banners for the 6 bulk-action buttons, station-modifiers caching
  (advance() populates a cache the UI reads instead of recomputing), HUD badges for errands/Face-Offs.
  All committed + pushed to both devices.
- Added missing StoreTests coverage for Carnival Pass purchase (testCarnivalPassUnlocksPremiumFestivalTrack)
  while investigating Robert's "Carnival Pass button does nothing" report. Code path traced
  end-to-end, structurally identical to working purchases, no bug found by reading. Could not
  verify real StoreKit behavior from CLI (xcodebuild test always skips StoreTests - needs Xcode's
  own test runner). Robert wasn't sure if OTHER Shop purchases work either - open question, see below.

## Open questions (bugs, not balance - still worth a real answer from Robert)

2. **Carnival Pass button report.** Does ANY Shop tab purchase actually work on Robert's device
   right now? If none do, likely App Store Connect/provisioning (needs his access, not code). If
   only Carnival Pass fails, there's a real narrow bug still to find.

## Shipped overnight (Robert asleep, full autonomy granted ~01:57)

- Fixed equipped venue skins not applying anywhere except the venue stage art itself
  (VenuePalette.of(theme, skin:) was called with no skin argument in StationListView's station
  cards, RootView's background gradient, and VenueSelectView's venue rows - only VenueStageView
  passed it correctly). A player who bought and equipped a skin would see it on the stage but
  everywhere else stayed "classic". Also added the missing confirmation sound to Signature Dish
  crowning (had haptics, no sound.play, unlike every comparable action). Committed 714d80b,
  pushed to both devices.
- Ran two background bug-hunt surveys (Legacy/Contracts/Tools/Cosmetics/Sound/Tutorial/
  Notifications; and Formatting/race-conditions/empty-states/accessibility/date-edge-cases).
  First one found the skin bug above plus a low-confidence Legacy-tree "permanently owed perk
  pick past level 13" note (not acted on - no reproduced failure, just a hypothetical future
  landmine if code ever branches on the raw owed count instead of the derived offer array;
  worth a second look if Legacy levels ever get easier to reach in bulk). Second survey still
  running as of this note.

- Second bug-hunt survey found and fixed: perk double-tap could burn a second precious choice
  (choosePerk had no idempotency guard - fixed + regression test added), SheetScaffold close
  button and IntroBanner dismiss button had no accessibilityLabel (VoiceOver users hit unlabeled
  controls on the first sheet they open), Restore Purchases had no re-entry guard unlike every
  purchase button. Committed b9fed66, pushed to both devices.
  Low-confidence note not acted on: Notifications.swift's Happy Hour reminder compares against
  the reminder time (start-15min) not the event itself, so in the 15 min right before Happy Hour
  starts the notification silently skips to tomorrow instead of firing for tonight. Arguably
  intended (can't schedule in the past) - worth a decision from Robert either way, not a clear bug.

## Rules for tonight
- Ship: bug fixes, QOL matching already-approved patterns, test coverage, performance fixes.
- Don't ship without flagging: economy/pricing/drop-rate/pacing number changes - log as a question instead.
- No purchases, no paid API/cloud usage.
- Build+test+commit in small verified batches; push to both devices periodically.
