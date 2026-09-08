import XCTest
@testable import Fable

/// Covers what a purchase *does to the game* - the half of the shop that does not need StoreKit.
///
/// `StoreTests` exercises the real StoreKit 2 path, and can only do so from Xcode: under
/// `xcodebuild test` product queries never reach the test session, so all twelve of those tests
/// skip and a green CLI run says nothing about purchases at all. That gap is worth closing,
/// because the part most likely to actually be wrong is not StoreKit's behaviour - it is ours.
///
/// The sharp edge is re-delivery. `refreshEntitlements()` re-delivers every non-consumable on
/// each launch, so each of those grants guards its contents behind a `firstTime` check. If one
/// of those guards breaks, nothing fails loudly: the game just hands out gems, managers and a
/// fresh multi-day boost again on every single relaunch, forever. These tests grant twice and
/// assert the second one is inert, which is precisely the scenario a relaunch reproduces.
///
/// Everything here runs anywhere, including on the command line.
@MainActor
final class ShopGrantTests: XCTestCase {

    private var engine: GameEngine!
    private var store: StoreService!

    override func setUp() async throws {
        try await super.setUp()
        engine = GameEngine(state: GameState.newGame(), startTimers: false,
                            persistence: EphemeralPersistence())
        store = StoreService(engine: engine)
    }

    override func tearDown() async throws {
        store = nil
        engine = nil
        try await super.tearDown()
    }

    // MARK: helpers

    /// A product currently on sale.
    private func item(_ reward: ShopReward) throws -> ShopItem {
        try XCTUnwrap(ShopCatalog.all.first { $0.reward == reward },
                      "no catalog item rewards \(reward) - the catalog and ShopReward have drifted")
    }

    /// A product that has been withdrawn from sale but whose grant is still live.
    ///
    /// The Grand Opening Bundle and the Founder's Bundle were cut when the catalog was trimmed
    /// from 17 products to 12, so `ShopCatalog` no longer lists them - but `grant` still handles
    /// both, and it has to: `refreshEntitlements()` re-delivers non-consumables on every launch,
    /// so anyone who bought one *before* it was withdrawn still has that transaction replayed at
    /// them for the life of the install. Their `firstTime` guards are therefore still load-bearing
    /// for real players, and are exactly the code least likely to be exercised by hand again.
    /// Built here rather than looked up, since there is no catalog entry left to find.
    private func retiredItem(_ reward: ShopReward, id: String) -> ShopItem {
        ShopItem(id: id, title: "retired", subtitle: "", reward: reward,
                 fallbackPrice: "", badge: nil, magnitude: 0)
    }

    private func boosts(id: String) -> Int {
        engine.state.activeBoosts.filter { $0.id == id }.count
    }

    // MARK: consumables repeat

    /// Gem packs are Consumable: buying twice must credit twice. This is the control case - if
    /// it ever starts behaving like the guarded grants, the guards have been applied too widely.
    func testGemPacksAreRepeatable() throws {
        let pack = try XCTUnwrap(ShopCatalog.gemPacks.first)
        guard case .gems(let amount) = pack.reward else {
            return XCTFail("first gem pack does not reward gems")
        }
        let before = engine.state.gems

        store.grantForTesting(pack)
        store.grantForTesting(pack)

        XCTAssertEqual(engine.state.gems, before + amount * 2)
    }

    // MARK: non-consumables must not re-grant

    /// The Starter Pack's contents - 500 gems, a manager pack, a 24h x2 boost - sit behind a
    /// `firstTime` check. A relaunch re-delivers the transaction; only the entitlement should
    /// survive the second pass.
    func testStarterPackContentsLandExactlyOnceAcrossRedelivery() throws {
        let starter = try item(.starterPack)
        let gemsBefore = engine.state.gems

        store.grantForTesting(starter)
        let gemsAfterFirst = engine.state.gems
        let boostsAfterFirst = boosts(id: "starter")

        // Second delivery: exactly what `refreshEntitlements()` does on the next launch.
        store.grantForTesting(starter)

        XCTAssertTrue(engine.state.entitlements.starterPack)
        XCTAssertEqual(gemsAfterFirst, gemsBefore + 500, "first grant should credit 500 gems")
        XCTAssertEqual(engine.state.gems, gemsAfterFirst,
                       "re-delivering the Starter Pack granted its gems a second time")
        XCTAssertEqual(boosts(id: "starter"), boostsAfterFirst,
                       "re-delivering the Starter Pack stacked another 24h boost")
    }

