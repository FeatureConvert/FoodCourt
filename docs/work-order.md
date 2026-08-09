# Work order: full-review follow-up (Aug 2026)

You are working on **Food Court Tycoon**, a SwiftUI iOS idle-tycoon game in this repo
(`/Users/roberthouston/Documents/Fable`, bundle `com.fable.foodcourt`, branch `master`).
This document is the complete backlog from a three-part codebase review (code correctness,
economy/balance, UX/monetization/store-readiness). Work through it top to bottom — the
tiers are ordered by severity. Every item is self-contained: file, problem, fix, and how to
verify.

## Ground rules

- **Build/test**: `xcodegen generate` if project.yml changed, then
  `xcodebuild -project Fable.xcodeproj -scheme Fable -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build-for-testing` and `test-without-building`. The full suite must
  stay green after every tier.
- **Commit per tier** (or per logical group within a tier), message style matching
  `git log` — plain imperative summaries.
- **Items marked `DECISION`** involve a judgment call Robert has not signed off on.
  Do NOT silently pick a number. Ask him with the options listed, or if he has told you to
  proceed autonomously, use the stated default and flag it clearly in your summary as a
  choice he can override.
- **Never touch** the sqrt star formula, the staleness-tax curve, or the 2.4 research
  growth exponent — those were explicitly tuned and confirmed this month.
- The game has a Python economy-sim precedent: for any balance change, a quick simulation
  or back-of-envelope check in the commit message beats vibes.

---

## P0 — Crash and money-path bugs (do these first, no decisions needed)

### 1. Game Center score submission traps on huge earnings
`Sources/Core/GameCenterService.swift:25` — `let score = Int(min(coins, Double(Int.max)))`.
`Double(Int.max)` rounds **up** to 2^63 exactly, which is out of `Int64` range, so for any
save with `lifetimeEarnings >= 9.223e18` the `Int(...)` conversion is a fatal trap. This is
the same bug class as the recently fixed `Balance.totalStars` trap, and a corrupted save
repaired by the new decode clamp can still carry earnings near `Balance.maxSaneLifetimeEarnings`
(~1e31), so this is reachable in production the moment such a player opens the League sheet
(`Sources/UI/Sheets/EventsView.swift:334`).
**Fix**: clamp below the boundary, e.g. `Int(min(coins, 9.2e18))`, with a comment explaining
why `Double(Int.max)` itself is unsafe. **Test**: add to `Tests/FableTests/` — submitting is
not testable, but extract the clamp into a small pure helper (or test the expression) with
inputs `1e40`, `.infinity`, `Double(Int.max)`.

### 2. Local notifications silently die after every app relaunch
`Sources/Core/Notifications.swift:60` — `authStatus` starts `.notDetermined` in memory and is
**only** ever set inside the `requestAuthorization` callback. Nothing queries
`UNUserNotificationCenter.getNotificationSettings()`. So: player enables notifications
(works that session), kills the app, relaunches → `reschedule(for:)` at
`Sources/App/FableApp.swift:65` hits `guard authStatus == .authorized else { return }` and
schedules nothing, forever, until the player re-toggles the setting.
**Fix**: on `NotificationService.init()` (and/or at the top of `reschedule`), read the real
status via `getNotificationSettings` and update `authStatus`. Keep it async-safe
(`@MainActor` hop like the existing callback).
**Verify**: unit-test `NotificationPlanner` is already pure; for the service, manual check —
enable notifications, relaunch app in simulator, background it, confirm scheduled requests
exist (`center.pendingNotificationRequests`) via a debug print or breakpoint.

### 3. A paid purchase can be lost if it arrives before the engine attaches
`Sources/Store/StoreService.swift` — `FableApp` constructs `StoreService()` with `engine: nil`
and only calls `store.attach(engine:)` inside the root `.task`. `listenForTransactions()`
starts in `init`, so a `Transaction.updates` delivery in that window reaches
`grant(_:announce:)`, which does `guard let engine else { return }` — **but `finalize` still
calls `transaction.finish()`**. For a consumable (gems, Research Grant), finishing without
granting permanently eats the purchase.
**Fix** (pick the cleanest): in `finalize`, if `engine == nil`, do **not** finish or record
the transaction id — return and let StoreKit redeliver; or buffer the verified transaction
and drain the buffer in `attach(engine:)`. Do NOT restructure `FableApp`'s StateObject
setup to pass the engine into the initializer — `@StateObject` interdependence is fragile.
**Test**: `Tests/FableTests/StoreTests.swift` — construct `StoreService(engine: nil)`, drive
`grant` path if factored testably; at minimum assert the guard ordering via a refactor that
makes "should finish?" a pure function.

