import Foundation

/// Fetches the device's external (public) IP address from a lightweight HTTP service.
/// Results are cached in-memory for 60 seconds to avoid redundant requests on repeated
/// menu opens.
final class ExternalIPFetcher {

    private static let serviceURL = URL(string: "https://api.ipify.org")!
    private static let cacheTTL: TimeInterval = 60

    private var currentTask: URLSessionDataTask?
    private var lastFetchedIP: String?
    private var lastFetchTime: Date?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Fetches the external IP, using the in-memory cache if it is still within the TTL.
    /// Always calls `completion` on the main queue.
    func fetch(completion: @escaping (String?) -> Void) {
        if let ip = lastFetchedIP,
           let time = lastFetchTime,
           Date().timeIntervalSince(time) < Self.cacheTTL {
            DispatchQueue.main.async { completion(ip) }
            return
        }

        currentTask?.cancel()
        currentTask = nil

        let task = session.dataTask(with: Self.serviceURL) { [weak self] data, _, error in
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            self?.currentTask = nil

            var ip: String?
            if let data, let str = String(data: data, encoding: .utf8) {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { ip = trimmed }
            }
            if let ip {
                self?.lastFetchedIP = ip
                self?.lastFetchTime = Date()
            }
            DispatchQueue.main.async { completion(ip) }
        }
        currentTask = task
        task.resume()
    }

    /// Clears the cached IP (e.g., after a network interface change).
    func invalidateCache() {
        lastFetchedIP = nil
        lastFetchTime = nil
    }
}
