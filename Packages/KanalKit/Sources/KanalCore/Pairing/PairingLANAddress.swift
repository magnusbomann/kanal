import Foundation
import Darwin

/// Returns a private, non-loopback IPv4 address suitable for a same-LAN QR fallback.
enum PairingLANAddress {
    static func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 169 && octets[1] == 254)
    }

    static func privateIPv4Address() -> String? {
        var address: String?
        var interface: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interface) == 0 else { return nil }
        defer { freeifaddrs(interface) }

        for cursor in sequence(first: interface, next: { $0?.pointee.ifa_next }) {
            guard let cursor, (cursor.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
                  let sa = cursor.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: cursor.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let value = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard isPrivateIPv4(value) else { continue }
            address = value
            break
        }
        return address
    }
}
