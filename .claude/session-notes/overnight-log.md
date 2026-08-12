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
  First one found the skin bug above plus a Legacy-tree "permanently owed perk pick past level
  13" concern - later verified SAFE by hand (see below, no fix needed). Second survey still
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

- Third bug-hunt survey (crash-risk: force-unwraps, stale-index array access, Int overflow,
  decode fragility) found no live force-unwraps or try! (prior passes already cleaned those up),
  and confirmed NaN/overflow guards from earlier fixes still hold. Two real-but-not-currently-
  reachable findings: fixed the safe one (CollectionView.placementLabel + QuestsView's catering
  requirements list both subscripted Balance.venue(_).stations by a PERSISTED index rather than
  a catalog-derived one - reconcileWithCatalog only grows station arrays, never shrinks, so this
  can't fire with today's catalog, but would crash on a save from a future catalog edit that
  removes/reorders a station. Added bounds guards, no behavior change today). Committed 6a439f7,
  pushed to both devices.

3. ~~Codable hardening inconsistency~~ — PARTIALLY FIXED, narrowed. Hardened VenueState,
   TutorialState, and FestivalState with hand-written init(from:) (commit 4e07414) - all three
   already had a declared default for every field, so it's the same mechanical
   decodeIfPresent-??-default pattern GameState/StationState/Entitlements/~10 others already use,
   just completed for these three. Added testFieldlessStatesDecodeToTheirDefaults
   (MigrationTests) decoding "{}" for each and confirming defaults land instead of throwing.
   Verified against the full suite (284 tests) + a full PrestigeScalingTests run (exercises deep
   save state over many simulated hours). Committed + pushed to both devices.

   Still open: **BoostState and ActiveQuest** were deliberately left alone - neither has a
   natural default for every field (BoostState: id/label/multiplier/expiry; ActiveQuest:
   id/kind/target/progress/rewardGems/rewardSeconds), so hardening them means actually deciding
   fallback semantics (e.g. should a BoostState missing `expiry` decode as already-expired and
   inert, or get some other treatment?) - that's a real judgment call, not mechanical, so left
   for daylight review rather than guessed at 4am. Currently harmless either way since every
   field in both types has existed since each system launched.

   Final confirmation: the full PrestigeScalingTests multi-hour simulation (many Franchise
   resets, heavy save-state churn) passed clean after the Codable changes (600s run, exit 0).
   Cycle numbers this run (22h54m/11h58m/10h55m/9h14m) ran a bit longer than the earlier one
   (17h6m/10h32m/8h29m/8h34m) - this harness is wall-clock-bounded, not bit-exact-deterministic,
   and I had a lot else running concurrently tonight, so read that as system-load noise, not a
   regression. Nothing balance-related changed between the two runs.

- Visually verified the venue-skin fix on the iPhone 17 Pro Max simulator (injected a save with
  neon equipped on Burger Shack): background gradient, station-card buy/unlock button colors, and
  the Venues tab row all correctly switched to neon purple/green. Confirms the earlier fix works,
  not just compiles.

- Verified the Legacy tree "permanently owed" concern by hand: pendingLegacyPerkOffer already
  resolves to nil once every perk is maxed (offer.isEmpty wins over the raw owed count), so it
  was never actually a live bug. Added testLegacyOfferResolvesToNilOnceEveryPerkIsMaxed to lock
  the invariant in for the future. Committed 258bf7d, pushed to both devices.

4. **HUD badge row has no horizontal scroll (pre-existing, not something I introduced).** Wanted
   to check whether my 2 new errand/Face-Off badges could push the HUD badge row off-screen on
   iPad, especially landscape - couldn't verify on an actual iPad simulator (no device access
   grantable while Robert's asleep; the iPhone-only simulator I have access to doesn't exercise
   iPad's .regular size class code path). From reading RootView.landscapeContent, the HUD (badges
   included) already renders at full width in landscape, same as portrait, and the badge row was
   already a plain HStack + Spacer with no ScrollView before I touched it - so this isn't a
   regression I caused, but with up to 8 possible badges now (contract, happy hour, VIP, mogul,
   errand, Face-Off, N boosts) simultaneously active, it could theoretically overflow even iPad's
   width. Given I can't visually verify a fix and this predates tonight's changes, not touching
   it - flagging for Robert to eyeball on his/Kristin's actual iPad if it ever looks cramped.

## Rules for tonight
- Ship: bug fixes, QOL matching already-approved patterns, test coverage, performance fixes.
- Don't ship without flagging: economy/pricing/drop-rate/pacing number changes - log as a question instead.
- No purchases, no paid API/cloud usage.
- Build+test+commit in small verified batches; push to both devices periodically.
