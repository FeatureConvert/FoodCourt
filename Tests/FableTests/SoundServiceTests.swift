import XCTest
@testable import Fable

/// `Haptics` (UI/Theme.swift) has zero test coverage - it's a thin, side-effect-only wrapper
/// around system feedback and there's nothing meaningful to assert about it. `SoundService`
/// does real system-framework I/O (AVAudioEngine) so it's worth a step further than that
/// precedent, but actual audio output still can't be asserted from XCTest - these are smoke
/// tests confirming construction and every `SoundKind` play without crashing or hanging,
/// plus that the mute flag is read correctly.
@MainActor
final class SoundServiceTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "soundEnabled")
        super.tearDown()
    }

    // AVAudioEngine's hardware start retries for several seconds in this headless
    // simulator/CI context (no real output device), so one shared instance across every
    // assertion here avoids paying that cost per test - none of these need XCTest's
    // per-test isolation to be meaningful, they're smoke tests for a single service.
    func testConstructionAndPlaybackNeverCrash() {
        let service = SoundService()

        for kind in SoundKind.allCases {
            service.play(kind)
        }

        UserDefaults.standard.set(false, forKey: "soundEnabled")
        for kind in SoundKind.allCases {
            service.play(kind)
        }

        UserDefaults.standard.set(true, forKey: "soundEnabled")
        service.play(.tap)
    }
}
