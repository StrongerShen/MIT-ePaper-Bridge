import Foundation
import UIKit

enum BridgeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum Frame {
    static let width = 800
    static let height = 480
    static let byteCount = 48000

    static func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0)
            }
        }
        return crc ^ 0xffffffff
    }

    static func preview(_ bytes: Data) -> UIImage? {
        guard bytes.count == byteCount else { return nil }
        let pixels = bytes.flatMap { byte in
            (0..<8).map { bit -> UInt8 in (byte & (0x80 >> bit)) == 0 ? 0 : 255 }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: image)
    }

    static func generateTestPattern() -> Data {
        var data = Data(repeating: 0xff, count: byteCount)
        let bytesPerRow = width / 8
        for y in 0..<height {
            for bx in 0..<bytesPerRow {
                let x = bx * 8
                if y < 4 || y >= height - 4 || x < 8 || x >= width - 8 {
                    data[y * bytesPerRow + bx] = 0x00
                } else if ((x / 32) + (y / 32)) % 2 == 0 {
                    data[y * bytesPerRow + bx] = 0xaa
                }
            }
        }
        return data
    }
}

extension Data {
    func littleEndian(_ offset: Int, _ length: Int) -> UInt32 {
        (0..<length).reduce(UInt32(0)) { value, index in
            value | (UInt32(self[offset + index]) << (8 * index))
        }
    }

    mutating func appendLE(_ value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
}
