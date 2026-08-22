import Compression
import Foundation

/// Gzip decoding for EPG payloads.
///
/// Guides are served as `.xml.gz` far more often than as plain XML, and Foundation
/// has no gunzip. Apple's `compression` library speaks raw DEFLATE, so the gzip
/// wrapper is peeled off by hand before handing the stream over.
public enum Gunzip {

    public static func isGzipped(_ data: Data) -> Bool {
        data.count > 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    /// Returns the input unchanged when it is not gzipped, so callers can pass
    /// any downloaded body through without sniffing first.
    public static func decode(_ data: Data) -> Data {
        guard isGzipped(data), let body = stripHeader(data) else { return data }
        return inflate(body) ?? data
    }

    /// RFC 1952: 10 fixed bytes, then optional extra/name/comment/CRC fields.
    private static func stripHeader(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18 else { return nil }
        let flags = bytes[3]
        var index = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard index + 1 < bytes.count else { return nil }
            let length = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + length
        }
        if flags & 0x08 != 0 { // FNAME
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 } // FHCRC

        // Trailing 8 bytes are CRC32 + ISIZE.
        guard index < bytes.count - 8 else { return nil }
        return data.subdata(in: (data.startIndex + index)..<(data.endIndex - 8))
    }

    private static func inflate(_ deflated: Data) -> Data? {
        // Guides expand roughly 10×; start there and grow if the buffer fills.
        var capacity = max(deflated.count * 12, 1 << 20)
        for _ in 0..<4 {
            let result = deflated.withUnsafeBytes { source -> Data? in
                guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                defer { destination.deallocate() }
                let written = compression_decode_buffer(
                    destination, capacity,
                    base, deflated.count,
                    nil, COMPRESSION_ZLIB
                )
                guard written > 0 else { return nil }
                // A full buffer means the output was probably truncated.
                guard written < capacity else { return nil }
                return Data(bytes: destination, count: written)
            }
            if let result { return result }
            capacity *= 4
        }
        return nil
    }
}
