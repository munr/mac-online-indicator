import XCTest
@testable import Online_Indicator

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

// MARK: - Probe targets

final class ProbeTargetTests: XCTestCase {

    func testParseTargetsSplitsOnCommasAndWhitespace() {
        XCTAssertEqual(
            ConnectivityChecker.parseTargets("https://a.com, https://b.com  http://c.com"),
            ["https://a.com", "https://b.com", "http://c.com"]
        )
    }

    func testParseTargetsEmpty() {
        XCTAssertTrue(ConnectivityChecker.parseTargets("  ").isEmpty)
    }

    func testSummaryAllOK() {
        let r = ProbeResult(reachable: true, latencyMs: 20, total: 3, failedHosts: [], captivePortal: false)
        XCTAssertEqual(r.summary, "3/3 OK")
    }

    func testSummaryNamesFirstFailureAndCountsRest() {
        let r = ProbeResult(reachable: true, latencyMs: 20, total: 3, failedHosts: ["a.com", "b.com"], captivePortal: false)
        XCTAssertEqual(r.summary, "1/3 OK · a.com +1")
    }
}

// MARK: - ConnectionHistory

final class ConnectionHistoryTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testNoOutageYet() {
        let h = ConnectionHistory()
        h.record(.connected, at: t0)
        XCTAssertNil(h.summary())
    }

    func testOngoingOutageThenRecovery() {
        let h = ConnectionHistory()
        h.record(.connected, at: t0)
        h.record(.blocked, at: t0.addingTimeInterval(60))
        XCTAssertTrue(h.summary()?.hasPrefix("Since") == true)
        h.record(.noNetwork, at: t0.addingTimeInterval(90))          // still the same outage
        h.record(.connected, at: t0.addingTimeInterval(60 + 180))
        XCTAssertTrue(h.summary()?.hasSuffix("· 3 min") == true)
    }

    func testBlipsUnderMinimumAreIgnored() {
        let h = ConnectionHistory()
        h.record(.noNetwork, at: t0)
        h.record(.connected, at: t0.addingTimeInterval(3))
        XCTAssertNil(h.summary())
    }

    func testDurationFormatting() {
        XCTAssertEqual(ConnectionHistory.duration(45), "45 s")
        XCTAssertEqual(ConnectionHistory.duration(180), "3 min")
        XCTAssertEqual(ConnectionHistory.duration(3900), "1 h 5 min")
    }
}

// MARK: - IPAddressProvider

final class IPv6PreferenceTests: XCTestCase {

    func testPrefersGlobalOverLinkLocal() {
        XCTAssertEqual(IPAddressProvider.preferredIPv6(from: ["fe80::1", "fd7b::2", "2001:db8::3"]), "fd7b::2")
    }

    func testFallsBackToLinkLocal() {
        XCTAssertEqual(IPAddressProvider.preferredIPv6(from: ["FE80::1"]), "FE80::1")
    }

    func testNoAddresses() {
        XCTAssertNil(IPAddressProvider.preferredIPv6(from: []))
    }
}
