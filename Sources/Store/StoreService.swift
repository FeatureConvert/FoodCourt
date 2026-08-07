import Foundation
import StoreKit

/// What a product hands the player once the transaction is verified.
enum ShopReward: Equatable {
    case gems(Int)
    case starterPack
    case vip
    case festivalPass
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
        case .gems, .festivalPass: return true
        case .starterPack, .vip: return false
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
    ]

    static let offers: [ShopItem] = [
        ShopItem(id: prefix + "pack.starter", title: "Starter Pack",
                 subtitle: "500 gems · a manager for every open station · 24h double profit",
                 reward: .starterPack, fallbackPrice: "$4.99", badge: "ONE TIME", magnitude: 3),
        ShopItem(id: prefix + "vip.pass", title: "VIP Pass",
                 subtitle: "+25% profit forever · 12h offline earnings · Carnival Pass every season",
                 reward: .vip, fallbackPrice: "$9.99", badge: "BEST VALUE", magnitude: 4),
        ShopItem(id: prefix + "pack.festival", title: "Carnival Pass",
                 subtitle: "Unlocks the premium reward on all 30 festival tiers",
                 reward: .festivalPass, fallbackPrice: "$7.99", badge: "SEASON", magnitude: 3),
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

    init(engine: GameEngine? = nil) {
        self.engine = engine
        listenForTransactions()
    }

    deinit { updatesTask?.cancel() }

    func attach(engine: GameEngine) {
        self.engine = engine
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
        case .gems: return false
        case .starterPack: return engine.state.entitlements.starterPack
        case .vip: return engine.state.entitlements.vip
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
            // Sync throwing usually means the user cancelled the sign-in sheet.
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
        case .unverified:
            // Failed signature check - never grant on these.
            errorMessage = "That purchase couldn't be verified."
        case .verified(let transaction):
            let isNew = processedTransactions.insert(transaction.id).inserted
            if isNew, let item = ShopCatalog.item(for: transaction.productID) {
                grant(item, announce: true)
            }
            // Finishing is what removes the transaction from the queue; skipping it makes
            // StoreKit redeliver it forever.
            await transaction.finish()
        }
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
        }
        engine.save()
    }
}
