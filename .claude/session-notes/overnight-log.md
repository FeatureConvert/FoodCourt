# Overnight autonomous session log

Robert went to bed ~01:57 (2026-08-12), granted full autonomous control for ~8h: keep doing
QOL/bug-fix/balance passes, log open questions rather than blocking on them, don't spend money
on credits. This file was reorganized once near the end of the session for a cleaner read -
the git commits themselves are the authoritative record of what changed.

## TL;DR

9 commits shipped and pushed to both devices since Robert went to bed (6 overnight + 3 first thing
this morning once he was back and answered questions). Full suite + the long PrestigeScalingTests
simulation stayed green throughout. One question still genuinely open (Carnival Pass - needs
Robert to test his device); everything else got a real answer and was acted on.

## Resolved this morning (Robert answered directly, no longer open)

1. **Venue 5→6 unlock gap** - Robert chose "dial back just the top of the curve." Discounted the
   final venue's unlockCost 30% off the raw escalation (`3890262`), left `venueEscalation` itself
   untouched. Verified with a full PrestigeScalingTests run: the gap's share of total cycle time
   came down from a 33-47% range (worst case 47%) to a tighter 33-38% range across all four
   cycles, with overall cycle lengths unchanged.

3. **BoostState/ActiveQuest hardening** - Robert said do it now. Hardened both (`bfce3f3`) with
   conservative, non-exploitable fallbacks: a corrupt/incomplete boost decodes as already-expired
   and inert; a corrupt/incomplete quest decodes as permanently unfinishable (target pinned just
   above whatever progress it got). Neither can hand the player something they didn't earn.
   Added `testCorruptBoostAndQuestDecodeAsInertRatherThanThrowingOrGrantingSomething`.

5. **"Franchise" vs "Prestige" naming** - Robert confirmed "Franchise." Swept all 5+ remaining
   "Prestige" strings (`105d51b`): two RootView nudge toasts, RoadmapView's group header + item
   title, four Achievements detail strings. Internal identifiers (IntroKey.prestige, `prestige_N`
   ids, the `prestigeCount` property) deliberately left alone - copy sweep, not a symbol rename.

## Still open

