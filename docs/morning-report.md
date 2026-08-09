# Morning report — overnight autonomous session (Aug 9, 2026)

Thirteen commits, 212 tests green (11 StoreKit-session tests skip on CLI by design — run
them once from Xcode), every tier of docs/work-order.md landed except three deliberate
deferrals listed at the end. No real money touched anywhere; all store work is against the
local StoreKit test configuration.

## Phase 1 — engineering (all committed, suite green at every step)

**P0 crash/money bugs**: Game Center's `Int(Double(Int.max))` trap clamped (this was the
same crash class as the star incident and was reachable from the League sheet on a
repaired save); notifications no longer silently die after relaunch (auth status is now
read from the system, not a stale in-memory cache); a paid consumable can no longer be
consumed-unfinished in the launch race (transactions park until the engine attaches);
cloud-save conflict ordering now understands Legacy resets and corruption-clamp ties.

**P1 correctness**: `automatedRate` includes the Legacy multiplier (offline pay, quests,
dailies, errands, and time warps were all underpaying Legacy players); daily-reward coins
feed the league and earn-quests; stale golden/orders cleared on prestige; offline-cap
notification gated on actually earning and teasing the real amount; assorted hardening.

**Part 2 — the prestige arc** (the headline): research is now award-priced —
`cost = max(static 2.4 curve, 40% × your last Franchise award)`. Sim-validated (and
re-verified tonight from the shipped constants): the 90-rank tree maxes at **day 111 /
185 / 259 for a 3 / 5 / 7-day prestige cadence — identical across a 10× play-intensity
spread**. A 5-day patient cadence is your six months, and cadence choice genuinely moves
the date. Each Franchise funds ~2-3 ranks, so "when do I reset" now means "when does my
next breakthrough come" — the big-decision feel you asked for, priced in. Legacy is now
honest: it zeroes lifetime earnings too (no more free re-prestige), pays +20%/level
(was +5%), and gates on five franchises. The sanity ceiling rose to 1e10 so it never
clamps a real player. Star purchases scale with the award (Star Infusion 15%, Research
Grant 60%) so they stay meaningful forever. Multiplier displays switch to ×-form past
×100 (your wife's +32,000% would now read "×321").

**Whale tier**: Dynasty of Gems $199.99 (45K gems — ladder stays strictly
better-per-dollar, now enforced by a test), Mogul Pass $49.99 (+50% forever, stacks with
VIP, +12h offline, family-shareable), Time Vault $39.99 (24h banked + ×3/72h), Founder's
Bundle $99.99 (one-time: 12K gems, 2 Legendaries, ×2 for a week). Wired end-to-end:
catalog, storekit config, grants, entitlements, ASC doc (13 → 17 everywhere), tests.

**Economy rebalance**: errand gems 1/2/4/7 (the un-nerfed faucet), quest gems trimmed
~35% (slot-cycling still out-earned everything combined), Guest Chef 400→700 gems,
Grand Opening $9.99→$14.99 (it strictly dominated Chest), streak milestones extended to
day 300, Tycoon achievement 1e9→1e13 plus Dynasty (1e18) and Food Court Legend (40
franchises) capstones.

**Goal clarity (the wife-fix)**: WelcomeView now opens with the journey in three numbered
beats and no longer advises the exact board-stalling the staleness tax punishes; a
persistent **Next Goal chip** under the HUD walks a ladder from "hire your first manager"
to Legacy 3 (tap to unfold why it matters); the Roadmap got an intro banner and HelpView
now opens with "What's the goal?"; a one-shot toast fires at halfway-to-first-Franchise.

**Retention hooks (18 of 20)**: live anticipation meter on the star pill ("+558 ready"),
end-of-run recap sheet after every Franchise, Today's Plan checklist with deep links on
the daily sheet, Happy Hour (6-8pm local, ×1.5 + double golden odds, HUD badge +
reminder), Daily Deal (30% off, rotates daily), Weekly Challenge (150 gems, resets
Monday), Venue Mastery badges (persist through prestige), nemesis rival (save-stable name,
paced just above you), Grand Reopening comeback boost, landmark celebrations
(1M/1B/1T..., backfilled silently for old saves), manager bonding (+2%/level at
1/3/7/14/30 days of service), streak preview, rush chains (max 3, +25%/tier), offline
tease notification, VIP critics (5% of goldens pay ×10), board-staleness day-3 nudge,
season best tracking, RIVAL badge in standings.

**Compliance/copy/a11y**: Privacy Policy link in Settings (**placeholder URL — swap in
your real hosted policy before submission, constant is marked**), currencies FAQ, Guest
Chef + iCloud intro banners, VoiceOver labels on the tap-to-cook control, Coffee Break,
Rush Hour, star pill, Help, and Settings.

## Phase 2 — visual refresh (core landed, verified by screenshot)

Theme gained depth tokens (top-light wash, button light, lit edges) consumed by
`PanelBackground` and `ChunkyButtonStyle`, so every panel and button lifted at once. The
stage is now a lit room: glowing garland bulbs, warm accent light pool, floor contact
shadow, vignette. Food sprites get a shared sheen/shade pass. Payout bursts anchor over
the cooker ring instead of on top of the station title. Before/after screenshots:
scratchpad `before_main.png` → `after_main.png`, `after_burst_fix.png`, `shop_check.png`.

## Phase 3 — verification

1. Correctness: swept for stale references (fixed one doc comment) and unguarded
   `Int(Double)` conversions in new code — clean. 2. Economy: constants re-derived from
   the shipped files match the sim (k=0.4, 1e10, +20%, gate 5). 3. Consistency:
   storekit == code == ASC doc, 17 products, ids match exactly (scripted check).
   4. Experience: simulator run-through — daily sheet (streak preview, Today's Plan),
   main screen (chip, meter, lit stage), Shop (Daily Deal live at 175 gems). 5. Tests:
   212 green.

## Judgment calls I made (flag any you want changed)

1. Quest gems trimmed ~35% — my call from the aggregate ledger, not in the resolved list.
2. Happy Hour fixed at 6-8pm local (not configurable), ×1.5, doubled golden odds.
3. Landmarks at 1e6/9/12/15/18/21; rush chain window 1h, cap 3, +25%/tier; critic 5%/×10;
   bonding levels 1/3/7/14/30 days at +2%; comeback threshold 3 days for ×2/24h;
   weekly challenge = 6h of serve throughput for 150 gems.
4. Item 84 ("3 things to do now" HUD chip) folded into Today's Plan + red dots rather
   than adding a third competing HUD element.
5. Research Grant's in-app subtitle is now dynamic; the ASC description is qualitative
   ("scaled to your empire") — Apple reviewers dislike numbers that don't match.

## Deferred (the honest list)

1. **Item 80, mystery card picks** — the one retention hook not built: it needs a real
   pick-one-of-three reveal UI to feel right, and a rushed version would undercut it.
   Recommend: next session, ~1-2h.
2. **Design brief items 3-8 in full** (character overhaul, food redraws, tab bar
   identity, app icon, prestige star-field moment, item 87's sign frames) — the token
   foundation landed and reads well, but the full art pass deserves its own dedicated
   session. Copy-paste prompt for it below.
3. **Dynamic Type** — per the resolved decision, deferred with a TODO.

## The design-session prompt (copy-paste when ready)

```
Read docs/design-brief.md in this repo and execute the remaining visual refresh of Food
Court Tycoon (brief items 2-8; item 1's Theme tokens already shipped - build on
Theme.topLight/buttonLight/edgeLight, do not reinvent them). You are the design lead; the
owner's verdict was that the graphics "look simple and dated". Hard constraint: ALL art
stays programmatic SwiftUI vector code - no image assets ever. The files:
Sources/UI/Art/CustomerSprite.swift (better silhouettes, venue uniforms, 2-3 keyframe
idle bob), Sources/UI/Art/FoodSprite.swift (per-sprite shading beyond the shared sheen,
serving context), Sources/UI/Art/VenueProps.swift + Sources/UI/VenueStageView.swift
(ambient steam wisps, customer shuffle, per-venue palette push, prestige sign frames at
5/15/40 franchises reading bronze/silver/gold), Sources/UI/Art/CoinBurst.swift (payout
pop-scale, a prestige star-field moment distinct from routine rewards),
Sources/UI/RootView.swift tab bar + Sources/UI/HUDView.swift (bespoke active states,
metallic coin / crystalline gem pills), Sources/UI/Art/Icons.swift app icon + launch
screen last. One surface per commit; build to the iPhone 17 Pro Max simulator and
screenshot before/after EVERY surface, and iterate until it clearly reads richer. 20Hz
engine + TimelineView stays; ambient animation allocation-free and honoring
accessibilityReduceMotion; never strip accessibility labels; xcodegen generate if any
new file is added; full test suite green before each commit.
```

## Before you ship, you personally must

1. Replace `SettingsView.privacyPolicyURL` with your real hosted policy + enter it in ASC.
2. Create the 4 new IAPs in App Store Connect per the updated table in
   docs/AppStoreConnect-IAP-Setup.md (17 products now, prices changed on Grand Opening).
3. Run the StoreKit tests once from Xcode (they skip on CLI).
