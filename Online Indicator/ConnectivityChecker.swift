import Foundation

class ConnectivityChecker {

    static let defaultURLString = "http://captive.apple.com"

    static var monitoringURLString: String {
        let saved = UserDefaults.standard.string(for: .pingURL) ?? ""
        return saved.isEmpty ? defaultURLString : saved
    }

    private var currentTask: URLSessionDataTask?

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpAdditionalHeaders = ["Connection": "close"]
        return URLSession(configuration: configuration)
    }()

    func checkOutboundConnection(completion: @escaping (Bool) -> Void) {

        guard let url = URL(string: Self.monitoringURLString) else {
            completion(false)
            return
        }

        currentTask?.cancel()
        currentTask = nil

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let task = session.dataTask(with: request) { [weak self] data, response, error in

            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }

            self?.currentTask = nil

            if error != nil {
                completion(false)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                completion(false)
                return
            }

            // For the default captive portal URL, verify the body contains "Success" to avoid
            // false positives where a captive portal intercepts the request and returns its
            // own page with an HTTP 200 status code.
            if Self.monitoringURLString == Self.defaultURLString {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(body.contains("Success"))
            } else {
                completion(true)
            }
        }

        currentTask = task
        task.resume()
    }
}
