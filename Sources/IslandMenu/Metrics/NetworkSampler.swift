import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

/// Throughput across physical interfaces plus a short list of what is connected.
final class NetworkSampler {
    private var previous: (counters: [String: (UInt32, UInt32)], time: TimeInterval)?
    private lazy var displayNames: [String: String] = {
        let all = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? []
        return Dictionary(all.compactMap { interface in
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? else { return nil }
            return (bsd, name)
        }, uniquingKeysWith: { first, _ in first })
    }()

    func sample() -> NetworkSnapshot {
        var counters: [String: (UInt32, UInt32)] = [:]
        var speeds: [String: UInt32] = [:]
        var addresses: [String: String] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return NetworkSnapshot() }
        defer { freeifaddrs(list) }
        for entry in sequence(first: list, next: { $0?.pointee.ifa_next }) {
            guard let entry, let address = entry.pointee.ifa_addr, entry.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            switch Int32(address.pointee.sa_family) {
            case AF_LINK where name.hasPrefix("en"):
                guard let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
                counters[name] = (data.ifi_ibytes, data.ifi_obytes)
                speeds[name] = data.ifi_baudrate
            case AF_INET:
                addresses[name] = Self.ipv4(address)
            default:
                continue
            }
        }
        var snapshot = NetworkSnapshot()
        let now = ProcessInfo.processInfo.systemUptime
        if let previous, now > previous.time {
            // Interface byte counters are 32-bit and wrap, so subtract with overflow.
            let delta = counters.reduce(into: (0.0, 0.0)) { sum, item in
                guard let before = previous.counters[item.key] else { return }
                sum.0 += Double(item.value.0 &- before.0)
                sum.1 += Double(item.value.1 &- before.1)
            }
            snapshot.down = delta.0 / (now - previous.time)
            snapshot.up = delta.1 / (now - previous.time)
        }
        previous = (counters, now)
        snapshot.interfaces = interfaces(addresses: addresses, speeds: speeds)
        return snapshot
    }

    private func interfaces(addresses: [String: String], speeds: [String: UInt32]) -> [NetworkInterface] {
        let wifiName = CWWiFiClient.shared().interface()?.interfaceName
        return addresses.keys.sorted().compactMap { name in
            guard let ip = addresses[name] else { return nil }
            if name == wifiName {
                let rate = CWWiFiClient.shared().interface()?.transmitRate() ?? 0
                return NetworkInterface(name: "Wi-Fi", detail: rate > 0 ? "\(Int(rate)) Mbps" : ip)
            }
            if name.hasPrefix("en") {
                let mbps = (speeds[name] ?? 0) / 1_000_000
                return NetworkInterface(name: displayNames[name] ?? name, detail: mbps > 0 ? "\(mbps) Mbps" : ip)
            }
            // Tailscale hands out addresses from the CGNAT range 100.64.0.0/10.
            if name.hasPrefix("utun"), Self.isCGNAT(ip) { return NetworkInterface(name: "Tailscale", detail: ip) }
            return nil
        }
    }

    private static func ipv4(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }

    private static func isCGNAT(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }
}

/// Looks up the public IP address at most once per `maxAge`, with a timeout and one retry.
actor PublicIPResolver {
    private static let endpoint = URL(string: "https://api.ipify.org")!
    private static let maxAge: TimeInterval = 600
    private var cached: (value: String, at: Date)?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func resolve() async -> String? {
        if let cached, Date().timeIntervalSince(cached.at) < Self.maxAge { return cached.value }
        for _ in 0..<2 {
            guard let (data, response) = try? await session.data(from: Self.endpoint),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, text.count <= 45 else { continue }
            cached = (text, Date())
            return text
        }
        return cached?.value
    }
}
