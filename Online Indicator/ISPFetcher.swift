import Foundation

/// Fetches the ISP / ASN name for the device's current public IP via ip-api.com.
/// Results are cached in-memory for 60 seconds, matching the ExternalIPFetcher TTL.
final class ISPFetcher {

    // Returns plain-text org string, e.g. "AS7922 Comcast Cable Communications, LLC"
    private static let serviceURL = URL(string: "https://ipinfo.io/org")!
    private static let cacheTTL: TimeInterval = 60

    private var currentTask: URLSessionDataTask?
    private var lastFetchedISP: String?
    private var lastFetchTime: Date?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Fetches the ISP name, using the in-memory cache if still within the TTL.
    /// Always calls `completion` on the main queue.
    func fetch(completion: @escaping (String?) -> Void) {
        if let isp = lastFetchedISP,
           let time = lastFetchTime,
           Date().timeIntervalSince(time) < Self.cacheTTL {
            DispatchQueue.main.async { completion(isp) }
            return
        }

        currentTask?.cancel()
        currentTask = nil

        let task = session.dataTask(with: Self.serviceURL) { [weak self] data, _, error in
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            self?.currentTask = nil

            var isp: String?
            if let data, let str = String(data: data, encoding: .utf8) {
                // Strip leading "AS<number> " prefix if present, e.g. "AS7922 Comcast" → "Comcast"
                var org = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if org.hasPrefix("AS"), let spaceIndex = org.firstIndex(of: " ") {
                    org = String(org[org.index(after: spaceIndex)...])
                }
                if !org.isEmpty { isp = org }
            }
            if let isp {
                self?.lastFetchedISP = isp
                self?.lastFetchTime = Date()
            }
            DispatchQueue.main.async { completion(isp) }
        }
        currentTask = task
        task.resume()
    }

    /// Clears the cached ISP name (e.g., after a network interface change).
    func invalidateCache() {
        lastFetchedISP = nil
        lastFetchTime  = nil
    }
}
