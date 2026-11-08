import Foundation

/// A generic single-URL fetcher with an in-memory cache.
/// Handles cancellation, TTL, and always delivers results on the main actor.
/// Both ExternalIPFetcher and ISPFetcher were identical except for the URL and
/// response transform — this class replaces both.
@MainActor
final class CachedFetcher {

    private static let cacheTTL: TimeInterval = 60

    private let url: URL
    private let transform: (Data) -> String?

    private var currentTask: URLSessionDataTask?
    private var cachedValue: String?
    private var cacheTime: Date?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    init(url: URL, transform: @escaping (Data) -> String?) {
        self.url       = url
        self.transform = transform
    }

    /// Fetches the value, using the in-memory cache if still within the TTL.
    /// Calls `completion` on the main actor.
    func fetch(completion: @escaping @MainActor (String?) -> Void) {
        if let value = cachedValue,
           let time = cacheTime,
           Date().timeIntervalSince(time) < Self.cacheTTL {
            completion(value)
            return
        }

        currentTask?.cancel()
        currentTask = nil

        let task = session.dataTask(with: url) { [weak self] data, response, error in
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            let result: String? = {
                // An error page (e.g. a 429 rate limit) must not be shown as the IP or ISP.
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return self?.transform(data)
            }()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTask = nil
                if let result {
                    self.cachedValue = result
                    self.cacheTime   = Date()
                }
                completion(result)
            }
        }
        currentTask = task
        task.resume()
    }

    /// Clears the cached value (e.g., after a network interface change).
    func invalidateCache() {
        cachedValue = nil
        cacheTime   = nil
    }
}

// MARK: - Shared instances

extension CachedFetcher {

    /// Fetches the device's external (public) IP address from api.ipify.org.
    static let externalIP = CachedFetcher(
        url: URL(string: "https://api.ipify.org")!
    ) { data in
        let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (str?.isEmpty == false) ? str : nil
    }

    /// Fetches the ISP / ASN name for the current public IP from ipinfo.io.
    /// Strips the leading "AS<number> " prefix (e.g. "AS7922 Comcast" → "Comcast").
    static let isp = CachedFetcher(
        url: URL(string: "https://ipinfo.io/org")!
    ) { data in
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        var org = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if org.hasPrefix("AS"), let spaceIndex = org.firstIndex(of: " ") {
            org = String(org[org.index(after: spaceIndex)...])
        }
        return org.isEmpty ? nil : org
    }
}
