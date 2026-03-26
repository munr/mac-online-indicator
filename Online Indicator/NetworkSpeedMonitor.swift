import Foundation

/// Measures download speed, upload speed, and ping latency in the background.
/// Speed tests run on a slow timer (default 5 minutes); ping updates are pushed
/// in from `AppState` on every connectivity check.
final class NetworkSpeedMonitor {

    struct Snapshot {
        var downloadMbps: Double?
        var uploadMbps:   Double?
        var pingMs:       Double?
    }

    var snapshotHandler: ((Snapshot) -> Void)?
    private(set) var snapshot = Snapshot()

    private let queue = DispatchQueue(label: "com.onlineindicator.speedmonitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var downloadTask: URLSessionDataTask?
    private var uploadTask: URLSessionDataTask?
    private var isMeasuring = false

    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=1000000")!
    private static let uploadURL   = URL(string: "https://speed.cloudflare.com/__up")!
    private let uploadPayload = Data(count: 100_000)

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Control

    func start(interval: TimeInterval) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.runNow() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        downloadTask?.cancel()
        uploadTask?.cancel()
        isMeasuring = false
    }

    func runNow() {
        queue.async { [weak self] in
            guard let self, !self.isMeasuring else { return }
            self.isMeasuring = true
            self.measureSpeeds()
        }
    }

    // MARK: - Ping (pushed from AppState on every connectivity check)

    func updatePing(_ ms: Double) {
        snapshot.pingMs = ms
        let snap = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.snapshotHandler?(snap)
        }
    }

    // MARK: - Speed measurement

    private func measureSpeeds() {
        let group = DispatchGroup()
        var dlMbps: Double?
        var ulMbps: Double?

        group.enter()
        measureDownload { result in
            dlMbps = result
            group.leave()
        }

        group.enter()
        measureUpload { result in
            ulMbps = result
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.snapshot.downloadMbps = dlMbps
            self.snapshot.uploadMbps   = ulMbps
            self.isMeasuring = false
            self.snapshotHandler?(self.snapshot)
        }
    }

    private func measureDownload(completion: @escaping (Double?) -> Void) {
        let start = Date()
        downloadTask?.cancel()
        let task = session.dataTask(with: Self.downloadURL) { data, _, error in
            if let urlError = error as? URLError, urlError.code == .cancelled {
                completion(nil)
                return
            }
            guard error == nil, let data else {
                completion(nil)
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed > 0 else { completion(nil); return }
            completion(Double(data.count) * 8 / elapsed / 1_000_000)
        }
        downloadTask = task
        task.resume()
    }

    private func measureUpload(completion: @escaping (Double?) -> Void) {
        var request = URLRequest(url: Self.uploadURL)
        request.httpMethod = "POST"
        request.httpBody   = uploadPayload
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let start = Date()
        uploadTask?.cancel()
        let task = session.dataTask(with: request) { _, _, error in
            if let urlError = error as? URLError, urlError.code == .cancelled {
                completion(nil)
                return
            }
            guard error == nil else {
                completion(nil)
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed > 0 else { completion(nil); return }
            completion(Double(self.uploadPayload.count) * 8 / elapsed / 1_000_000)
        }
        uploadTask = task
        task.resume()
    }
}