    /// Same guard, and the one whose comment in `grant` spells out the failure: 1,500 gems and a
    /// fresh 72h boost on every relaunch forever.
    func testGrandOpeningBundleContentsLandExactlyOnceAcrossRedelivery() throws {
        let bundle = retiredItem(.grandOpeningBundle, id: "com.fable.foodcourt.grandopening")
        let gemsBefore = engine.state.gems

        store.grantForTesting(bundle)
        let gemsAfterFirst = engine.state.gems
        let boostsAfterFirst = boosts(id: "grand-opening")

        store.grantForTesting(bundle)

        XCTAssertTrue(engine.state.entitlements.grandOpeningBundle)
        XCTAssertEqual(gemsAfterFirst, gemsBefore + 1_500)
        XCTAssertEqual(engine.state.gems, gemsAfterFirst,
                       "re-delivering the Grand Opening Bundle granted its gems again")
        XCTAssertEqual(boosts(id: "grand-opening"), boostsAfterFirst,
                       "re-delivering the Grand Opening Bundle stacked another 72h boost")
    }

    /// The most expensive one to get wrong: 12,000 gems, two legendary managers and a week-long
    /// x2, every launch.
    func testFoundersBundleContentsLandExactlyOnceAcrossRedelivery() throws {
        let founders = retiredItem(.foundersBundle, id: "com.fable.foodcourt.founders")
        let gemsBefore = engine.state.gems
        let rosterBefore = engine.state.managers.count

        store.grantForTesting(founders)
        let gemsAfterFirst = engine.state.gems
        let rosterAfterFirst = engine.state.managers.count
        let boostsAfterFirst = boosts(id: "founders")

        store.grantForTesting(founders)

        XCTAssertTrue(engine.state.entitlements.foundersBundle)
        XCTAssertEqual(gemsAfterFirst, gemsBefore + 12_000)
        XCTAssertEqual(rosterAfterFirst, rosterBefore + 2, "should grant two legendary managers")
        XCTAssertEqual(engine.state.gems, gemsAfterFirst,
                       "re-delivering the Founder's Bundle granted its 12,000 gems again")
        XCTAssertEqual(engine.state.managers.count, rosterAfterFirst,
                       "re-delivering the Founder's Bundle granted two more legendaries")
        XCTAssertEqual(boosts(id: "founders"), boostsAfterFirst,
                       "re-delivering the Founder's Bundle stacked another 168h boost")
    }

    // MARK: pure entitlements

    /// VIP and Mogul carry no contents, so re-delivery is naturally idempotent - but they do
    /// move the profit multiplier and the offline cap, and those must not compound.
    func testPureEntitlementsAreIdempotentAndStack() throws {
        let baseCap = engine.state.offlineCapHours
        XCTAssertFalse(engine.state.entitlements.vip)
        XCTAssertFalse(engine.state.entitlements.mogul)

        store.grantForTesting(try item(.vip))
        store.grantForTesting(try item(.vip))

        XCTAssertTrue(engine.state.entitlements.vip)
        XCTAssertEqual(engine.state.entitlements.profitMultiplier,
                       1 + Balance.vipProfitBonus, accuracy: 1e-9,
                       "VIP granted twice compounded its own profit bonus")
        XCTAssertGreaterThan(engine.state.offlineCapHours, baseCap)

        store.grantForTesting(try item(.mogulPass))

        XCTAssertTrue(engine.state.entitlements.mogul)
        // The two are documented as stacking multiplicatively rather than replacing each other.
        XCTAssertEqual(engine.state.entitlements.profitMultiplier,
                       (1 + Balance.vipProfitBonus) * (1 + Balance.mogulProfitBonus),
                       accuracy: 1e-9)
    }

    /// The Carnival Pass had a real bug report against it ("button does nothing"), and the
    /// StoreKit-level test for it is one of the twelve that skip on CLI. This covers the half
    /// that does not need StoreKit.
    func testFestivalPassUnlocksThePremiumTrack() throws {
        XCTAssertFalse(engine.festivalPremiumActive)

        store.grantForTesting(try item(.festivalPass))

        XCTAssertTrue(engine.state.festival.premiumUnlocked)
        XCTAssertTrue(engine.festivalPremiumActive)
    }

    // MARK: the whole catalog

    /// Every catalog entry must actually deliver something. `grant`'s switch is exhaustive, so
    /// the compiler already catches a reward that was never wired up - but a reward wired to the
    /// *wrong* engine call, or to one that silently no-ops, is a product a player pays for and
    /// receives nothing from, and nothing else would catch that.
    ///
    /// `lastSeen` is normalised out before comparing. `grant` ends with `engine.save()`, which
    /// stamps `state.lastSeen`, so a naive equality check would pass for every reward including
    /// one that did nothing at all - the assertion would look thorough and test nothing.
    func testEveryCatalogItemDeliversSomething() throws {
        for entry in ShopCatalog.all {
            let fresh = GameEngine(state: GameState.newGame(), startTimers: false,
                                   persistence: EphemeralPersistence())
            let freshStore = StoreService(engine: fresh)
            let before = fresh.state

            freshStore.grantForTesting(entry)

            var after = fresh.state
            after.lastSeen = before.lastSeen
            XCTAssertNotEqual(before, after,
                              "granting \(entry.id) changed nothing but the save timestamp")
        }
    }
}
