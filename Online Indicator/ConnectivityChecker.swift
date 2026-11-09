import Foundation

/// Outcome of one probe cycle across all configured targets.
struct ProbeResult {
    let reachable: Bool          // at least one target responded correctly
    let latencyMs: Double?       // latency of the first target that succeeded
    let total: Int
    let failedHosts: [String]
    let captivePortal: Bool      // the default Apple probe returned a non-"Success" page

    /// Compact menu text, e.g. "3/3 OK" or "2/3 OK · example.com +1".
    var summary: String {
        let ok = total - failedHosts.count
        guard let first = failedHosts.first else { return "\(ok)/\(total) OK" }
        let more = failedHosts.count > 1 ? " +\(failedHosts.count - 1)" : ""
        return "\(ok)/\(total) OK · \(first)\(more)"
    }
}

final class ConnectivityChecker {

    static let defaultURLString = "http://captive.apple.com"
    static let maxTargets = 5

    /// Splits a saved "Ping URL" value into targets (comma or whitespace separated).
    /// ponytail: URLs containing commas can't be used; add real quoting if that ever matters.
    static func parseTargets(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }

    /// True for an http(s) URL with a host; the only kind a probe can use.
    static func isValidTarget(_ target: String) -> Bool {
        guard let url = URL(string: target), let scheme = url.scheme else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    /// Targets to probe now: the saved list, or the Apple default when none is set.
    static var targets: [String] {
        let saved = parseTargets(UserDefaults.standard.string(for: .pingURL) ?? "")
        return saved.isEmpty ? [defaultURLString] : Array(saved.prefix(maxTargets))
    }

    /// Times a DNS lookup of a random, never-cached name so the result reflects the resolver's
    /// round trip rather than the local cache. NXDOMAIN counts as success (resolver answered);
    /// `nil` means the resolver didn't answer. Blocks for as long as the resolver takes, so it
    /// runs off the main thread.
    static func measureDNSLookup(completion: @escaping (Double?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let host = "\(UUID().uuidString.prefix(8).lowercased()).captive.apple.com"
            var result: UnsafeMutablePointer<addrinfo>?
            let start = DispatchTime.now().uptimeNanoseconds
            let code = getaddrinfo(host, nil, nil, &result)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            if result != nil { freeaddrinfo(result) }
            completion(code == 0 || code == EAI_NONAME ? ms : nil)
        }
    }

    private struct Outcome {
        let host: String
        let ok: Bool
        let ms: Double?
        let portal: Bool
    }

    private var currentTasks: [URLSessionDataTask] = []
    private var generation = 0   // main thread only; lets a newer check discard an older one

    private let session: URLSession

    /// `session` is injectable so tests can stub the network.
    init(session: URLSession = ConnectivityChecker.makeSession()) {
        self.session = session
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpAdditionalHeaders = ["Connection": "close"]
        return URLSession(configuration: configuration)
    }

    /// Drops any probe still in flight so its late result can't overwrite a newer status.
    /// Main thread only.
    func cancelPending() {
        currentTasks.forEach { $0.cancel() }
        currentTasks = []
        generation += 1
    }

    /// Probes every target in parallel. Must be called on the main thread; `completion`
    /// is delivered on the main thread, and not at all if a newer check superseded this one.
    func checkOutboundConnection(targets: [String] = ConnectivityChecker.targets,
                                 completion: @escaping (ProbeResult) -> Void) {

        cancelPending()
        let gen = generation

        let group = DispatchGroup()
        let lock = NSLock()
        var outcomes = [Outcome?](repeating: nil, count: targets.count)

        for (index, target) in targets.enumerated() {
            let host = URL(string: target)?.host ?? target
            guard let url = URL(string: target) else {
                outcomes[index] = Outcome(host: host, ok: false, ms: nil, portal: false)
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            let probeStart = Date()

            group.enter()
            let task = session.dataTask(with: request) { data, response, error in
                defer { group.leave() }

                let elapsed = Date().timeIntervalSince(probeStart) * 1000
                if (error as? URLError)?.code == .cancelled { return }

                var outcome = Outcome(host: host, ok: false, ms: nil, portal: false)
                if error == nil,
                   let http = response as? HTTPURLResponse,
                   (200...399).contains(http.statusCode) {
                    if target == Self.defaultURLString {
                        // A captive portal can answer the probe with its own page and a 200, so
                        // the default probe must also contain "Success".
                        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        let success = body.contains("Success")
                        outcome = Outcome(host: host, ok: success, ms: success ? elapsed : nil, portal: !success)
                    } else {
                        outcome = Outcome(host: host, ok: true, ms: elapsed, portal: false)
                    }
                }
                lock.lock(); outcomes[index] = outcome; lock.unlock()
            }
            currentTasks.append(task)
            task.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.currentTasks = []
            lock.lock(); let results = outcomes.compactMap { $0 }; lock.unlock()
            let ok = results.filter(\.ok)
            completion(ProbeResult(
                reachable: !ok.isEmpty,
                latencyMs: ok.first?.ms,
                total: targets.count,
                failedHosts: results.filter { !$0.ok }.map(\.host),
                captivePortal: results.contains { $0.portal }
            ))
        }
    }
}
