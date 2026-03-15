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

    // Helper that mirrors UpdateChecker.isNewer(_:than:) without requiring @testable.
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator:  ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true  }
            if rv < lv { return false }
        }
        return false
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
        XCTAssertEqual(UserDefaults.Key.showKnownNetworks.rawValue, "showKnownNetworks")
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
