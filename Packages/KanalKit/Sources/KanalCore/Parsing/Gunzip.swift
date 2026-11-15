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
        // Indexed in place. Copying the archive into an array first doubled
        // the memory of a guide that is already tens of megabytes.
        let count = data.count
        guard count > 18 else { return nil }
        func byte(_ offset: Int) -> UInt8 { data[data.startIndex + offset] }
        let flags = byte(3)
        var index = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard index + 1 < count else { return nil }
            let length = Int(byte(index)) | (Int(byte(index + 1)) << 8)
            index += 2 + length
        }
        if flags & 0x08 != 0 { // FNAME
            while index < count, byte(index) != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while index < count, byte(index) != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 } // FHCRC

        // Trailing 8 bytes are CRC32 + ISIZE.
        guard index < count - 8 else { return nil }
        return data.subdata(in: (data.startIndex + index)..<(data.endIndex - 8))
    }

    /// Inflates in fixed chunks.
    ///
    /// The one-shot call needs its whole output buffer up front, and guessing
    /// meant reserving twelve times the archive, then forty-eight, then a
    /// hundred and ninety-two — over a gigabyte for a large guide, on an Apple
    /// TV that is killed long before that. A stream only ever holds what it
    /// has actually produced.
    private static func inflate(_ deflated: Data) -> Data? {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(stream) }

        let chunkSize = 1 << 18
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }

        var output = Data()
        let finished = deflated.withUnsafeBytes { source -> Bool in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return false }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count
            while true {
                stream.pointee.dst_ptr = chunk
                stream.pointee.dst_size = chunkSize
                let status = compression_stream_process(
                    stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                )
                let produced = chunkSize - stream.pointee.dst_size
                if produced > 0 { output.append(chunk, count: produced) }
                switch status {
                case COMPRESSION_STATUS_END:
                    return true
                case COMPRESSION_STATUS_OK:
                    // No output and no input left is a truncated archive.
                    if produced == 0, stream.pointee.src_size == 0 { return false }
                default:
                    return false
                }
            }
        }
        return finished && !output.isEmpty ? output : nil
    }
}
