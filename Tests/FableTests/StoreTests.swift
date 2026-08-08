import XCTest
import StoreKitTest
@testable import Fable

/// Exercises the real StoreKit 2 code path against the local configuration file, so the
/// purchase, grant, finish, and restore flow is verified without App Store Connect.
///
/// These only run when a StoreKit test environment is actually active. Xcode applies the
/// scheme's StoreKit configuration when it runs the tests; `xcodebuild test` from the
/// command line does not, and there is no flag that makes it, so on CLI runs the products
/// come back empty and every test here skips rather than reporting a false failure.
/// Run them from Xcode (Product > Test) to exercise purchases for real.
@MainActor
final class StoreTests: XCTestCase {

    private var session: SKTestSession!
    private var engine: GameEngine!
    private var store: StoreService!

    override func setUp() async throws {
        try await super.setUp()
        session = try? SKTestSession(configurationFileNamed: "Products")
        session?.resetToDefaultState()
        session?.clearTransactions()
        session?.disableDialogs = true

        engine = GameEngine(state: GameState.newGame(), startTimers: false,
                            persistence: EphemeralPersistence())
        store = StoreService(engine: engine)
        await store.loadProducts()

        try XCTSkipIf(store.products.isEmpty,
                      "No StoreKit test environment - run from Xcode so the scheme's StoreKit configuration applies.")
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        store = nil
        engine = nil
        try await super.tearDown()
    }

    func testEveryCatalogItemHasAMatchingProduct() {
        XCTAssertEqual(store.products.count, ShopCatalog.productIDs.count,
                       "a catalog entry with no StoreKit product would render as unbuyable")
        for item in ShopCatalog.all {
            XCTAssertNotNil(store.products[item.id], item.id)
            // Live price should win over the hardcoded fallback.
            XCTAssertFalse(store.displayPrice(for: item).isEmpty)
        }
    }

    func testBuyingAGemPackCreditsGemsExactlyOnce() async throws {
        let pack = ShopCatalog.gemPacks[0]          // 100 gems
        let before = engine.state.gems

        await store.purchase(pack)

        XCTAssertEqual(engine.state.gems, before + 100)
        // Nothing should be left unfinished in the queue.
        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        XCTAssertEqual(unfinished, 0, "consumables must be finished after granting")
    }

    func testRepeatedGemPurchasesAccumulate() async throws {
        let pack = ShopCatalog.gemPacks[1]          // 550 gems
        let before = engine.state.gems

        await store.purchase(pack)
        await store.purchase(pack)

        XCTAssertEqual(engine.state.gems, before + 1100)
    }

    func testVIPUnlocksProfitBonusAndLongerOfflineCap() async throws {
        XCTAssertFalse(engine.state.entitlements.vip)
        XCTAssertEqual(engine.state.offlineCapHours, Balance.offlineCapHours)

        guard let vip = ShopCatalog.offers.first(where: { $0.reward == .vip }) else {
            return XCTFail("missing VIP offer")
        }
        await store.purchase(vip)

        XCTAssertTrue(engine.state.entitlements.vip)
        XCTAssertEqual(engine.state.offlineCapHours, Balance.offlineCapHoursVIP)
        XCTAssertEqual(engine.state.globalMultiplier, 1 + Balance.vipProfitBonus, accuracy: 1e-9)
        XCTAssertTrue(store.isOwned(vip))
    }

    func testStarterPackGrantsGemsManagersAndABoost() async throws {
        // Open a second station so the manager pack has something to staff.
        engine.addCoins(10_000)
        engine.buyQuantity = .x1
        XCTAssertTrue(engine.buy(station: 1))

        guard let starter = ShopCatalog.offers.first(where: { $0.reward == .starterPack }) else {
            return XCTFail("missing starter pack")
        }
        let gemsBefore = engine.state.gems
        await store.purchase(starter)

        XCTAssertTrue(engine.state.entitlements.starterPack)
        XCTAssertEqual(engine.state.gems, gemsBefore + 500)
        XCTAssertTrue(engine.state.venues[0].stations[0].hasManager)
        XCTAssertTrue(engine.state.venues[0].stations[1].hasManager)
        XCTAssertEqual(engine.state.activeBoosts.count, 1)
        XCTAssertEqual(engine.state.activeBoosts.first?.multiplier, 2)
    }

