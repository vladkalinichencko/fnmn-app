import FNMNCore
import XCTest
@testable import FNMN

final class SpeedProfileTests: XCTestCase {
    private func defaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func key(_ setting: ReaderAppearance.SpeedSetting, _ kind: FNMNCore.Material.Kind) -> String {
        setting.key(kind)
    }

    func testTheSpeedOneHadBecomesBothProfilesOnce() {
        let defaults = defaults()
        defaults.set(420, forKey: ReaderAppearance.speedKey)
        defaults.set(2, forKey: ReaderAppearance.speedWordsKey)
        defaults.set("slight", forKey: ReaderAppearance.speedPausesKey)

        ReaderAppearance.makeSpeedProfiles(in: defaults)

        for kind in [FNMNCore.Material.Kind.article, .book] {
            XCTAssertEqual(defaults.integer(forKey: key(.wordsPerMinute, kind)), 420)
            XCTAssertEqual(defaults.integer(forKey: key(.wordsPerFrame, kind)), 2)
            XCTAssertEqual(defaults.string(forKey: key(.pauses, kind)), "slight")
        }
    }

    func testASecondLaunchLeavesTheProfilesAsTheyAre() {
        let defaults = defaults()
        defaults.set(420, forKey: ReaderAppearance.speedKey)
        ReaderAppearance.makeSpeedProfiles(in: defaults)
        defaults.set(300, forKey: key(.wordsPerMinute, .book))

        ReaderAppearance.makeSpeedProfiles(in: defaults)

        XCTAssertEqual(defaults.integer(forKey: key(.wordsPerMinute, .book)), 300)
    }

    func testAMaterialThatWasNeverReadGetsNoProfile() {
        let defaults = defaults()
        ReaderAppearance.makeSpeedProfiles(in: defaults)
        XCTAssertNil(defaults.object(forKey: key(.wordsPerMinute, .article)))
    }
}
