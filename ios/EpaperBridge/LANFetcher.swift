import Foundation

struct LANImageDescriptor: Decodable {
    let url: String
    let width: Int
    let height: Int
    let length: Int
    let crc32: UInt32

    func checkedURL() throws -> URL {
        guard width == 800, height == 480, length == Frame.byteCount,
              let result = URL(string: url), result.scheme == "http",
              let host = result.host, let port = result.port, (1...65535).contains(port),
              result.user == nil, result.password == nil, result.query == nil, result.fragment == nil else {
            throw BridgeError.invalid("電腦傳來的圖片連線資訊不正確")
        }
        // Only numeric private/link-local IPv4 addresses; no DNS or redirects.
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4,
              octets.map({ String($0) }).joined(separator: ".") == host else {
            throw BridgeError.invalid("只接受區域網路 IPv4 位址")
        }
        let local = octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
        guard local else { throw BridgeError.invalid("圖片網址不在區域網路範圍內") }
        return result
    }
}

final class LANFetcher: NSObject, URLSessionTaskDelegate {
    func fetch(_ descriptor: LANImageDescriptor) async throws -> Data {
        let url = try descriptor.checkedURL()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength == Int64(Frame.byteCount) else {
            throw BridgeError.invalid("電腦回傳的圖片長度或 HTTP 狀態不正確")
        }
        var frame = Data()
        frame.reserveCapacity(Frame.byteCount)
        for try await byte in stream {
            guard frame.count < Frame.byteCount else {
                throw BridgeError.invalid("收到超出預期長度的圖片")
            }
            frame.append(byte)
        }
        try Task.checkCancellation()
        guard frame.count == Frame.byteCount, Frame.crc32(frame) == descriptor.crc32 else {
            throw BridgeError.invalid("Wi-Fi 圖片不完整或 CRC 檢查失敗")
        }
        return frame
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