### 4. Cloud-save conflict detection is wrong for Legacy players
`Sources/Core/CloudSave.swift` `isAhead(_:of:)` compares `lifetimeStars` then
`lifetimeEarnings`. Two real failure modes:
- `GameEngine.legacyReset()` **zeroes `lifetimeStars` by design** — so the device that just
  did a Legacy reset looks strictly *behind* a stale second device, which then wins
  `reconcileOnLaunch` and can clobber the reset (or spuriously prompt a "restore your old
  save?" conflict that undoes a deliberate reset).
- Two saves both clamped by the corruption repair in `GameState.init(from:)`
  (`Sources/Core/GameState.swift:440`) tie exactly on both fields, so `isAhead` is false
  both ways and a genuinely different remote is silently ignored.
**Fix**: compare in order: `legacy.level` → `lifetimeStars` → `lifetimeEarnings` →
`prestigeCount` → total research ranks (`research.values.reduce(0,+)`). Keep it
`nonisolated static` and pure.
**Test**: extend `Tests/FableTests/` with cases: post-legacy-reset local vs pre-reset
remote (local must win); both-clamped saves differing in research (higher research wins);
untouched-vs-played unchanged behavior.

---

## P1 — Correctness and consistency bugs (small, safe, no decisions)

### 5. `automatedRate` omits the Legacy multiplier
`Sources/Core/StationMath.swift` `automatedRate` multiplies by star, VIP, and research
multipliers but **not** `Balance.legacyMultiplier(level:)`, while `globalMultiplier`
(`Sources/Core/GameState.swift:284`) includes it. Everything priced off `automatedRate` —
offline earnings, quest coin rewards, daily-reward coins, errand coins, time warps, golden
customer payouts — underpays a Legacy player relative to their live tick income.
**Fix**: add `* Balance.legacyMultiplier(level: legacy.level)` to `automatedRate`.
**Test**: in `EconomyTests`, a state with `legacy.level = 1` must have `automatedRate`
exactly `Balance.legacyMultiplier(level: 1)`× the same state at level 0.

### 6. Daily-reward coins bypass league score and earn-quests
`Sources/Core/DailyRewards.swift` `claim` does `state.coins += payout.coins;
state.lifetimeEarnings += ...; state.runEarnings += ...` directly, unlike every other grant
which goes through `GameEngine.addCoins` → `recordEarnings` (which also feeds
`state.league.score` and `.earn` quest progress). Inconsistent: quest rewards count toward
the league, daily rewards don't.
**Fix**: make `DailyRewards.claim` return the payout without applying coins, and have
`GameEngine.claimDaily()` apply them via `addCoins`; or add league/quest lines in place.
Preserve the existing gem/boost handling.
**Test**: claiming a daily coin reward increases `state.league.score` by the same amount.

### 7. "Purchases restored" toast shows even when restore fails
`Sources/Store/StoreService.swift` `restore()` sets `lastGrant = "Purchases restored"`
unconditionally, including when `AppStore.sync()` threw (user cancelled sign-in).
**Fix**: only set the success toast when sync didn't throw; on catch, set nothing (silent
cancel) — do not show an error for a user-cancelled sheet.

### 8. Unverified transactions redeliver an error toast forever
`Sources/Store/StoreService.swift` `finalize` — the `.unverified` branch shows an error and
never finishes the transaction, so StoreKit redelivers it every launch → the same "couldn't
be verified" toast on every launch, forever. **Fix**: keep never-granting, but finish the
unverified transaction after surfacing the error once (a transaction that fails the
signature check will never become verified by waiting). Add a comment explaining the choice.

### 9. Stale golden customer / station order survive a prestige
`Sources/Core/GameEngine.swift` — `prestige()` (:708) and `legacyReset()` (:750) clear
`lastServe`/`pendingBursts`/`lastBurstAt`/`combo` but not `golden` or `activeOrder`, unlike
`switchTo(venue:)` and `adoptCloudSave` which clear all of them. A pending "ORDER UP" for a
station on the wiped board can be fulfilled by the new board's station of the same index.
**Fix**: nil both out in `prestige()` and `legacyReset()`.

### 10. "Offline earnings are capped" notification fires for players who earn nothing offline
`Sources/Core/Notifications.swift` `NotificationPlanner.plan` appends `offline-cap-full`
unconditionally — a brand-new player with zero staffed stations (automatedRate 0, so zero
offline income) still gets "Come collect before you lose more."
**Fix**: only append when `state.automatedRate > 0`. **Test**: extend planner tests: fresh
`GameState.newGame()` must produce no `offline-cap-full` plan.

### 11. Remove dead code `GameState.station(_:_:)`
`Sources/Core/GameState.swift:302` — zero call sites in the codebase. Delete it.

### 12. `hireManager` lacks the bounds check `tap` has
`Sources/Core/GameEngine.swift:426` indexes `state.venues[venue].stations[index]` directly;
`tap(station:)` (:358) guards with `indices.contains`. All current callers are UI-driven and
safe, but add the same guard for consistency and crash-proofing.

### 13. Stale product count in the IAP setup doc
`docs/AppStoreConnect-IAP-Setup.md:136` — "None of the 12 products above" should be **13**
(the Research Grant row was added above but this line was missed). NOTE: superseded by
item 61's full 13 → 17 count sweep — do the count corrections once, as part of 61.

---

## P2 — Economy and balance (most items DECISION-gated — batch the questions to Robert)

### 14. `DECISION` — Legacy reset's core trade-off is not real
`Sources/Core/GameEngine.swift:751` `legacyReset()` zeroes `stars`/`lifetimeStars`/`research`
but **not `lifetimeEarnings`** — and `pendingStars` is computed from `lifetimeEarnings`
(`Balance.pendingStars`). So immediately after a Legacy reset the player can prestige once
(the board rebuild to `minimumLifetimeForPrestige` is trivial at their income) and get
essentially their entire star multiplier back. The only permanent cost is research. The doc
comment sells it as "trades away the accumulated star multiplier," which is not what happens.
`Tests/FableTests/FeatureTests.swift:1554-1573` asserts current behavior as intended.
**Options for Robert**: (a) also zero `lifetimeEarnings` in `legacyReset` so stars genuinely
restart (makes Legacy much more expensive — probably needs the legacy multiplier per level
raised to compensate); (b) keep mechanics, rewrite the doc comment + in-game Legacy copy
(`PrestigeView`, legacy alert) to honestly say "resets research, stars come back quickly";
(c) partial haircut (e.g. halve lifetimeEarnings). If (a), update the FeatureTests
assertions to the new intent.

