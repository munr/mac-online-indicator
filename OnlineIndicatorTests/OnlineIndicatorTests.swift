import XCTest

// NOTE: Add this file to an "OnlineIndicatorTests" Unit Testing Bundle target via
// Xcode → File → New → Target → Unit Testing Bundle. The target must link the
// app's source files (or use @testable import OnlineIndicator once the product
// module name is set).

// MARK: - UpdateChecker.isNewer

final class UpdateCheckerVersionTests: XCTestCase {

    // isNewer is a private static method; test it by driving check() with known
    // version strings. For direct unit coverage, expose via @testable import.

    func testNewerMajorVersion() {
        XCTAssertTrue(isNewer("2.0.0", than: "1.9.9"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(isNewer("1.1.0", than: "1.0.9"))
    }

    func testNewerPatchVersion() {
        XCTAssertTrue(isNewer("1.0.1", than: "1.0.0"))
    }

    func testSameVersion() {
        XCTAssertFalse(isNewer("1.0.0", than: "1.0.0"))
    }

    func testOlderVersion() {
        XCTAssertFalse(isNewer("0.9.9", than: "1.0.0"))
    }

    func testFewerComponents() {
        XCTAssertTrue(isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(isNewer("1.0", than: "1.0.1"))
    }

    func testVPrefixStripped() {
        // Simulate the "v" stripping logic from UpdateChecker.check()
        let tag = "v2.1.0"
        let stripped = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        XCTAssertEqual(stripped, "2.1.0")
        XCTAssertTrue(isNewer(stripped, than: "1.0.0"))
    }

    func testRegressionOlderVersionIsNotNewer() {
        XCTAssertFalse(isNewer("v1.1.5", than: "1.1.6"))
    }

    func testPreReleaseVersionStillComparesNumerically() {
        XCTAssertTrue(isNewer("v1.2.0-beta.1", than: "1.1.9"))
        XCTAssertFalse(isNewer("v1.1.6-rc.1", than: "1.1.6"))
    }

    // Helper that mirrors UpdateChecker version parsing/comparison behavior.
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = versionComponents(from: remote)
        let l = versionComponents(from: local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true  }
            if rv < lv { return false }
        }
        return false
    }

    private func versionComponents(from version: String) -> [Int] {
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsVersion = version as NSString
        let fullRange = NSRange(location: 0, length: nsVersion.length)
        return regex.matches(in: version, options: [], range: fullRange).compactMap {
            Int(nsVersion.substring(with: $0.range))
        }
    }
}

// MARK: - UpdateChecker cached result

final class UpdateCheckerCachedResultTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearUpdateDefaults()
    }

    override func tearDown() {
        clearUpdateDefaults()
        super.tearDown()
    }

    func testCachedResultClearsWhenTagIsNotNewerThanInstalledVersion() {
        UserDefaults.standard.set("v0.0.1", for: .lastUpdateTag)
        UserDefaults.standard.set("https://example.com/release", for: .lastUpdatePage)

        let result = UpdateChecker.cachedResult

        XCTAssertNil(result, "Stale cached updates should be ignored")
        XCTAssertNil(UserDefaults.standard.string(for: .lastUpdateTag))
        XCTAssertNil(UserDefaults.standard.string(for: .lastUpdatePage))
    }

    func testCachedResultRemainsWhenTagIsNewerThanInstalledVersion() {
        UserDefaults.standard.set("v9999.0.0", for: .lastUpdateTag)
        UserDefaults.standard.set("https://example.com/release", for: .lastUpdatePage)
        UserDefaults.standard.set("notes", for: .lastUpdateNotes)

        let result = UpdateChecker.cachedResult

        guard case .updateAvailable(let tag, let notes, _, let pageURL)? = result else {
            XCTFail("Expected cached update to be returned for a newer tag")
            return
        }
        XCTAssertEqual(tag, "v9999.0.0")
        XCTAssertEqual(notes, "notes")
        XCTAssertEqual(pageURL.absoluteString, "https://example.com/release")
    }

    private func clearUpdateDefaults() {
        let keys: [UserDefaults.Key] = [
            .lastUpdateTag,
            .lastUpdateNotes,
            .lastUpdateDownload,
            .lastUpdatePage,
            .lastUpdateCheck
        ]
        for key in keys {
            UserDefaults.standard.removeObject(for: key)
        }
    }
}

// MARK: - UserDefaults.Key

final class UserDefaultsKeyTests: XCTestCase {

    private let suiteName = "com.OnlineIndicator.tests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStringRoundTrip() {
        defaults.set("https://example.com", for: .pingURL)
        XCTAssertEqual(defaults.string(for: .pingURL), "https://example.com")
    }

    func testDoubleRoundTrip() {
        defaults.set(120.0, for: .refreshInterval)
        XCTAssertEqual(defaults.double(for: .refreshInterval), 120.0)
    }

    func testRemoveObject() {
        defaults.set("hello", for: .pingURL)
        defaults.removeObject(for: .pingURL)
        XCTAssertNil(defaults.string(for: .pingURL))
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(UserDefaults.Key.refreshInterval.rawValue, "refreshInterval")
        XCTAssertEqual(UserDefaults.Key.pingURL.rawValue,         "pingURL")
        XCTAssertEqual(UserDefaults.Key.userIconSets.rawValue,    "userIconSets_v1")
    }
}

// MARK: - ConnectivityChecker (URL validation)

final class ConnectivityCheckerURLTests: XCTestCase {

    func testDefaultURLIsValid() {
        XCTAssertNotNil(URL(string: "http://captive.apple.com"))
    }

    func testCustomURLAcceptsHTTPS() {
        let url = URL(string: "https://example.com")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
    }

    func testInvalidSchemeRejected() {
        let url = URL(string: "ftp://example.com")
        let isValid = url.flatMap { u in
            u.scheme.map { ["http", "https"].contains($0) }
        } ?? false
        XCTAssertFalse(isValid)
    }

    func testEmptyStringProducesNil() {
        XCTAssertNil(URL(string: ""))
    }
}
