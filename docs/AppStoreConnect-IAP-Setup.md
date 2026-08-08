# Setting up real In-App Purchases in App Store Connect

Everything on the code side is done — `Sources/Store/StoreService.swift` and
`Sources/Store/Products.storekit` already know about all 12 products. **Nothing in this
document requires touching code.** It's the steps to make those same 12 products exist for
real on Apple's side, which only you can do (it needs your Apple Developer account, your
banking details, and your agreement signatures — none of which I can enter on your behalf).

Once the real products exist and are approved, the app doesn't need a single line changed:
StoreKit fetches by product ID, and the IDs below are already exactly what the code asks for.
The local `Products.storekit` file stays in the project *only* for Xcode's test runner — the
shipped app never reads it.

## 0. Before you touch In-App Purchases at all

Two gates, both one-time:

1. **Apple Developer Program enrollment** — $99/year, if you haven't already. Without this
   there's no App Store Connect access at all.
2. **Paid Apps Agreement + tax + banking** — App Store Connect →
   **Agreements, Tax, and Banking**. Apple will not let a paid IAP go live — not even
   approve it — until this section shows Active, with a bank account and tax forms on file.
   This can take a few days to process, so do it *first*, before creating products, so it's
   not the thing blocking launch at the end.

Free apps with **zero** paid IAP don't need this section. The moment you add one paid
product, you do.

## 1. Create the app record (if you haven't)

App Store Connect → **Apps** → **+** → **New App**. iOS platform, the bundle ID
`com.fable.foodcourt` (must match what's in `project.yml`), pick a name. In-App Purchase
capability doesn't need a separate entitlement or Xcode capability toggle — it's available to
every app by default once the app record exists.

## 2. Create the 12 products

App Store Connect → your app → **Monetization** → **In-App Purchases** (older ASC layouts
call this tab **Features → In-App Purchases** — same place, different label depending on
when you're reading this).

For each row below: **+** → pick the **Type** shown → fill in exactly the **Product ID**,
**Reference Name**, and **Price** shown. Reference Name is internal (you'll see it in
reports, not the player) — Product ID is what actually matters and **must match exactly**,
character for character, or the app will never find the product.

| Product ID | Type | Price | Reference Name | Display Name (en-US) |
|---|---|---|---|---|
| `com.fable.foodcourt.gems.handful` | Consumable | $0.99 | Handful of Gems | Handful of Gems |
| `com.fable.foodcourt.gems.pouch` | Consumable | $4.99 | Pouch of Gems | Pouch of Gems |
| `com.fable.foodcourt.gems.chest` | Consumable | $9.99 | Chest of Gems | Chest of Gems |
| `com.fable.foodcourt.gems.vault` | Consumable | $24.99 | Vault of Gems | Vault of Gems |
| `com.fable.foodcourt.gems.hoard` | Consumable | $49.99 | Hoard of Gems | Hoard of Gems |
| `com.fable.foodcourt.gems.empire` | Consumable | $99.99 | Empire of Gems | Empire of Gems |
| `com.fable.foodcourt.pack.starter` | Non-Consumable | $4.99 | Starter Pack | Starter Pack |
| `com.fable.foodcourt.pack.festival` | Consumable | $3.99 | Carnival Pass | Carnival Pass |
| `com.fable.foodcourt.pack.legendary` | Consumable | $9.99 | Legendary Chef Crate | Legendary Chef Crate |
| `com.fable.foodcourt.pack.accelerator` | Consumable | $19.99 | Franchise Accelerator | Franchise Accelerator |
| `com.fable.foodcourt.pack.grandopening` | Non-Consumable | $9.99 | Grand Opening Bundle | Grand Opening Bundle |
| `com.fable.foodcourt.vip.pass` | Non-Consumable | $14.99 | VIP Pass | VIP Pass |

**Consumable vs. Non-Consumable matters and must match the table exactly.** Get it wrong and
either the purchase won't restore when it should (VIP/Starter Pack must be Non-Consumable),
or a one-time unlock will incorrectly show as re-buyable forever. This is the one field ASC
won't let you change after creation — pick wrong and you'll delete and recreate the product
with a fresh ID.

For each product's **Description** field (shown to Apple's reviewer, not to players — the
in-app copy is native to the app), the one-liners already in `Products.storekit` work
directly:

- Handful — *A handful of gems to keep the fryers hot.*
- Pouch — *A pouch of gems for the ambitious owner.*
- Chest — *A chest of gems. Best everyday value.*
- Vault — *A vault of gems for serious franchise builders.*
- Hoard — *A hoard of gems for players building an empire fast.*
- Empire — *The biggest gem pack. For the truly dedicated owner.*
- Starter Pack — *500 gems, a manager for every open station, and 24 hours of double profit.*
- Carnival Pass — *Unlocks the premium reward on all 30 festival tiers for this season.*
- Legendary Chef Crate — *One guaranteed Legendary-rarity manager, instantly.*
- Franchise Accelerator — *2,500 gems, 8 hours of income banked instantly, and double profit for 48 hours.*
- Grand Opening Bundle — *1,500 gems, a manager for every open station in every venue you've unlocked, and double profit for 72 hours.*
- VIP Pass — *Permanent +25% profit, 12 hour offline earnings, and the Carnival Pass every season.*

**VIP Pass only**: turn on **Family Sharing** for it (matches `familyShareable: true` in the
local config) — the rest should stay off.

### Screenshot requirement

Every IAP needs one App Review screenshot showing it in context in the app (App Store
Connect will ask for it per-product, minimum roughly 640×920px). A screenshot of the Shop
sheet with that product's row visible satisfies this for all 12 — you can reuse the same one
or two shop screenshots across every product, Apple doesn't require a unique image per item.

## 3. Test with a Sandbox account before anything goes live

Don't test with your real Apple ID.

1. App Store Connect → **Users and Access** → **Sandbox** → **Testers** → create one with an
   email that isn't tied to a real Apple ID (a `+sandbox` alias on an existing address works
   fine, e.g. `you+sandbox@icloud.com`).