    func testNonConsumablesComeBackOnAFreshInstall() async throws {
        guard let vip = ShopCatalog.offers.first(where: { $0.reward == .vip }) else {
            return XCTFail("missing VIP offer")
        }
        await store.purchase(vip)

        // Simulate a reinstall: brand new engine and store, same StoreKit account.
        let reinstalled = GameEngine(state: GameState.newGame(), startTimers: false,
                                     persistence: EphemeralPersistence())
        let freshStore = StoreService(engine: reinstalled)
        XCTAssertFalse(reinstalled.state.entitlements.vip)

        await freshStore.refreshEntitlements()
        XCTAssertTrue(reinstalled.state.entitlements.vip, "VIP should restore from entitlements")
    }

    func testConsumablesAreNotRestored() async throws {
        await store.purchase(ShopCatalog.gemPacks[0])

        let reinstalled = GameEngine(state: GameState.newGame(), startTimers: false,
                                     persistence: EphemeralPersistence())
        let freshStore = StoreService(engine: reinstalled)
        let before = reinstalled.state.gems

        await freshStore.refreshEntitlements()
        XCTAssertEqual(reinstalled.state.gems, before,
                       "restoring must never re-grant spent consumables")
    }

    func testBuyingTheBiggestGemPackCreditsCorrectly() async throws {
        guard let empire = ShopCatalog.gemPacks.first(where: { $0.id.hasSuffix("gems.empire") }) else {
            return XCTFail("missing the Empire gem pack")
        }
        let before = engine.state.gems
        await store.purchase(empire)
        XCTAssertEqual(engine.state.gems, before + 18_000)
    }

    func testLegendaryChefCrateGrantsALegendaryManagerAndIsRepeatable() async throws {
        guard let crate = ShopCatalog.offers.first(where: { $0.reward == .legendaryManager }) else {
            return XCTFail("missing the Legendary Chef Crate")
        }
        await store.purchase(crate)
        XCTAssertEqual(engine.state.managers.count, 1)
        XCTAssertEqual(engine.state.managers.first?.spec.rarity, .legendary)
        XCTAssertFalse(store.isOwned(crate), "repeatable - must never lock as OWNED")

        // Buying it again should recruit a second legendary, not silently no-op.
        await store.purchase(crate)
        XCTAssertEqual(engine.state.managers.count, 2)
    }

    func testFranchiseAcceleratorGrantsTheFullBundle() async throws {
        engine.hireManager(for: 0, free: true)   // give automatedRate something to bank

        guard let accelerator = ShopCatalog.offers.first(where: { $0.reward == .accelerator }) else {
            return XCTFail("missing the Franchise Accelerator")
        }
        let gemsBefore = engine.state.gems
        let coinsBefore = engine.state.coins

        await store.purchase(accelerator)

        XCTAssertEqual(engine.state.gems, gemsBefore + 2_500)
        XCTAssertGreaterThan(engine.state.coins, coinsBefore)
        XCTAssertEqual(engine.state.activeBoosts.first { $0.id == "accelerator" }?.multiplier, 2)
    }

    func testFailedPurchaseGrantsNothing() async throws {
        // failTransactionsEnabled was deprecated in iOS 17 with no replacement property;
        // the modern equivalent targets a specific API and takes a real StoreKitError.
        try await session?.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        let before = engine.state.gems

        await store.purchase(ShopCatalog.gemPacks[2])

        XCTAssertEqual(engine.state.gems, before)
        XCTAssertNotNil(store.errorMessage)
    }
}
