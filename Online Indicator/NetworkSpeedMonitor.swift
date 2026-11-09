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

    private var downloadTask: URLSessionDownloadTask?
    private var uploadTask: URLSessionDataTask?
    private var isMeasuring = false {
        didSet {
            guard isMeasuring != oldValue else { return }
            measuringChangedHandler?(isMeasuring)
        }
    }

    // 25 MB download for accuracy on fast connections; 5 MB upload.
    private static let downloadBytes = 25_000_000
    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadBytes)")!
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

    /// Main thread only, like everything else on this class; the work itself is async URLSession tasks.
    func runNow() {
        guard !isMeasuring else { return }
        isMeasuring = true
        measureSpeeds()
    }

    /// Cancelled tasks complete with `nil`, so the normal completion path clears `isMeasuring`.
    func cancel() {
        downloadTask?.cancel()
        uploadTask?.cancel()
    }

    // MARK: - Ping (pushed from AppState on every connectivity check)

    func updatePing(_ ms: Double) {
        snapshot.pingMs = ms
        snapshotHandler?(snapshot)
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
        // A download task streams to disk instead of buffering all 25 MB in memory.
        let task = session.downloadTask(with: Self.downloadURL) { fileURL, response, error in
            if let urlError = error as? URLError, urlError.code == .cancelled {
                completion(nil)
                return
            }
            guard error == nil, fileURL != nil, (response as? HTTPURLResponse)?.statusCode == 200 else {
                completion(nil)
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed > 0 else { completion(nil); return }
            completion(Double(Self.downloadBytes) * 8 / elapsed / 1_000_000)
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
        let task = session.dataTask(with: request) { _, response, error in
            if let urlError = error as? URLError, urlError.code == .cancelled {
                completion(nil)
                return
            }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200 else {
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
