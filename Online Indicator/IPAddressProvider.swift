import Foundation
import Darwin
import CoreWLAN
import SystemConfiguration

struct IPAddressProvider {

    struct Addresses {
        var ipv4: String?
        var ipv6: String?
        var wifiName: String?
        var wifiRSSI: Int?
        var gateway: String?
        var dnsServers: [String] = []
        var isVPNActive: Bool = false
    }

    /// Reads the current IPv4, IPv6, Wi-Fi name, default gateway, and DNS servers.
    /// Addresses come from the primary-route interface when there is one (see `candidateInterfaces`),
    /// else from any non-virtual interface. Strips the scope-ID suffix from IPv6.
    static func current() -> Addresses {
        var result = Addresses()
        let wifiInterface = CWWiFiClient.shared().interface()
        result.wifiName  = wifiInterface?.ssid()
        result.wifiRSSI  = wifiInterface?.rssiValue()
        result.gateway   = defaultGateway()
        result.dnsServers = currentDNSServers()

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return result }
        defer { freeifaddrs(ifaddr) }

        // Collect all active, non-loopback interface names in encounter order.
        // Also detect VPN tunnels in this same pass.
        var seenNames: [String] = []
        var ptr = ifaddr
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            if !seenNames.contains(name) { seenNames.append(name) }

            // VPN detection: utun*/ipsec* interface with an IPv4 address that is UP + RUNNING.
            if (name.hasPrefix("utun") || name.hasPrefix("ipsec")),
               let addr = ifa.pointee.ifa_addr,
               addr.pointee.sa_family == AF_INET,
               (ifa.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
               (ifa.pointee.ifa_flags & UInt32(IFF_RUNNING)) != 0 {
                result.isVPNActive = true
            }
        }

        let active = candidateInterfaces(from: seenNames, primary: primaryInterface())

        var ipv6Candidates: [String] = []
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

            if family == UInt8(AF_INET6) {
                guard getnameinfo(addr,
                                  socklen_t(addr.pointee.sa_len),
                                  &hostname, socklen_t(hostname.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                var address = String(cString: hostname)
                if let percent = address.firstIndex(of: "%") {
                    address = String(address[..<percent])
                }
                ipv6Candidates.append(address)
            }
        }
        result.ipv6 = preferredIPv6(from: ipv6Candidates)

        return result
    }

    /// Whether there is a usable connection to show addresses for: a Wi-Fi name, an IPv4 address,
    /// or a global IPv6 one (link-local alone doesn't count, so IPv6-only networks still work).
    static func hasConnectivity(_ addresses: Addresses) -> Bool {
        addresses.wifiName != nil || addresses.ipv4 != nil
            || addresses.ipv6.map { !$0.lowercased().hasPrefix("fe80") } == true
    }

    /// Interfaces whose addresses are shown. Purely virtual/tunnel interfaces are excluded. When the
    /// system's primary route (`State:/Network/Global/IPv4`) is on one of the rest, only that one
    /// counts, so Wi-Fi + Ethernet show the interface actually carrying traffic; otherwise (e.g. a
    /// full-tunnel VPN is primary) all of them do.
    static func candidateInterfaces(from names: [String], primary: String?) -> Set<String> {
        let excluded = ["lo", "utun", "ipsec", "llw", "anpi", "bridge", "p2p"]
        let real = Set(names.filter { name in !excluded.contains { name.hasPrefix($0) } })
        if let primary, real.contains(primary) { return [primary] }
        return real
    }

    /// First global address; falls back to a link-local (`fe80::`) one only if that's all there is,
    /// since getifaddrs lists link-local first and it's rarely what someone wants to copy.
    static func preferredIPv6(from addresses: [String]) -> String? {
        addresses.first { !$0.lowercased().hasPrefix("fe80") } ?? addresses.first
    }

    // MARK: - Gateway

    private static func globalIPv4State() -> [String: Any]? {
        guard let store = SCDynamicStoreCreate(nil, "OnlineIndicator" as CFString, nil, nil) else { return nil }
        return SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
    }

    private static func defaultGateway() -> String? { globalIPv4State()?["Router"] as? String }

    private static func primaryInterface() -> String? { globalIPv4State()?["PrimaryInterface"] as? String }

    // MARK: - DNS

    private static func currentDNSServers() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "OnlineIndicator" as CFString, nil, nil) else { return [] }
        guard let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = dict["ServerAddresses"] as? [String] else { return [] }
        return servers
    }
}