### 15. `DECISION` — Same-effect research nodes have wildly inconsistent cost-per-percent
`Sources/Core/Research.swift` — among `globalProfit` nodes: `prep` ≈ 3,396★/% and `brand`
≈ 4,528★/%, but `franchise` ≈ 168★/% and `lockin` ≈ 270★/% — 15–27× cheaper for the identical
effect. `brand` alone is ~271,686★ (~36% of the whole 757K tree) for +60%, while its branch
sibling `franchise` gives +50% for 8,425★. The three growth retunes only moved the shared
exponent, never the per-node baseCosts.
**Options**: (a) re-derive baseCosts so cost-per-percent is roughly monotone with depth in
the tree (recommended; propose exact numbers to Robert with a table before editing); (b)
differentiate effects instead so cheap nodes give less. Whatever changes, keep rank-0 entry
costs of the cheapest nodes untouched (explicit prior decision) and re-run a quick
total-cost sum so the ~6-month completion target (~757K total) stays in the same ballpark.

### 16. `DECISION` — Legacy unlock threshold vs. the new research economy
`Balance.legacyUnlockLifetimeStars = 500` was set before research became a ~757K★/6-month
sink. Given item 14, the *real* price of Legacy is the research wipe — an early threshold
tempts players into wiping months of research for a small flat bonus. Ask Robert whether
500 lifetime stars is still the intended gate or should scale (e.g. also require N research
ranks or a higher star floor). Present the tension, don't pick silently.

### 17. Stale "Tycoon" achievement threshold
`Sources/Core/Achievements.swift` — `earn_3` (1e9 lifetime) completes two orders of
magnitude before the first prestige is even possible (`minimumLifetimeForPrestige = 1e11`).
The tier reads: 1e5 → 1e7 → 1e9, all trivially cleared pre-prestige.
**Fix**: rescale to something like 1e5 → 1e9 → 1e13 so the last tier lands post-first-
prestige. Flag the exact numbers chosen to Robert as tunable.

### 18. `DECISION` — Errand gems were never nerfed with every other gem source
`Sources/Core/Errands.swift` `gemsPerHour` (2/4/7/12 by rarity) was untouched by the
deliberate -30–50% pass on quests/achievements/festival/daily/league (commit `4308813`).
Two 12h slots of legendaries = up to 288 gems/day passively, which dwarfs the nerfed
sources. **Default if authorized**: cut ~40% to 1/2.5/4/7 (round: 1/2/4/7) matching the
pass; flag to Robert either way.

### 19. Grand Opening Bundle strictly dominates the Chest gem pack
`Sources/Store/StoreService.swift` — both $9.99: Chest = 1,200 gems; Grand Opening = 1,500
gems **plus** managers everywhere **plus** 72h ×2. A first-time $9.99 buyer should never
pick Chest. **Options**: raise Grand Opening to $14.99/$19.99, or cut its gems to ~800 so
it's a convenience bundle not a superset. Ask Robert; also update `Products.storekit` and
`docs/AppStoreConnect-IAP-Setup.md` price tables to match whatever he picks.

