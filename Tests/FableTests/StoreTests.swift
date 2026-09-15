import XCTest
import StoreKitTest
@testable import Fable

/// Exercises the real StoreKit 2 code path against the local configuration file, so the
/// purchase, grant, finish, and restore flow is verified without App Store Connect.
///
/// These only run when a StoreKit test environment is actually active, which the `XCTSkipIf`
/// in `setUp` checks for by seeing whether any products loaded. **Run them from Xcode
/// (Product > Test) to exercise purchases for real.**
///
/// On a freshly booted simulator, `xcodebuild test` does not route product queries to the test
/// session: the products come back empty and all twelve tests skip rather than reporting a false
/// failure. **A green `xcodebuild test` therefore says nothing whatsoever about the purchase
/// path.** Treat CLI runs as having zero IAP coverage.
///
/// What has been ruled out, so nobody spends the afternoon again:
///
/// - Not a dangling reference. `Fable.xctestplan` carries a `storeKitConfigurationFileReference`
///   and `Scripts/generate.sh` patches the same reference into the scheme's Test action; the
///   identifier it points at is a live `PBXFileReference` in the generated project. Both are
///   wired correctly and neither is sufficient.
/// - Not a missing configuration file. `Products.storekit` is copied into the test bundle by
///   `project.yml`, and `SKTestSession(configurationFileNamed:)` reports **created OK**. The
///   session exists; `Product.products(for:)` just resolves 0 of 12 against it.
/// - Not the daemon needing to warm up. A bounded retry - twelve attempts over six seconds -
///   resolved nothing on every cold-booted run, and only added about a minute per run before
///   skipping anyway. It was removed.
///
/// So the gap is in how `xcodebuild` launches the host versus how Xcode's own runner does, and
/// it is not closable from inside this file. If CLI coverage matters, the realistic options are
/// a UI-test host, or moving the grant/entitlement assertions off StoreKit onto a seam that can
/// be driven directly - most of what these tests actually assert is `GameEngine` state after a
/// grant, not StoreKit's own behaviour.
///
/// **The failure mode worth knowing about is the in-between state.** If the simulator's StoreKit
/// daemon has been primed by earlier activity in the same boot - repeated installs, launches and
/// test runs will do it - then products *do* resolve, the skip does not fire, and these tests run
/// against a half-configured session. In that state `SKTestSession` is unreliable: a *different*
/// case fails on each run, cases take two to three minutes, and the log fills with
/// `SKInternalErrorDomain Code=3` ("Error deleting all transactions", "Error clearing
/// overrides"). It is a harness fault rather than a grant-path bug - no transaction is vended at
/// all, so the observed failure is gems sitting at their starting 25 rather than landing on a
/// wrong number. Reproduced identically on a clean checkout of `84a0169`, so it is not a
/// regression in the app. Shutting the simulator down and booting it again restores the clean
/// skip behaviour.
///
/// So: a red StoreTests on CLI means the simulator needs restarting, not that the store broke.
@MainActor
final class StoreTests: XCTestCase {

    private var session: SKTestSession!
    private var engine: GameEngine!
    private var store: StoreService!

    /// Why the session could not be created, if it could not. Kept so the skip can say what
    /// actually went wrong instead of "no StoreKit test environment", which is a symptom and
    /// sent this investigation down two wrong paths before anyone looked at the real error.
    private var sessionError: Error?

    override func setUp() async throws {
        try await super.setUp()
        do {
            session = try SKTestSession(configurationFileNamed: "Products")
        } catch {
            sessionError = error
        }
        session?.resetToDefaultState()
        session?.clearTransactions()
        session?.disableDialogs = true

        engine = GameEngine(state: GameState.newGame(), startTimers: false,
                            persistence: EphemeralPersistence())
        store = StoreService(engine: engine)

        // Fetched once, deliberately. A bounded retry was tried here and removed: on a cleanly
        // booted simulator, twelve attempts over six seconds resolved nothing, every time, so
        // this is not the daemon needing a moment to warm up. All it bought was ~67s added to
        // every CLI run before skipping anyway.
        await store.loadProducts()

        try XCTSkipIf(store.products.isEmpty, """
            No StoreKit test environment, so the purchase path is NOT covered by this run.
            SKTestSession: \(sessionError.map { "failed - \($0)" } ?? (session == nil ? "nil, no error" : "created OK"))
            Products requested: \(ShopCatalog.productIDs.count), resolved: \(store.products.count)
            Run from Xcode (Product > Test) to exercise purchases for real.
            """)
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
        let pack = ShopCatalog.gemPacks[0]          // Handful, 500 gems
        let before = engine.state.gems

        await store.purchase(pack)

        XCTAssertEqual(engine.state.gems, before + 500)
        // Nothing should be left unfinished in the queue.
        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        XCTAssertEqual(unfinished, 0, "consumables must be finished after granting")
    }

    func testRepeatedGemPurchasesAccumulate() async throws {
        let pack = ShopCatalog.gemPacks[1]          // Pouch, 3,000 gems
        let before = engine.state.gems

        await store.purchase(pack)
        await store.purchase(pack)

        XCTAssertEqual(engine.state.gems, before + 6000)
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

    /// Robert reported the Carnival Pass button under Events doing nothing on-device. The
    /// button itself (EventsView.purchasePremiumPass) calls the exact same `store.purchase`
    /// every other IAP button does, and reading the whole path (grant -> unlockFestivalPremium
    /// -> state.festival.premiumUnlocked) didn't turn up a bug - this exercises it end to end
    /// against the real StoreKit 2 code path to either confirm that or catch what reading
    /// the code missed.
    func testCarnivalPassUnlocksPremiumFestivalTrack() async throws {
        XCTAssertFalse(engine.festivalPremiumActive)

        guard let pass = ShopCatalog.item(for: Festival.premiumProductID) else {
            return XCTFail("Carnival Pass product missing from the catalog")
        }
        await store.purchase(pass)

        XCTAssertNil(store.errorMessage, "purchase reported an error: \(store.errorMessage ?? "")")
        XCTAssertTrue(engine.state.festival.premiumUnlocked)
        XCTAssertTrue(engine.festivalPremiumActive)
        XCTAssertTrue(store.isOwned(pass))
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
        XCTAssertTrue(engine.state.venues[0].stations[0].isStaffed)
        XCTAssertTrue(engine.state.venues[0].stations[1].isStaffed)
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
        guard let hoard = ShopCatalog.gemPacks.first(where: { $0.id.hasSuffix("gems.hoard") }) else {
            return XCTFail("missing the Hoard gem pack")
        }
        let before = engine.state.gems
        await store.purchase(hoard)
        XCTAssertEqual(engine.state.gems, before + 45_000)
    }

    // Legendary Chef Crate and Franchise Accelerator are cut from sale (see
    // ShopCatalog.retired) - there's no longer a StoreKit purchase flow to test for either.
    // Their grant mechanics stay covered directly: ShopGrantTests.testPureEntitlementsIs...
    // (via retiredItem) isn't the right fit since both are consumables, but
    // FeatureTests.testLegendaryChefCrateGrantsAGuaranteedLegendary and
    // testFranchiseAcceleratorGrantsAllThreeRewards exercise the engine calls directly.

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