2. On a real device (sandbox purchases don't need the simulator — you've already got that
   covered locally via `Products.storekit`): **Settings → App Store → Sandbox Account**
   (iOS 18 and earlier: **Settings → App Store**, scroll down) → sign in with that tester.
3. Build and run the real app from Xcode onto that device, open the Shop, buy something.
   You'll see "[Environment: Sandbox]" in the system purchase sheet — that confirms you're
   not being charged. Confirm the product grants correctly and, for VIP, confirm **Restore
   Purchases** brings it back after deleting and reinstalling the app.

Sandbox purchases work as soon as products are saved in ASC — they do **not** need to be
Apple-approved first, so you can fully test the whole store before ever submitting.

## 4. Submit

New IAPs are reviewed **alongside an app binary** — App Store Connect won't send them for
review by themselves the very first time. When you submit the app version for review, you'll
see a prompt to select which "Ready to Submit" IAPs to include. Select all 12.

After that first approval, adding a *new* IAP later can go through review on its own,
without needing a fresh app binary.

## 5. Nothing else changes

Once the products show **Approved** in App Store Connect, the shipped app works exactly as
it does in local testing today — same product IDs, same `ShopCatalog`, same grant logic in
`StoreService.grant(_:announce:)`. There is no separate "go live" switch to flip in code.

---

## If you want a subscription later

None of the 12 products above are subscriptions — everything is a one-time consumable or
non-consumable, matching how `Sources/Core/Balance.swift` and the store layer are built
today. If you later want a recurring "VIP, but monthly" tier instead of (or alongside) the
one-time VIP Pass, that's a materially different setup: a **Subscription Group** in App Store
Connect, an **Auto-Renewable Subscription** product type, and StoreKit code that reads
`Product.SubscriptionInfo` / renewal status rather than a flat "owns it forever" flag. That's
real additional engineering, not a config change — flag it separately if you want to pursue
it, rather than treating it as part of this list.