### 20. `DECISION` — Legendary Chef Crate vs Guest Chef price gap
Crate: $9.99 real money for a guaranteed legendary. Guest Chef
(`Sources/Core/GuestChef.swift`): 400 gems ≈ $3–4 for a guaranteed legendary weekly.
~2.5× price for the same headline outcome (pools differ slightly). Options: raise Guest
Chef to 600–800 gems, lower Crate to $4.99, or accept and differentiate copy ("any week,
instantly" vs "this week's pick"). Ask Robert.

### 21. `DECISION` — Three very different-value sinks all cost exactly 400 gems
Automate Venue (full venue staffing), Research Boost (+300★), Guest Chef (weekly legendary)
— identical 400-gem price for wildly different value. Propose a spread (e.g. Research Boost
250, Automate 400, Guest Chef 600) and ask.

### 22. Research Boost/Grant magnitude sanity-check
+300★ (400 gems) is 0.04% of the tree; +2,500★ ($9.99) is 0.33%. The code comments say
"buy back time, not completion" — deliberately small — but confirm with Robert that these
read as *worth buying* (they roughly equal a few days of early-tree stars, but are noise
against late-tree node costs of 10K–270K★). Option: scale grants with tree progress
(e.g. "+N% of your next affordable node") — bigger change, needs his sign-off.

### 23. `DECISION` — Gem staffing bypasses the staleness tax
Instant Manager (100 gems) and Automate Venue (400 gems) in `Sources/Store/GemSpend.swift`
ignore `costInflation`, while coin hires pay it (`GameEngine.managerCost`). A gem-rich
player sidesteps part of the tax's pressure. Plausibly an intentional monetization valve —
ask Robert: keep (and document in code comment), or scale gem costs by a mild inflation
factor.

### 24. Streak milestones dead-end at day 100 against a ~180-day arc
`Sources/Core/DailyRewards.swift` `streakMilestones` caps at (100, 650). With the research
arc now ~6 months, add milestones at 150, 200, 250, 300 (suggest 650-gem steps scaling
~1.5×; flag exact numbers to Robert). Cheap content, real retention.

### 25. `DECISION` — Prestige-count achievements vs the patient cadence
`prestige_2` (5) / `prestige_3` (15) predate the staleness tax's 3–7-day intended cadence:
15 prestiges ≈ 6–15 weeks, which may now be fine — or not. Ask Robert whether 5/15 still
matches the cadence he wants rewarded, or bump to e.g. 10/30.

### 26. "Own 50 managers" achievement may be unreachable in practice
`staff_3` counts live `state.managers.count`, but `prestige()` wipes all non-premium
managers. Under patient cadence, hitting 50 *simultaneous* managers means staffing ~all 30
stations plus 20 premium bench members, or stalling prestige. Check the real numbers
(30 stations across 5 venues — count the specs), then either lower to 30–35, or count a new
persistent `lifetimeManagersHired` stat instead (schema addition — decode with `?? 0`).
Recommend the lifetime-stat approach; confirm with Robert.

### 27. Re-simulate the aggregate gem economy once 18/24/25 land
The individual -30–50% cuts were never re-summed against the full sink catalog over a
6-month arc. Extend the scratchpad sim approach (see `prestige_staleness.py` methodology in
the session notes; rebuild a simple weekly ledger in Python if not present): weekly gem
income (quests + achievements + festival + league + daily + streak + errands) vs. priced
sinks. Deliver the table to Robert with any glaring surplus/deficit flagged. No code change
without his call.

---

## P3 — Copy, onboarding, and UX gaps

### 28. WelcomeView actively teaches the anti-pattern the staleness tax punishes
`Sources/UI/WelcomeView.swift:15` — final tip says franchise "once you've built out
everything you can." The intended cadence is now reset-every-3–7-days; the tax exists
precisely to punish "wait until maxed." This is the first thing every new player reads.
**Fix**: rewrite the tip, e.g. "Franchising resets the board for a permanent profit bonus —
don't sit on a maxed-out board too long; costs creep up the longer you wait." Keep tone.

### 29. HelpView states wrong numbers for combo and Rush Hour
`Sources/UI/Sheets/HelpView.swift:83-88` — says combo window is "a second and a half"
(actual `ActivePlay.comboWindow = 2.5`) and Rush cooldown "20-minute" (actual
`rushCooldownMinutes = 30`). Fix the copy; better, interpolate the constants so it can't
drift again.

### 30. HelpView franchising guidance contradicts the staleness tax
`HelpView.swift:112-118` — never mentions cost inflation and still implies "franchise
whenever you've built out everything." Rewrite to explain: costs inflate on a stale board
after ~8h grace, resetting clears it, a few days per board is the sweet spot.

### 31. HelpView sets no research-pacing expectation
Add a line to the research entry: the tree is a long-arc goal measured in months, not
something to finish in a run.

### 32. HelpView star copy is now wrong for purchased stars
`HelpView.swift:112-118` says "Every star is +2% profit forever… Stars are also the currency
for research." Research Grant/Boost stars are spendable-only (never touch `lifetimeStars`),
so a buyer expecting their % to rise will feel cheated — a genuine paid-purchase-clarity
risk. Rewrite to distinguish "stars earned by Franchising raise your permanent bonus;
purchased research stars are spendable on research only." Also verify the Shop/Prestige
purchase copy says "research only" everywhere (it does on the pitch card — keep it).

### 33. HelpView FAQ never mentions the Research Grant
Add it to the money/shop FAQ answer alongside the other IAPs.

### 34. Legacy card has no IntroBanner
`Sources/UI/Sheets/PrestigeView.swift` `FranchiseSection` shows the Legacy card whenever
`canLegacyReset`, relying on a one-time alert the player may have dismissed weeks earlier.
Add an `IntroBanner` (key: reuse `IntroKey.legacy` semantics — add a distinct
`legacyCard` key to `IntroKey` + `allKeys`) matching the pattern of the other banners.

### 35. `DECISION` — "Research Boost" vs "Research Grant" naming collision
Mechanically identical (`grantResearchStars`), near-identical names/copy, adjacent in the
Shop — one is 400 gems, one is $9.99. Propose renames to Robert (e.g. gem sink → "Star
Infusion +300", IAP → "Research Grant +2,500") or distinct subtitle framing; if the IAP
name changes, the ASC doc/`Products.storekit` reference names must follow.

### 36. No single place explains the three-tier currency structure
Gems → stars → research-only stars is never explained together. Add one HelpView FAQ entry
("What are all these currencies?") covering coins, gems, stars (earned = permanent bonus +
spendable), purchased research stars (spendable only).

### 37. Missing IntroBanners for later systems
`IntroKey` covers 11 surfaces but not: Achievements, Quests, Daily/streak, Guest Chef
(zero explainer of the weekly rotation), Game Center, iCloud sync. Minimum worth adding:
**Guest Chef** (in its Collection spotlight) and **iCloud sync** (data-adjacent). Add keys +
banners following the existing pattern; the rest are optional-nice.

### 38. `DECISION` — No notification references the reset cadence
The four scheduled notifications never mention that a stale board is getting expensive —
the one timing decision the game now wants players to make well. Option: a fifth plan,
"Your board's been running N days — costs are up X%, a Franchise reset clears it," fired
around day 3 of board age. Design it, show Robert copy + trigger rule before wiring.

### 39. `DECISION` — No re-engagement path for the 6-month research arc
Nothing notifies or nudges mid-tree. Option: notification when spendable stars exceed the
next affordable node's cost ("Research ready: you can afford Prep Stations rank 3").
Propose to Robert alongside 38 — same planner, same review.

---

## P4 — Accessibility (no decisions, straight work)

### 40. The primary tap-to-cook control is invisible to VoiceOver
`Sources/UI/StationListView.swift:147-176` — the button's label is pure vector art. Add
`.accessibilityLabel("Cook \(spec.name)")` (or equivalent from the model) and
`.accessibilityHint("Serves one order")`.

### 41. Label every icon-only button
Known sites: `Sources/UI/HUDView.swift:66-81` (Help, Settings),
`Sources/UI/ActivePlayViews.swift:136-164` (Coffee Break, Rush Hour), plus icon-only
controls in `StationListView.swift` and `PrestigeView.swift`. Grep for `Button {` blocks
whose label is only a `GlyphIcon`/`Image` and add `.accessibilityLabel` to each.

### 42. Sweep the sheets for unlabeled elements
`Sources/UI/Sheets/*.swift` currently contain zero accessibility modifiers. Pass through
each sheet: label progress bars with `.accessibilityValue` (e.g. quest progress), group
stat rows with `.accessibilityElement(children: .combine)`. Pragmatic bar: every
interactive element reachable and meaningfully announced, not a full audit.

### 43. `DECISION` — Dynamic Type is entirely unsupported
`Sources/UI/Theme.swift` hard-codes `.system(size:weight:design:)` everywhere. Real fix is
migrating `Theme.body/numeric/title` to `.system(.body/.title3, design:)` +
`@ScaledMetric` for custom sizes — a visual-regression-prone lift across every screen.
Ask Robert whether to take it now or defer to a dedicated pass; do NOT attempt it as a
drive-by.

---

## P5 — Store readiness / compliance

### 44. No privacy policy anywhere (App Review Guideline 5.1.1 blocker)
The app uses IAP + iCloud + Game Center; App Store Connect requires a Privacy Policy URL.
Nothing in `SettingsView` (only a version footer) or the docs mentions one. **Do**: add a
"Privacy Policy" link row in Settings' about/footer area pointing to a placeholder URL
constant (single `let privacyPolicyURL` so Robert swaps in the real one), and add a section
to `docs/AppStoreConnect-IAP-Setup.md` (or a new checklist doc) telling Robert he must host
a policy and paste the URL in ASC + in that constant. Writing/hosting the actual policy is
his task — flag it prominently.

### 45. `DECISION` — Dark-mode-only is currently an accident-shaped choice
`.preferredColorScheme(.dark)` is forced everywhere and `Theme.swift` has no light palette.
Shipping dark-only is legitimate for a game — but confirm with Robert it's deliberate. If
yes: no code change; note it in App Store metadata plans. If no: that's a large theming
project to scope separately, not part of this work order.

### 46. Verify the ASC docs stay consistent after P2 pricing changes
After items 19/20/35 resolve, re-check `docs/AppStoreConnect-IAP-Setup.md` and
`Sources/Store/Products.storekit` against `ShopCatalog` — product IDs, prices, types,
reference names, and the product count — so the three sources never disagree.

---

## P6 — Tests and hardening to add regardless

### 47. Test the GameCenter clamp (with item 1).
### 48. Test `CloudSave.isAhead` legacy/tie cases (with item 4).
### 49. Test `automatedRate` includes the legacy multiplier (with item 5).
### 50. Test daily-reward coins reach `league.score` and `.earn` quests (with item 6).
### 51. Test `NotificationPlanner` emits no offline-cap plan at `automatedRate == 0` (with item 10).
### 52. Update `FeatureTests.swift:1554-1573` to whatever item 14's decision is — the test
currently enshrines the questionable behavior; it must assert the *decided* intent.
### 53. Add a decode test: a save JSON missing `boardStartedAt` gets "now" (fresh grace
period), and one missing `seenIntros` with `totalTaps > 0` backfills all intro keys —
locking in the two subtle migration behaviors in `GameState.init(from:)`.
### 54. Add a `Quests.roll` property test: for every kind, rolled `target > progress` at
roll time (guards the absolute-kind seeding at `Sources/Core/Quests.swift:128-133`).
### 55. Simulator playtest checklist after each tier lands: fresh-install onboarding,
buy/hire/prestige loop, a StoreKit test purchase of the Research Grant, Legacy reset,
notifications toggle → relaunch → background (verifies item 2), VoiceOver spot-check of
the main screen (verifies items 40-41).

---

---

# PART 2 — Second review: the prestige arc (supersedes items 15, 16, 22, 24 where noted)

A full re-simulation of the prestige loop against the SHIPPED constants (8h grace, 1/6
days-per-hour, power 3.0 — note the old scratchpad sims used pre-final values) with
research profit feedback, a 16h-awake/8h-offline sleep model, and an activity multiplier
sweep (A=1 bare floor … A=10 perks/boosts/combo-rich) produced these facts:

- **The "~6 months to finish the 757,445★ tree" claim in `Research.swift`'s doc comment is
  wrong by an order of magnitude.** Star income compounds (stars → multiplier → earnings →
  stars): first prestige lands ~10-15K stars (players wait past the 1e11 minimum, they
  don't take 47★), which grants a ~40× multiplier, and each subsequent board multiplies
  lifetime earnings 10-1000×. The full static tree completes **by day 10-14** in every
  simulated profile. Live play corroborates the curve: a real save observed a +32,000%
  (~320×) multiplier ≈ 5.6M stars within weeks on an earlier build.
- **Star totals reach 39M-244M by day 180** depending on intensity — meaning the 100M
  `maxSaneLifetimeStars` ceiling would CLAMP legitimate hardcore players around month 2-4.
- Fixed star prices can never pace this currency: any constant is trivial one board later.

Robert's confirmed targets: **fully maxing the arc ≈ 6 months** (new venues/content patch
extends it afterward), and **prestige must feel like a big decision**.

### 56. Research pricing rework — the headline change (direction confirmed, params flagged)
Replace static-only pricing with award-proportional hybrid pricing:
`cost(rank) = max(staticCost_2.4curve, 0.4 × lastPrestigeAward)`.
Validated by simulation (`scratchpad sim6mo.py` + AwardSim variant): with k=0.4 the tree
maxes at **day 111 / 185 / 259 for 3/5/7-day prestige cadence — identical across a 10×
intensity spread** (self-scaling, ungameable: the award is fixed per board, unlike live
`pendingStars`). A 5-day patient cadence = almost exactly 6 months; faster cadence
meaningfully accelerates it, which strengthens the prestige-timing decision. Each prestige
funds ~2-3 ranks, so "when do I reset" becomes "when does my next research unlock" — the
big-decision feel Robert wants.
**Implement**: add `lastPrestigeAward: Int` to `GameState` (decode `?? 0`; set in
`prestige()`; reset to 0 in `legacyReset()` so post-Legacy early ranks fall back to the
cheap static floor); thread it through `Research.canBuy`/`GameEngine.buyResearch`/the
`PrestigeView` cost labels (make cost lookup engine-aware — `node.cost(forRank:award:)`).
Rewrite `ResearchNode.cost` doc comment (the six-months claim there is now known-wrong).
Update `EconomyTests` + add: cost equals static floor when award is small; equals
0.4×award when large; a simulated 36-prestige sequence affords ~90 ranks.
**k=0.4 is Robert-reviewable** but the mechanism is decided.

### 57. Raise `maxSaneLifetimeStars` 100M → 10_000_000_000 (1e10)
Legit players hit 200M+ by day 180 (sim, A=10 cad 3d). 1e10 gives ~50× headroom over the
6-month hardcore trajectory while staying 9 orders of magnitude below the Int64 trap line.
`maxSaneLifetimeEarnings` self-derives. Update the doc comment (its "13.5M in two years"
claim came from the pre-final-constants sim — say so) and the EconomyTests expectations.

### 58. Scale the research-star purchases with the new pricing (supersedes item 22)
Flat +300/+2,500 grants are noise one board after week one. Make them proportional:
Research Boost (gems) → `max(300, 15% × lastPrestigeAward)`; Research Grant IAP →
`max(2_500, 60% × lastPrestigeAward)` (≈ 1.5 ranks at k=0.4). In-app subtitles must become
dynamic ("+N stars right now", computed); the ASC/storekit descriptions stay qualitative
("a research windfall scaled to your empire"). Percentages are Robert-reviewable.

### 59. Multiplier displays need large-number formatting
`HUDView.swift:53` and `PrestigeView.swift:76/79/159` render `+\(Int((mult-1)*100))%`.
At the raised ceiling the bonus reads "+4,000,000%"-style garbage (and live saves already
saw +32,000%). Above ~×100, switch to "×418" / "×1.3K" via `Format.count`. No trap risk
(bonus stays far below Int64) — this is legibility only.

### 60. Legacy gate is broken by the real curve (supersedes item 16's framing)
`legacyUnlockLifetimeStars = 500` is passed on the FIRST prestige (~10-15K award). The
"several trips through the regular loop" doc comment predates the curve. Gate on prestige
count and/or a star total that means something (e.g. `prestigeCount >= 5` — week 3-5).
Combined with item 14's decision about what Legacy costs. Robert picks the gate.

### 61. Mega-whale IAP tier (Robert requested; final prices are his call)
Four new products — all self-scaling (gems or time-based, never flat coins/stars), so the
star curve can't obsolete them. Wire each end-to-end: `ShopReward` case, `ShopCatalog`,
`Products.storekit`, `StoreService.grant`, `isConsumable`/`isOwned`, `StoreTests`, ASC doc
table + product-count strings (13 → 17 everywhere, including the section-136 sentence).
- **Dynasty of Gems** — $199.99 consumable, 45,000 gems (+125%/$ vs Empire's +80% — keeps
  the ladder monotonic).
- **Mogul Pass** — $49.99 non-consumable: permanent +50% profit (stacks multiplicatively
  with VIP), +12h offline cap on top of current, exclusive venue skin set. New entitlement
  `mogul` (decode `?? false`), family-shareable to match VIP.
- **Time Vault** — $39.99 consumable: 24h of income banked instantly + ×3 profit for 72h.
- **Founder's Bundle** — $99.99 non-consumable one-time: 12,000 gems + 2 guaranteed
  Legendary managers + ×2 profit for 7 days.
Guard rails: no new strict-dominance inversions (see item 19 — fix that first, then price
these above their gem-content value); permanent-power stays entitlement-based like VIP.

### 62. Re-anchor achievements to the measured curve (folds items 17 & 25)
With sim data in hand: `earn_3` → ~1e13 (post-first-prestige), consider an `earn_4` at
~1e18; prestige thresholds 5/15 are fine for a 3-7d cadence (15 ≈ week 8-15) — keep, but
add a `prestige_4` (40?) for the 6-month arc. Numbers to Robert as a table.

### 63. Make the prestige moment carry its weight (design-lite, no new mechanics)
A richer pre-confirm sheet in `PrestigeView`: star award, current → new multiplier, "~N
research ranks affordable after this reset" (from k×award vs the tree), cost inflation
cleared (current `costInflation`), staff being let go (count of non-premium managers).
All values already computable from engine state. This is the "huge decision" surfaced.

### 64. Propagate the new pacing into copy (extends items 30-31)
HelpView research/franchise sections and the `IntroBanner` for research should reflect:
research is award-priced ("each breakthrough costs a share of your latest Franchise"),
the arc is a months-long journey, prestige cadence drives it.

### Part-2 second-pass code notes (small, fold into P1)
65. `Festival.rolloverIfNeeded` resets `endsAt = now + seasonLength` — an absence of
    several weeks settles only one season (acceptable; add a comment saying it's chosen).
66. `ManagerCatalog.random(rarity:seed:)` uses `abs(seed)` — fine for current callers
    (seeds 0..<10K) but `abs(Int.min)` traps; swap to `seed.magnitude`-based indexing in
    passing.
67. Old scratchpad sims (`prestige_staleness.py` etc.) carry pre-final staleness constants
    (12h/÷24/^2.5 vs shipped 8h/÷6/^3.0) — any future tuning must re-copy the shipped
    values; `sim6mo.py` is the current source of truth.

---

# PART 3 — Retention depth & goal clarity (Robert-requested, all approved to implement)

Two driving observations: (a) the game's systems are deep but the *hooks that pull a
player back tomorrow* are thin — most engagement surfaces are passive lists rather than
appointments, anticipations, or near-misses; (b) a real non-idle-gamer playtester
(Robert's wife) never understood the end goal — the earn → automate → expand → Franchise
→ research → Legacy arc is invisible until you stumble into it. Items 68-87 add the
hooks; 88-91 fix the goal clarity. Defaults are chosen; tune-flag anything that fights
the code.

### Retention hooks

68. **Prestige anticipation meter.** The HUD star pill currently shows the static bonus.
    Make it show pending stars accruing live (+ a subtle fill animation as
    `pendingStars` grows) and, post-item-56, "next research rank affordable after
    Franchise: ✓/✗". Watching the payoff build is the single strongest pull the game
    already owns and doesn't surface.
69. **End-of-run recap.** After every prestige, before the confetti clears: "This
    franchise ran 4d 2h · earned $8.1T · served 1.2M · +14,200 stars". Extends item 63's
    confirm sheet with a celebration after. All values already in state.
70. **Daily Plan screen.** One consolidated on-launch sheet (replaces nothing, sits above
    the sheets): claimables in one place — daily reward, completed quests, returned
    errands, unclaimed festival tiers, streak status — each one-tap. The morning ritual
    is currently 5 sheet visits; make it one.
71. **Happy Hour appointment window.** One fixed 2h window daily (default 6-8pm local,
    computed not scheduled) with ×1.5 tips + doubled golden-customer odds; a HUD chip
    when active, one notification 15min before (respects the notifications toggle).
    Time-of-day habit anchor the game entirely lacks.
72. **Daily Deal in the shop.** One gem sink per day at 30% off, rotating
    deterministically from the day number. Near-miss/scarcity hook, zero new content.
73. **Weekly Big Challenge.** One large weekly quest slot ("Serve 40,000 dishes this
    week", scaled like `Quests.roll`) with a premium-feel reward (epic manager or 150
    gems). Complements the 3 fast slots; weekly cadence matches league/festival.
74. **Venue Mastery stars.** Bronze/silver/gold badge per venue for all-stations at
    Lv 50/100/250 (persists through prestige — it's an accomplishment, not run state).
    Medium-term goals between prestiges; show on the venue select screen.
75. **Recipe album completion pressure.** The Collection tab shows sets; make missing
    cards explicit ("1 card missing!" highlight on nearly-complete sets) and celebrate
    set completion with the big fanfare. Completion anxiety is free retention.
76. **Nemesis rival.** Persist one league rival name across weeks (seeded per player)
    whose jitter tracks just above the player's recent pace; badge them in standings.
    "Beat Rossi's Bistro this week" beats 29 anonymous rows.
77. **Comeback bonus.** Absent ≥3 days → "Grand Reopening" banner on return: ×2 profit
    for 24h, free. Win-back the game currently leaves to chance.
78. **Landmark celebrations.** First time lifetime earnings cross 1M/1B/1T/1Qa: full
    confetti + toast. One `Set<String>` of crossed landmarks in state, checked in
    `recordEarnings` (cheaply — compare against next-uncrossed only).
79. **Manager bonding levels.** Managers gain XP per real-time day assigned (cap level
    5, +2% station profit per level). Roster attachment + a reason to keep premium
    managers working. New `bondXP` on `OwnedManager` (decode `?? 0`).
80. **Choose-one mystery card packs.** Festival tier-20 free reward and league promotion
    bonus become "pick 1 of 3 face-down recipe cards". Anticipation beat using the
    existing recipe system; no paid gacha anywhere.
81. **Streak milestone preview.** Show the next streak milestone and days remaining on
    the Daily sheet header ("Day 23 — 7 days to 160 gems"). Loss-aversion made visible;
    pairs with the item 24 extension to day 300.
82. **Rush Hour chain bonus.** Completing a Rush within 1h of cooldown-end grants +1
    "chain" (max 3): each chain tier +25% Rush payout. Rewards punctual returns —
    appointment mechanic on an existing system, stored as `rushChain: Int` + timestamp.
83. **Offline earnings tease notification.** Replace the generic "offline cap" copy
    (item 10 fixes the zero-rate bug) with the amount: "Your court earned ~$41B while
    you were away — the till is full." Computed at schedule time from current rate.
84. **"3 things to do now" contextual chip.** Small HUD strip cycling through actionable
    nudges (claimable quest, errand returned, Rush ready, festival tier unclaimed) —
    tap deep-links to the right sheet. Uses existing red-dot logic, surfaces it.
85. **Golden customer jackpot variant.** 5% of golden customers are "VIP critics": ×10
    payout, distinct sparkle + the big fanfare. Rare-event thrill on an existing spawn.
86. **Season number + history.** Festival/league already have season IDs; show "Season
    12" prominently and a small personal-best history (best tier, best rank) in Events.
    Long-term identity: veterans can see how long they've played.
87. **Cosmetic prestige frames.** At prestige counts 5/15/40, the venue sign gains an
    escalating frame (bronze/silver/gold trim — vector, Theme tokens). Visible status
    for the core loop; pairs with `prestige_4` from item 62.

### Goal clarity (the "what's the point?" fix — highest priority in this part)

88. **Rewrite WelcomeView as the journey, not tips.** Three panels, plain language, with
    small vector art: (1) "Serve food, earn coins, hire staff so it runs itself." (2)
    "Open all five venues — from Burger Shack to the Grand Food Hall." (3) "Then
    Franchise: start over bigger. Stars make every future run richer, forever. Max out
    your research empire — that's the game." A non-gamer must leave knowing the loop is
    deliberate. (Replaces item 28's single-line fix; keep its cadence warning.)
89. **"Next Goal" director chip on the HUD.** A single always-visible goal that advances
    through a fixed ladder: hire first manager → reach Lv 25 perk → open venue 2 → …
    → first Franchise → first research → open all venues → first Legacy. Driven by a
    pure function of state (no new persistence — derive the first unmet rung). Tapping
    it explains the goal in one sentence and deep-links. This is the wife-fix: the game
    always tells you what the point of *right now* is.
90. **Surface the Roadmap.** The meta-milestone Roadmap view exists but hides in the
    Franchise sheet. Link it from the Next Goal chip's explainer and from HelpView's
    first entry ("What's the goal?"), and add an IntroBanner on first Roadmap open
    showing the full arc with the player's current position highlighted.
91. **Extend the tutorial past its current end.** The guided flow stops before prestige
    is conceivable. Add two late tutorial beats that trigger contextually rather than in
    the opening minutes: on first reaching 50% of `minimumLifetimeForPrestige` ("See the
    Franchise pill? That's the real game — half way there") and on first prestige
    completion ("Stars never reset. Research never sleeps. Go again, bigger."). Use the
    existing `TutorialState`/`seenIntros` machinery.

Sequencing note: 88-91 land in P3's slot (copy/onboarding); 68-87 land after Part 2's
items and before P4. Where a retention item and a Part 1/2 item touch the same surface
(63/69, 10/83, 24/81, 62/87), implement them together in one commit.

## RESOLVED DECISIONS (Aug 2026 — Robert delegated to the reviewer's recommendations)

Every DECISION marker above is settled as follows. Implement these without pausing to ask.
If, mid-implementation, one of them turns out to conflict with something in the code the
review missed, flag it in the final summary rather than silently deviating.

- **Item 14 (Legacy cost)**: option (a) — `legacyReset()` also zeroes `lifetimeEarnings`,
  AND `Balance.legacyMultiplier` rises from +5%/level to **+20%/level** so the harsher
  reset is worth taking. Update the FeatureTests assertions (item 52) and all Legacy copy
  to match the now-true "trades away your stars" framing.
- **Item 60 (Legacy gate)**: unlock requires **`prestigeCount >= 5`** (star threshold
  dropped; remove/repurpose `legacyUnlockLifetimeStars`, update the Balance doc comment,
  the Legacy card copy, and tests).
- **Item 23 (gem staffing vs staleness tax)**: keep as-is; add a code comment marking it a
  deliberate monetization valve.
- **Item 19**: Grand Opening Bundle price → **$14.99** (code fallbackPrice, storekit, ASC
  doc).
- **Item 20 + 21**: gem-sink spread — **Research Boost 250 gems, Automate Venue 400,
  Guest Chef 700** (`GuestChef.gemPrice`), Legendary Crate stays $9.99.
- **Item 61 (whale prices)**: as specced — Dynasty $199.99 / Mogul $49.99 / Time Vault
  $39.99 / Founder's Bundle $99.99.
- **Item 18 (errands)**: `gemsPerHour` → **1/2/4/7**.
- **Item 56 (k)**: **0.4**.
- **Item 57 (ceiling)**: **10_000_000_000**.
- **Item 58 (scaled purchases)**: gem Boost = **max(300, 15% × lastPrestigeAward)**; $9.99
  Grant = **max(2_500, 60% × lastPrestigeAward)**.
- **Item 62 (achievements)**: Tycoon `earn_3` → **1e13**; add **`earn_4` at 1e18** and
  **`prestige_4` at 40 prestiges** (rewards following the existing 15/45/120 pattern —
  use 250 for the new fourth tiers).
- **Item 35 (naming)**: gem sink renamed **"Star Infusion"**; IAP stays "Research Grant".
- **Items 38/39 (notifications)**: **add both** — day-3 board-staleness nudge and
  research-affordable nudge — via `NotificationPlanner` with tests.
- **Item 43 (Dynamic Type)**: **deferred** — skip, leave a TODO note in Theme.swift.
- **Item 45 (dark-only)**: **deliberate** — no light theme; note it and move on.

With these resolved, nothing in this document requires waiting on Robert. Work
start-to-finish.

## OVERNIGHT PROTOCOL (final phase, after both work phases complete)

Robert is asleep while this runs. When implementation and the visual refresh are both
done and committed, do a **five-pass verification review** before writing the morning
report — one full pass per lens, each covering EVERY aspect of the game:

1. **Correctness pass** — re-read every file touched; hunt regressions, broken references
   to renamed/removed symbols (`legacyUnlockLifetimeStars`, "Research Boost", flat +300/
   +2,500 copy), missed switch cases for new `ShopReward` values, and any remaining
   unguarded `Int(Double)` conversions anywhere in Sources/.
2. **Economy pass** — re-run `sim6mo.py` + the AwardSim check against the implemented
   constants; verify the ~6-month max target still holds end-to-end; sanity-check every
   price/reward touched against its neighbors for new dominance inversions.
3. **Consistency pass** — code vs `Products.storekit` vs both ASC docs vs HelpView vs
   in-app copy: every product count, price, name, and mechanic description agrees.
4. **Experience pass** — full simulator playthrough: fresh install → tutorial → first
   prestige → research purchase → shop (test-buy one item per new product) → Legacy
   flow → every sheet opened; screenshot anything that looks wrong.
5. **Test pass** — full suite green, plus review the tests themselves: does every resolved
   decision have an assertion locking it in?

Fix outright bugs found in these passes immediately (commit per fix). Anything that is a
*judgment call* — a number that feels off, a mechanic that plays worse than expected, an
improvement idea beyond this document's scope — do NOT implement. Collect them into the
morning report as a numbered list of QUESTIONS, each with a recommendation, formatted so
Robert can answer with just the numbers. The report ends with: what shipped, before/after
screenshots, test status, and that question list.
