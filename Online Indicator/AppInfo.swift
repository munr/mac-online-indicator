import Foundation

struct AppInfo {

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var commitHash: String {
        Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String ?? ""
    }

    static var fullVersionString: String {
        let hash = commitHash.isEmpty ? "" : " · \(commitHash)"
        return "v \(marketingVersion) (\(buildVersion)\(hash))"
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Online Indicator"
    }
}
