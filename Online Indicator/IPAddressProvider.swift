import Foundation
import Darwin
import CoreWLAN
import SystemConfiguration

struct IPAddressProvider {

    struct Addresses {
        var ipv4: String?
        var ipv6: String?
        var wifiName: String?
        var gateway: String?
        var dnsServers: [String] = []
    }

    /// Reads the current IPv4, IPv6, Wi-Fi name, default gateway, and DNS servers.
    /// Prefers `en*` interfaces (Wi-Fi / Ethernet), then falls back to any other active non-loopback
    /// interface (e.g. Thunderbolt Ethernet, USB adapters). Strips the scope-ID suffix from IPv6.
    static func current() -> Addresses {
        var result = Addresses()
        result.wifiName  = CWWiFiClient.shared().interface()?.ssid()
        result.gateway   = defaultGateway()
        result.dnsServers = currentDNSServers()

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return result }
        defer { freeifaddrs(ifaddr) }

        // Collect all active, non-loopback interface names in encounter order.
        var seenNames: [String] = []
        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("lo"), !seenNames.contains(name) else { continue }
            seenNames.append(name)
        }

        // Sort: en* first (lower index = higher priority), then everything else alphabetically.
        // Exclude purely virtual/tunnel interfaces that won't carry user traffic.
        let excluded: Set<String> = ["utun", "ipsec", "llw", "anpi", "bridge", "p2p"]
        let active = seenNames
            .filter { name in !excluded.contains(where: { name.hasPrefix($0) }) }
            .sorted { a, b in
                let aIsEn = a.hasPrefix("en")
                let bIsEn = b.hasPrefix("en")
                if aIsEn != bIsEn { return aIsEn }
                return a < b
            }

        ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            guard active.contains(name),
                  let addr = current.pointee.ifa_addr else { continue }

            let family = addr.pointee.sa_family
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

            if family == UInt8(AF_INET), result.ipv4 == nil {
                guard getnameinfo(addr,
                                  socklen_t(addr.pointee.sa_len),
                                  &hostname, socklen_t(hostname.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                result.ipv4 = String(cString: hostname)
            }

            if family == UInt8(AF_INET6), result.ipv6 == nil {
                guard getnameinfo(addr,
                                  socklen_t(addr.pointee.sa_len),
                                  &hostname, socklen_t(hostname.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                var address = String(cString: hostname)
                if let percent = address.firstIndex(of: "%") {
                    address = String(address[..<percent])
                }
                result.ipv6 = address
            }
        }

        return result
    }

    // MARK: - VPN Detection

    /// Returns `true` if any VPN tunnel interface (`utun*` or `ipsec*`) is up and has an assigned address.
    static func isVPNActive() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let ifa = ptr?.pointee {
            defer { ptr = ifa.ifa_next }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("utun") || name.hasPrefix("ipsec"),
                  let addr = ifa.ifa_addr,
                  addr.pointee.sa_family == AF_INET,
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
                  (ifa.ifa_flags & UInt32(IFF_RUNNING)) != 0
            else { continue }
            return true
        }
        return false
    }

    // MARK: - Gateway

    private static func defaultGateway() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "OnlineIndicator" as CFString, nil, nil) else { return nil }
        guard let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return dict["Router"] as? String
    }

    // MARK: - DNS

    private static func currentDNSServers() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "OnlineIndicator" as CFString, nil, nil) else { return [] }
        guard let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = dict["ServerAddresses"] as? [String] else { return [] }
        return servers
    }
}
