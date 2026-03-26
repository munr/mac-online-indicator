import Foundation

extension UserDefaults {

    enum Key: String {
        case refreshInterval    = "refreshInterval"
        case pingURL            = "pingURL"
        case showKnownNetworks  = "showKnownNetworks"
        case userIconSets       = "userIconSets_v1"
        // Update checker
        case lastUpdateCheck    = "lastUpdateCheck"
        case lastUpdateTag      = "lastUpdateTag"
        case lastUpdateNotes    = "lastUpdateNotes"
        case lastUpdateDownload = "lastUpdateDownload"
        case lastUpdatePage     = "lastUpdatePage"
        // Speed monitor
        case speedTestInterval  = "speedTestInterval"
    }

    func string(for key: Key) -> String? { string(forKey: key.rawValue) }
    func double(for key: Key) -> Double  { double(forKey: key.rawValue) }
    func bool(for key: Key) -> Bool      { bool(forKey: key.rawValue) }
    func bool(for key: Key, default defaultValue: Bool) -> Bool {
        object(for: key) == nil ? defaultValue : bool(for: key)
    }
    func data(for key: Key) -> Data?     { data(forKey: key.rawValue) }
    func object(for key: Key) -> Any?    { object(forKey: key.rawValue) }

    func set(_ value: Any?, for key: Key)  { set(value, forKey: key.rawValue) }
    func removeObject(for key: Key)        { removeObject(forKey: key.rawValue) }
}
