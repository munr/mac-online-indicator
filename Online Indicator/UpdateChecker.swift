import Foundation
import AppKit

class UpdateChecker {

    static let repoOwner = "bornexplorer"
    static let repoName  = "OnlineIndicator"

    private static var apiURL: URL? {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")
    }

    enum UpdateResult {
        case upToDate
        case updateAvailable(releaseTag: String, notes: String?, downloadURL: URL?, pageURL: URL)
        case error(String)
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents  = local.split(separator: ".").compactMap { Int($0) }
        let maxLength = max(remoteComponents.count, localComponents.count)

        for i in 0..<maxLength {
            let remoteValue = i < remoteComponents.count ? remoteComponents[i] : 0
            let localValue  = i < localComponents.count  ? localComponents[i]  : 0

            if remoteValue > localValue { return true  }
            if remoteValue < localValue { return false }
        }

        return false
    }

    // MARK: - Cached result (persisted across launches)

    /// The cached update result stored from the last successful check.
    static var cachedResult: UpdateResult? {
        guard let tag = UserDefaults.standard.string(for: .lastUpdateTag),
              let pageString = UserDefaults.standard.string(for: .lastUpdatePage),
              let pageURL = URL(string: pageString) else { return nil }
        let notes = UserDefaults.standard.string(for: .lastUpdateNotes)
        let downloadURL = UserDefaults.standard.string(for: .lastUpdateDownload).flatMap(URL.init)
        return .updateAvailable(releaseTag: tag, notes: notes, downloadURL: downloadURL, pageURL: pageURL)
    }

    private static func persistResult(_ result: UpdateResult) {
        switch result {
        case .updateAvailable(let tag, let notes, let downloadURL, let pageURL):
            UserDefaults.standard.set(tag,                          for: .lastUpdateTag)
            UserDefaults.standard.set(notes,                        for: .lastUpdateNotes)
            UserDefaults.standard.set(downloadURL?.absoluteString,  for: .lastUpdateDownload)
            UserDefaults.standard.set(pageURL.absoluteString,       for: .lastUpdatePage)
        case .upToDate:
            UserDefaults.standard.removeObject(for: .lastUpdateTag)
            UserDefaults.standard.removeObject(for: .lastUpdateNotes)
            UserDefaults.standard.removeObject(for: .lastUpdateDownload)
            UserDefaults.standard.removeObject(for: .lastUpdatePage)
        case .error:
            break
        }
    }

    // MARK: - Automatic check

    /// Checks for updates at most once every 24 hours. Calls `completion` only when a result
    /// is actually fetched; skips silently if the cooldown has not elapsed.
    static func checkIfNeeded(completion: @escaping (UpdateResult) -> Void) {
        let lastCheck = UserDefaults.standard.object(for: .lastUpdateCheck) as? Date
        let oneDayAgo = Date().addingTimeInterval(-86_400)
        guard lastCheck == nil || lastCheck! < oneDayAgo else { return }

        check { result in
            UserDefaults.standard.set(Date(), for: .lastUpdateCheck)
            persistResult(result)
            completion(result)
        }
    }

    // MARK: - Manual check

    static func check(completion: @escaping (UpdateResult) -> Void) {
        guard let url = apiURL else {
            completion(.error("Invalid repository URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.error(error.localizedDescription))
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    completion(.error("Invalid response from GitHub"))
                    return
                }

                // GitHub returns an error object when repo/release not found
                if let message = json["message"] as? String {
                    completion(.error(message))
                    return
                }

                guard let tag = json["tag_name"] as? String,
                      let pageURLString = json["html_url"] as? String,
                      let pageURL = URL(string: pageURLString)
                else {
                    completion(.error("Unexpected response format"))
                    return
                }

                // Strip a leading "v" from the tag (e.g. "v1.2.0" → "1.2.0") before comparing
                let remoteVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let localVersion  = AppInfo.marketingVersion

                guard isNewer(remoteVersion, than: localVersion) else {
                    persistResult(.upToDate)
                    completion(.upToDate)
                    return
                }

                let notes = json["body"] as? String

                // Prefer the first .dmg asset; fall back to the release page
                var downloadURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    let dmg = assets.first {
                        ($0["name"] as? String)?.hasSuffix(".dmg") == true
                    }
                    if let dmgURLString = dmg?["browser_download_url"] as? String {
                        downloadURL = URL(string: dmgURLString)
                    }
                }

                let result = UpdateResult.updateAvailable(
                    releaseTag:  tag,
                    notes:       notes,
                    downloadURL: downloadURL,
                    pageURL:     pageURL
                )
                persistResult(result)
                completion(result)
            }
        }.resume()
    }
}
