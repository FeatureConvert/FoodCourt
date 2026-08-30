# Overnight report #3 — bug hunt & balance review (Aug 30, 2026)

Third autonomous session, much narrower in scope than the first two: no new systems,
just correctness bugs (several reported live by you and your wife) and a balance
consistency review. **12 commits, 286 tests green** (StoreTests still skip on CLI by
design — run once from Xcode). Nothing shipped touches money, IAP, or App Store Connect;
build stays at 4, still unsubmitted per your instruction.

## What shipped

**The crash you reported** — Goals tab crashed to springboard with no error. Root cause:
`ActiveQuest.title` computed `Int(target)` unconditionally before checking quest kind,
even for `.earn` quests whose target scales uncapped with your income. Once income got
large enough, that conversion trapped the instant the Goals tab rendered. Fixed, plus a
sibling: "Serve" quest targets (e.g. "Serve 6,753 dishes" — the ugly-number report from
your wife) weren't rounded to a legible figure like the `.level` quest already was.

**A broad audit pass** (three parallel reviewers over the core engine, save/sync, and UI
layer) turned up four more real bugs, all fixed with regression tests:
- iCloud's routine background autosave could silently overwrite a save another of your
  own devices had already pushed further ahead — no conflict prompt, just gone. Now the
  automatic path re-checks before writing; the explicit "keep this device" override in
  the conflict screen still works as designed.
- `LeagueState`'s save decoder was the one struct left hard-requiring its fields instead
  of defaulting them — a single missing/corrupt field in the "league" blob would have
  thrown and wiped the *entire* save, not just League progress. Same bug class as three
  prior incidents (Quests, Balance, GameCenterService), just in decode form.
- A catering order survives a Franchise/Legacy reset pointing at a venue the reset just
  relocked — dead for up to 24h since a new one won't roll while the old one's still
  "active." Now cleared on reset, same as the golden-customer/station-order cleanup that
  already existed.
- A Face-Off crew's managers get deleted by `prestige()` (letting go non-premium hires)
  without the expedition itself being cleared — it was resolving against an empty crew
  instead of just ending. Fixed.

**The two bugs you reported directly tonight:**
- Auto-Assign Bench did nothing when tapped, no toast, felt broken. Actual cause: the
  button's displayed count ("Auto-Assign Bench (3)") counted every open station without
  checking whether its staffing fee was affordable — `autoAssignBenchedManagers()`
  correctly skips what it can't afford, so when *nothing* was affordable the button just
  silently did nothing. Fixed the count to be an accurate dry-run prediction; the button
  now never overpromises. Same bug independently found in PrestigeView's "Buy All
  Affordable Research" button (stars instead of coins) — fixed identically.
- The coin balance in the HUD was truncating to "60…" — unreadable. `minimumScaleFactor`
  shrinks text as a fraction of its OWN font size, not to a shared absolute floor, so the
  19pt balance line and the 11pt income-rate line under it hit genuinely different
  minimum widths at the same 0.6 despite sharing the same space; the bigger line hit its
  floor first and truncated. Lowered the floor across the HUD's currency row.

**Balance review** (peripheral reward/cost systems checked against the current, heavily
-retuned core economy): found Legacy's Seed Capital perk delivering roughly 1-2% of its
promised value — its cap was compared against a raw, uninflated venue price while the
income it's capping against already carries your own star multiplier, so for any player
who'd actually unlocked Legacy (5+ prestiges, tens of thousands of stars) the cap almost
always won. Fixed to use the same inflated pricing every other cost in the game respects.
Also caught and fixed a false claim in `Achievements.swift`'s own comments (see Q1 below)
— **comment-only**, no threshold changed.

Also: deduplicated a three-times-copied multiplier list (`globalMultiplier` /
`automatedRate` / `automatedRate(venueID:)`) that a code comment was manually keeping in
sync — the exact arrangement that already let Legacy's multiplier silently go missing
from one copy once before. One shared source now; and a harmless unused-binding compiler
warning silenced.

**Consistency pass**: re-checked every historically-drift-prone numeric claim in
`HelpView.swift` (combo cap, Rush Hour timing/chain bonus, Coffee Break, recipe set
bonus, festival tier count, streak milestone max day, perk-choice levels) against the
actual current constants one by one — all still exactly correct, no copy drift found.

## Questions for you (numbers, not code — nothing below is implemented)

**Q1 — "Dynasty" achievement (earn 1e18 lifetime) claims to match the 40-Franchise
capstone. It doesn't.** Traced through the current star formula: 1e18 corresponds to only
~150,000 cumulative stars, about 10-15x a single first prestige's award — crossed within
the first few weeks at your documented cadence, not six months. This was a resolved
decision from a prior session's work order (`docs/work-order.md` item 62), but the number
picked there doesn't survive being traced through the same formula used to fix two
sibling systems (Research pricing, Legacy's own gate) that had the identical problem.
Options: (a) raise the threshold to ~1e24 so it actually lands at six months (derived
from this repo's own "~225M stars in 6 months" hardcore benchmark), or (b) keep 1e18 as
an earlier, more attainable achievement and just leave the comment's parity claim
removed (already done tonight). No strong recommendation either way — it's a genuine
"how should the achievement ladder feel" call.

**Q2 — Face-Off (expedition) rewards look underpriced relative to Errands.** Even in the
best case (maxed legendary crew, guaranteed win), Face-Offs pay roughly 0.7-1.1
gems/manager-hour; Errands pay 7/manager-hour for the same rarity, guaranteed, no risk.
That's a 6-10x gap, and Errands were already the system hit hardest in a prior nerf pass
— so Face-Offs look low even against an already-conservative baseline, for a mechanic
that additionally risks losing. I didn't find a design note explaining the gap either
way. Recommend: raise Face-Off gem/coin rewards roughly 3-5x to land closer to Errands'
per-manager-hour rate, but the exact multiplier is yours to pick — I can implement
whatever number you choose in a few minutes once decided.

## Test status

286/286 green (`FableTests`, excluding `StoreTests` which structurally can't run outside
Xcode's own Test action — documented in that file's own header, unrelated to tonight).
Full suite re-run after every commit tonight, plus the long-horizon multi-profile
simulation (`PrestigeScalingTests`/`EarlyGamePacingTests`/`ExtremeScaleTests`) green at
the end. Verified live in the simulator on a fresh install: onboarding, tutorial skip,
station buy/hire, debug menu, and the HUD currency row rendering correctly post-fix.

## What I did NOT touch

- Build number (still 4), App Store Connect, any submission step — per your explicit
  "we won't submit yet."
- Any real money path, StoreKit config, or IAP pricing.
- Both DECISION items above — flagged, not guessed.
- Your wife's phone / device registration — that needs your one-click "Register Device"
  in Xcode, which I can't do from here; the build itself has been ready since build 4.

## For you, when you're up

1. Answer Q1/Q2 above whenever convenient — either is a small, fast change once decided.
2. Everything is pushed to `origin/master` (through commit `20526ad`). Nothing local and
   uncommitted.
3. If you want the actual "Register Device" + Run-to-her-phone step, just say so and I'll
   re-verify the device build first.
