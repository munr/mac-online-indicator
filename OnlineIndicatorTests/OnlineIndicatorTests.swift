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

    func testDefaultTargetIsValid() {
        XCTAssertTrue(ConnectivityChecker.isValidTarget(ConnectivityChecker.defaultURLString))
    }

    func testAcceptsHTTPS() {
        XCTAssertTrue(ConnectivityChecker.isValidTarget("https://example.com/health"))
    }

    func testRejectsOtherSchemes() {
        XCTAssertFalse(ConnectivityChecker.isValidTarget("ftp://example.com"))
    }

    func testRejectsMissingSchemeHostOrEmpty() {
        XCTAssertFalse(ConnectivityChecker.isValidTarget("example.com"))
        XCTAssertFalse(ConnectivityChecker.isValidTarget("http://"))
        XCTAssertFalse(ConnectivityChecker.isValidTarget(""))
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

final class CandidateInterfaceTests: XCTestCase {

    func testPrimaryInterfaceWinsOverOthers() {
        XCTAssertEqual(IPAddressProvider.candidateInterfaces(from: ["lo0", "en0", "en5"], primary: "en5"), ["en5"])
    }

    func testTunnelPrimaryFallsBackToAllRealInterfaces() {
        XCTAssertEqual(IPAddressProvider.candidateInterfaces(from: ["lo0", "en0", "utun3", "en5"], primary: "utun3"), ["en0", "en5"])
    }

    func testNoPrimaryKeepsAllRealInterfaces() {
        XCTAssertEqual(IPAddressProvider.candidateInterfaces(from: ["lo0", "awdl0", "bridge0", "en0"], primary: nil), ["awdl0", "en0"])
    }
}

final class ConnectivityPresenceTests: XCTestCase {

    func testNothingMeansNoConnectivity() {
        XCTAssertFalse(IPAddressProvider.hasConnectivity(.init()))
        XCTAssertFalse(IPAddressProvider.hasConnectivity(.init(ipv6: "fe80::1")))
    }

    func testIPv4WifiOrGlobalIPv6Count() {
        XCTAssertTrue(IPAddressProvider.hasConnectivity(.init(ipv4: "10.0.0.2")))
        XCTAssertTrue(IPAddressProvider.hasConnectivity(.init(wifiName: "Home")))
        XCTAssertTrue(IPAddressProvider.hasConnectivity(.init(ipv6: "2001:db8::3")))
    }
}

// MARK: - Network stub

/// Answers every request from `replies`, keyed by host. Hosts with no reply get a 599.
final class StubURLProtocol: URLProtocol {

    struct Reply { var status = 200; var body = "" }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var requestCount = 0

    static func reset() { replies = [:]; requestCount = 0 }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let reply = Self.replies[request.url?.host ?? ""] ?? Reply(status: 599)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - ConnectivityChecker (probing)

final class ConnectivityProbeTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset() }

    private func probe(_ targets: [String], file: StaticString = #filePath, line: UInt = #line) -> ProbeResult? {
        let checker = ConnectivityChecker(session: StubURLProtocol.session())
        let done = expectation(description: "probe")
        var result: ProbeResult?
        checker.checkOutboundConnection(targets: targets) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    func testDefaultProbeWithSuccessBodyIsReachable() {
        StubURLProtocol.replies["captive.apple.com"] = .init(body: "<HTML><BODY>Success</BODY></HTML>")
        let r = probe([ConnectivityChecker.defaultURLString])
        XCTAssertEqual(r?.reachable, true)
        XCTAssertEqual(r?.captivePortal, false)
    }

    func testDefaultProbeWithoutSuccessBodyIsACaptivePortal() {
        StubURLProtocol.replies["captive.apple.com"] = .init(body: "<html>Please log in</html>")
        let r = probe([ConnectivityChecker.defaultURLString])
        XCTAssertEqual(r?.reachable, false)
        XCTAssertEqual(r?.captivePortal, true)
        XCTAssertEqual(r?.failedHosts, ["captive.apple.com"])
    }

    func testReachableWhenAnyTargetAnswersAndFailuresAreNamed() {
        StubURLProtocol.replies["ok.example"] = .init(status: 204)
        StubURLProtocol.replies["down.example"] = .init(status: 500)
        let r = probe(["https://ok.example", "https://down.example"])
        XCTAssertEqual(r?.reachable, true)
        XCTAssertEqual(r?.failedHosts, ["down.example"])
        XCTAssertEqual(r?.summary, "1/2 OK · down.example")
    }

    func testBlockedWhenEveryTargetFails() {
        let r = probe(["https://a.example", "https://b.example"])
        XCTAssertEqual(r?.reachable, false)
        XCTAssertEqual(r?.failedHosts.count, 2)
    }

    func testCancelPendingSuppressesTheCompletion() {
        StubURLProtocol.replies["ok.example"] = .init()
        let checker = ConnectivityChecker(session: StubURLProtocol.session())
        let never = expectation(description: "completion must not run")
        never.isInverted = true
        checker.checkOutboundConnection(targets: ["https://ok.example"]) { _ in never.fulfill() }
        checker.cancelPending()
        wait(for: [never], timeout: 0.5)
    }
}
