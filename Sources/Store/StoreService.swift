import Foundation
import StoreKit

/// What a product hands the player once the transaction is verified.
enum ShopReward: Equatable {
    case gems(Int)
    case starterPack
    case vip
    case festivalPass
    /// One guaranteed random Legendary-rarity manager. Guaranteed rarity, not a gacha roll -
    /// only which of the roster's legendaries shows up is random, matching how the free
    /// festival/league legendary grants already work.
    case legendaryManager
    /// The whale bundle: gems + banked income + a long boost. See
    /// `GameEngine.grantFranchiseAccelerator`.
    case accelerator
    /// The one-time anchor purchase. See `GameEngine.grantGrandOpeningBundle`.
    case grandOpeningBundle
    /// Spendable-only stars for research - see `GameEngine.grantResearchStars`. Deliberately
    /// repeatable (Consumable): with the full research tree now a many-months sink, a single
    /// one-time purchase would barely register against it, and the whole point is to let a
    /// player buy back time, not to sell the tree's completion outright.
    case researchGrant
    /// Whale-tier permanent: +50% profit forever (stacks with VIP) and +12h offline cap.
    case mogulPass
    /// Whale-tier consumable: a day of income banked instantly plus x3 profit for 72h.
    /// Everything in it is time-priced, so it stays worth exactly what it says at any
    /// income level - flat coin amounts would be obsolete one board later.
    case timeVault
    /// One-time whale anchor: a gem hoard, two guaranteed Legendaries, and a week of x2.
    case foundersBundle
}

struct ShopItem: Identifiable, Equatable {
    let id: String          // product identifier
    let title: String
    let subtitle: String
    let reward: ShopReward
    /// Shown only when StoreKit has not returned a live price yet.
    let fallbackPrice: String
    let badge: String?
    /// Drives the gem-pile artwork size in the shop.
    let magnitude: Int

    /// Consumables are never restored. The Carnival Pass counts as one: it lasts a single
    /// festival season, so restoring it would hand out every later season free.
    var isConsumable: Bool {
        switch reward {
        case .gems, .festivalPass, .legendaryManager, .accelerator, .researchGrant,
             .timeVault:
            return true
        case .starterPack, .vip, .grandOpeningBundle, .mogulPass, .foundersBundle:
            return false
        }
    }
}

enum ShopCatalog {
    static let prefix = "com.fable.foodcourt."

    static let gemPacks: [ShopItem] = [
        ShopItem(id: prefix + "gems.handful", title: "Handful", subtitle: "100 gems",
                 reward: .gems(100), fallbackPrice: "$0.99", badge: nil, magnitude: 1),
        ShopItem(id: prefix + "gems.pouch", title: "Pouch", subtitle: "550 gems",
                 reward: .gems(550), fallbackPrice: "$4.99", badge: "+10%", magnitude: 2),
        ShopItem(id: prefix + "gems.chest", title: "Chest", subtitle: "1,200 gems",
                 reward: .gems(1200), fallbackPrice: "$9.99", badge: "+20%", magnitude: 3),
        ShopItem(id: prefix + "gems.vault", title: "Vault", subtitle: "3,300 gems",
                 reward: .gems(3300), fallbackPrice: "$24.99", badge: "+35%", magnitude: 4),
        ShopItem(id: prefix + "gems.hoard", title: "Hoard", subtitle: "7,500 gems",
                 reward: .gems(7500), fallbackPrice: "$49.99", badge: "+50%", magnitude: 4),
        ShopItem(id: prefix + "gems.empire", title: "Empire", subtitle: "18,000 gems",
                 reward: .gems(18000), fallbackPrice: "$99.99", badge: "+80%", magnitude: 4),
        // The whale tier of the gem ladder. 225 gems/$ keeps the value-per-dollar curve
        // strictly rising (Empire is 180/$), so no lower pack is ever the smarter buy at
        // this price point.
        ShopItem(id: prefix + "gems.dynasty", title: "Dynasty", subtitle: "45,000 gems",
                 reward: .gems(45000), fallbackPrice: "$199.99", badge: "+125%", magnitude: 4),
    ]