2. **Carnival Pass button report.** Still unresolved - Robert hasn't checked yet whether other
   Shop purchases work on his device. I traced the whole code path (tap → `purchasePremiumPass()`
   → `store.purchase()` → StoreKit → grant → `unlockFestivalPremium()`) and it's structurally
   identical to every working purchase - no bug found by reading. Added
   `testCarnivalPassUnlocksPremiumFestivalTrack` (StoreTests.swift) but couldn't run it for real:
   `xcodebuild test` from the CLI always skips StoreKit tests (needs Xcode's own GUI test runner -
   a pre-existing, documented limitation). If NO Shop purchase works, it's likely an App Store
   Connect/provisioning issue (needs Robert's access). If only Carnival Pass fails, there's a real
   narrow bug still to find.

4. **HUD badge row has no horizontal scroll** (pre-existing, not something introduced this
   session). 2 new badges (errand/Face-Off countdowns) were added to a row that was already a
   plain HStack + Spacer with no ScrollView. Up to 8 badges could theoretically be active at once
   now (contract, happy hour, VIP, mogul, errand, Face-Off, N boosts) - overflow risk on an actual
   iPad still unverified (no iPad simulator access grantable overnight; only iPhone simulators
   were already authorized in this session). Worth an eyeball on a real iPad if the HUD ever
   looks cramped with a lot going on.

## Shipped overnight (chronological, each batch tested + pushed to both devices)

1. **`714d80b`** — Fixed equipped venue skins not applying anywhere except the venue stage art
   itself. `VenuePalette.of(theme, skin:)` was called with no `skin:` argument in
   `StationListView`'s station cards, `RootView`'s background gradient, and `VenueSelectView`'s
   venue rows - only `VenueStageView` passed it correctly. A bought-and-equipped skin only ever
   showed up on the stage, nowhere else. Also gave Signature Dish crowning its missing
   confirmation sound (had haptics, no `sound.play`, unlike every comparable action). Visually
   confirmed the fix later on-simulator (background/buttons/Venues-tab row all correctly switch
   to neon purple/green once equipped).

2. **`b9fed66`** — `choosePerk()` had no idempotency guard: a double-tap (or a second tap landing
   in the 0.55s confirm-to-dismiss window) silently burned a second one of the run's four precious
   perk choices. Fixed + regression test added. Also: `SheetScaffold`'s close button and
   `IntroBanner`'s dismiss button (used on every modal / ~15+ banners) had no
   `accessibilityLabel`, unlike every other icon-only button in the app. And "Restore Purchases"
   had no re-entry guard, unlike every purchase button (which disables itself mid-transaction).

3. **`6a439f7`** — Guarded two station-index lookups (`CollectionView.placementLabel`, the
   catering-order requirements list in `QuestsView`) that subscripted `Balance.venue(_).stations`
   with a PERSISTED index rather than a catalog-derived one. `reconcileWithCatalog()` only grows
   a save's station arrays, never shrinks them, so this can't fire with today's catalog - but
   would crash on a save from a future catalog edit that removes/reorders a station. No behavior
   change today, just a safety net for later.

4. **`258bf7d`** — Verified (not fixed - it was already correct) that an exhausted Legacy tree
   (every perk maxed out) still safely resolves `pendingLegacyPerkOffer` to nil, even though the
   raw "owed" count stays positive forever past that point. Added a regression test to lock the
   invariant in, since it's an easy one to accidentally break later.

5. **`4e07414`** — Hardened `VenueState`, `TutorialState`, and `FestivalState` against missing
   save fields (see open question #3 for the two siblings NOT touched). These three, unlike
   `GameState`/`StationState`/`Entitlements`/~10 others, still used the synthesized `Decodable`,
   which throws on any missing key instead of falling back to the field's own declared default -
   completing an already-established pattern, not introducing a new one. Added a test decoding
   `"{}"` for each and confirming defaults land instead of throwing. Confirmed clean against the
   full suite AND a full multi-hour `PrestigeScalingTests` run (deep save-state churn under real
   simulated play).

6. **`51d1bec`** — Fixed one factual copy bug: the "Consider your first Legacy" goal string
   claimed "Trade your stars and research," but `legacyReset()` explicitly leaves research
   untouched (its own code comment says "RESEARCH SURVIVES") - every other mention of this
   already got it right. Also verified essentially every other numeric claim in player-facing
   copy against its source formula (perks, milestones, research, legacy, contracts, league,
   festival, recipes, errands, VIP/Mogul, the 12-product IAP catalog) - all correct, no other
   fixes needed.

7. Also added `c4e38b4` (Carnival Pass purchase test coverage, see open question #2) before bed
   was mentioned - included here for completeness since it's part of the same investigation.

8. **`105d51b`, `3890262`, `bfce3f3`** — the three items resolved this morning once Robert was
   back; see "Resolved this morning" above for detail.

## What was surveyed and came back clean (no action needed)

- Legacy tree, Contracts, Kitchen Tools/Gold Spatula, Tutorial edge cases, push notification
  cancellation, Game Center leaderboards - all wired correctly, nothing dead or duplicated.
- Crash-risk sweep: zero live force-unwraps or `try!` anywhere (prior passes already cleaned
  those up); NaN/overflow guards from earlier fixes all still hold.
- Race conditions, empty states, date/timezone edge cases, off-by-one boundary math: nothing
  reachable found.

## Rules that governed tonight's work
- Ship directly: bug fixes, QOL matching already-approved patterns, test coverage, perf fixes.
- Don't ship without flagging first: economy/pricing/drop-rate/pacing number changes.
- No purchases, no paid API/cloud usage.
- Every batch: build + test (full suite) + commit + push to both devices before moving on.
