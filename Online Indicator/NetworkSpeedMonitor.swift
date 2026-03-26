import Foundation

/// Measures download speed, upload speed, and ping latency on demand.
/// Speed tests are triggered explicitly (app start delay, WiFi change, user tap) —
/// there is no background polling timer.
final class NetworkSpeedMonitor {

    struct Snapshot {
        var downloadMbps: Double?
        var uploadMbps:   Double?
        var pingMs:       Double?
    }

    var snapshotHandler: ((Snapshot) -> Void)?
    var measuringChangedHandler: ((Bool) -> Void)?
    private(set) var snapshot = Snapshot()

    private let queue = DispatchQueue(label: "com.onlineindicator.speedmonitor", qos: .utility)
    private var downloadTask: URLSessionDataTask?
    private var uploadTask: URLSessionDataTask?
    private var isMeasuring = false {
        didSet {
            guard isMeasuring != oldValue else { return }
            let measuring = isMeasuring
            if Thread.isMainThread {
                measuringChangedHandler?(measuring)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.measuringChangedHandler?(measuring)
                }
            }
        }
    }

    // 25 MB download for accuracy on fast connections; 5 MB upload.
    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
    private static let uploadURL   = URL(string: "https://speed.cloudflare.com/__up")!
    private let uploadPayload = Data(count: 5_000_000)

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 60
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Control

    func runNow() {
        queue.async { [weak self] in
            guard let self, !self.isMeasuring else { return }
            self.isMeasuring = true
            self.measureSpeeds()
        }
    }

    func cancel() {
        downloadTask?.cancel()
        uploadTask?.cancel()
        queue.async { self.isMeasuring = false }
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