    static let offers: [ShopItem] = [
        ShopItem(id: prefix + "pack.starter", title: "Starter Pack",
                 subtitle: "500 gems · a manager for every open station · 24h double profit",
                 reward: .starterPack, fallbackPrice: "$4.99", badge: "ONE TIME", magnitude: 3),
        ShopItem(id: prefix + "vip.pass", title: "VIP Pass",
                 subtitle: "+25% profit forever · 12h offline earnings · Carnival Pass every season",
                 reward: .vip, fallbackPrice: "$14.99", badge: "BEST VALUE", magnitude: 4),
        ShopItem(id: prefix + "pack.festival", title: "Carnival Pass",
                 subtitle: "Premium reward on all 30 tiers · this season only",
                 reward: .festivalPass, fallbackPrice: "$3.99", badge: "THIS SEASON", magnitude: 2),
        ShopItem(id: prefix + "pack.legendary", title: "Legendary Chef Crate",
                 subtitle: "One guaranteed Legendary manager, instantly",
                 reward: .legendaryManager, fallbackPrice: "$9.99", badge: "GUARANTEED", magnitude: 4),
        ShopItem(id: prefix + "pack.accelerator", title: "Franchise Accelerator",
                 subtitle: "2,500 gems · 8 hours of income banked now · ×2 profit for 48h",
                 reward: .accelerator, fallbackPrice: "$19.99", badge: "BUNDLE", magnitude: 4),
        // $14.99, up from $9.99: at the same price as the plain 1,200-gem Chest, this
        // bundle's 1,500 gems PLUS managers PLUS 72h of double profit made Chest strictly
        // dominated - no first $9.99 should have two answers where one is always wrong.
        ShopItem(id: prefix + "pack.grandopening", title: "Grand Opening Bundle",
                 subtitle: "1,500 gems · a manager for every open station in every venue · ×2 for 72h",
                 reward: .grandOpeningBundle, fallbackPrice: "$14.99", badge: "ONE TIME", magnitude: 3),
        ShopItem(id: prefix + "pack.research", title: "Research Grant",
                 subtitle: "Research stars scaled to your empire - 60% of your last Franchise, repeatable",
                 reward: .researchGrant, fallbackPrice: "$9.99", badge: "SHORTCUT", magnitude: 2),
        ShopItem(id: prefix + "vip.mogul", title: "Mogul Pass",
                 subtitle: "+50% profit forever · +12h offline cap · stacks with VIP",
                 reward: .mogulPass, fallbackPrice: "$49.99", badge: "PERMANENT", magnitude: 4),
        ShopItem(id: prefix + "pack.timevault", title: "Time Vault",
                 subtitle: "A full day of income banked now · ×3 profit for 72h",
                 reward: .timeVault, fallbackPrice: "$39.99", badge: "BUNDLE", magnitude: 4),
        ShopItem(id: prefix + "pack.founders", title: "Founder's Bundle",
                 subtitle: "12,000 gems · 2 Legendary managers · ×2 profit for 7 days",
                 reward: .foundersBundle, fallbackPrice: "$99.99", badge: "ONE TIME", magnitude: 4),
    ]

    static let all: [ShopItem] = offers + gemPacks
    static var productIDs: [String] { all.map(\.id) }

    static func item(for id: String) -> ShopItem? { all.first { $0.id == id } }
}

@MainActor
final class StoreService: ObservableObject {

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchasingID: String?
    @Published var errorMessage: String?
    /// Shown as a toast after a successful grant.
    @Published var lastGrant: String?

    private weak var engine: GameEngine?
    private var updatesTask: Task<Void, Never>?
    /// A transaction can arrive both as the result of `purchase()` and through
    /// `Transaction.updates`. Granting gems twice for one payment would be a real bug, so
    /// every id is only ever honoured once.
    private var processedTransactions: Set<UInt64> = []
    /// Verified transactions that arrived before `attach(engine:)` ran. `Transaction.updates`
    /// starts delivering in `init`, but the app wires the engine in a later `.task` - and
    /// finishing a consumable in that window without granting it would eat a paid purchase
    /// permanently. Held un-finished here and drained the moment the engine attaches;
    /// if the app dies first, StoreKit simply redelivers on next launch.
    private var deferredTransactions: [Transaction] = []

    init(engine: GameEngine? = nil) {
        self.engine = engine
        listenForTransactions()
    }

    deinit { updatesTask?.cancel() }

    func attach(engine: GameEngine) {
        self.engine = engine
        let queued = deferredTransactions
        deferredTransactions = []
        for transaction in queued {
            Task { await self.deliver(transaction) }
        }
    }

    // MARK: Products

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: ShopCatalog.productIDs)
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        } catch {
            // The shop still renders with fallback prices; an empty store is worse than a
            // slightly stale one.
            errorMessage = "Couldn't reach the store. Showing standard prices."
        }
    }

    /// Live localized price when StoreKit has it, catalog price otherwise.
    func displayPrice(for item: ShopItem) -> String {
        products[item.id]?.displayPrice ?? item.fallbackPrice
    }

    func isOwned(_ item: ShopItem) -> Bool {
        guard let engine else { return false }
        switch item.reward {
        case .gems, .legendaryManager, .accelerator, .researchGrant, .timeVault: return false
        case .starterPack: return engine.state.entitlements.starterPack
        case .vip: return engine.state.entitlements.vip
        case .grandOpeningBundle: return engine.state.entitlements.grandOpeningBundle
        case .mogulPass: return engine.state.entitlements.mogul
        case .foundersBundle: return engine.state.entitlements.foundersBundle
        // Per-season, so it stops reading as owned once the season rolls - unless the
        // player holds VIP, which includes it and makes buying it separately pointless.
        case .festivalPass: return engine.festivalPremiumActive
        }
    }

    // MARK: Purchase

    func purchase(_ item: ShopItem) async {
        guard purchasingID == nil else { return }
        guard let product = products[item.id] else {
            errorMessage = "That item isn't available right now."
            return
        }
        purchasingID = item.id
        defer { purchasingID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await finalize(verification)
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            // Sync throwing usually means the user cancelled the sign-in sheet - stay
            // silent rather than toasting either success or failure for their own cancel.
            return
        }
        await refreshEntitlements()
        lastGrant = "Purchases restored"
    }

    /// Re-applies non-consumables on every launch so a reinstall or a new device keeps VIP.
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let item = ShopCatalog.item(for: transaction.productID),
                  !item.isConsumable else { continue }
            grant(item, announce: false)
        }
    }

    // MARK: Transaction plumbing

    private func listenForTransactions() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.finalize(update)
            }
        }
    }

    private func finalize(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .unverified(let transaction, _):
            // Failed signature check - never grant on these. But finish anyway: a
            // transaction that fails verification will never pass by waiting, and leaving
            // it in the queue redelivered it (and this error toast) on every launch forever.
            errorMessage = "That purchase couldn't be verified."
            await transaction.finish()
        case .verified(let transaction):
            await deliver(transaction)
        }
    }

    /// Grants and finishes one verified transaction - unless the engine isn't wired yet,
    /// in which case the transaction is parked un-finished (see `deferredTransactions`).
    private func deliver(_ transaction: Transaction) async {
        guard engine != nil else {
            deferredTransactions.append(transaction)
            return
        }
        let isNew = processedTransactions.insert(transaction.id).inserted
        if isNew, let item = ShopCatalog.item(for: transaction.productID) {
            grant(item, announce: true)
        }
        // Finishing is what removes the transaction from the queue; skipping it makes
        // StoreKit redeliver it forever.
        await transaction.finish()
    }

    private func grant(_ item: ShopItem, announce: Bool) {
        guard let engine else { return }
        switch item.reward {
        case .gems(let amount):
            engine.addGems(amount)
            if announce { lastGrant = "+\(Format.count(amount)) gems" }

        case .starterPack:
            let firstTime = !engine.state.entitlements.starterPack
            engine.setEntitlement(starterPack: true)
            if firstTime {
                engine.addGems(500)
                engine.grantManagerPack(venue: 0)
                engine.addBoost(id: "starter", label: "Starter ×2", multiplier: 2, hours: 24)
            }
            if announce { lastGrant = "Starter Pack unlocked" }

        case .vip:
            engine.setEntitlement(vip: true)
            if announce { lastGrant = "VIP Pass active" }

        case .festivalPass:
            engine.unlockFestivalPremium()
            if announce { lastGrant = "Carnival Pass unlocked" }

        case .legendaryManager:
            let spec = engine.grantManager(rarity: .legendary)
            if announce { lastGrant = "\(spec.name) joins your roster!" }

        case .accelerator:
            let earned = engine.grantFranchiseAccelerator()
            if announce { lastGrant = "+2,500 gems · \(Format.currency(earned)) coins · ×2 for 48h" }

        case .grandOpeningBundle:
            // Non-consumable: refreshEntitlements() re-delivers this transaction on every
            // launch, so the grant must only fire the first time or it would hand out a
            // fresh 1,500 gems and a fresh 72h boost on every relaunch forever.
            let firstTime = !engine.state.entitlements.grandOpeningBundle
            engine.setEntitlement(grandOpeningBundle: true)
            if firstTime { engine.grantGrandOpeningBundle() }
            if announce { lastGrant = "Grand Opening Bundle unlocked" }

        case .researchGrant:
            let stars = engine.researchGrantStars
            engine.grantResearchStars(stars)
            if announce { lastGrant = "+\(Format.count(stars)) research stars" }

        case .mogulPass:
            // Pure entitlement, so re-delivery on every launch is naturally idempotent.
            engine.setEntitlement(mogul: true)
            if announce { lastGrant = "Mogul Pass active" }

        case .timeVault:
            let earned = engine.timeWarp(hours: 24)
            engine.addBoost(id: "time-vault", label: "Time Vault ×3", multiplier: 3, hours: 72)
            if announce { lastGrant = "+\(Format.currency(earned)) coins · ×3 for 72h" }

        case .foundersBundle:
            // Non-consumable: refreshEntitlements() re-delivers on every launch, so the
            // contents must only land once - same guard as the Grand Opening Bundle.
            let firstTime = !engine.state.entitlements.foundersBundle
            engine.setEntitlement(foundersBundle: true)
            if firstTime {
                engine.addGems(12_000)
                _ = engine.grantManager(rarity: .legendary)
                _ = engine.grantManager(rarity: .legendary)
                engine.addBoost(id: "founders", label: "Founder's ×2", multiplier: 2, hours: 168)
            }
            if announce { lastGrant = "Founder's Bundle unlocked" }
        }
        engine.save()
    }
}
