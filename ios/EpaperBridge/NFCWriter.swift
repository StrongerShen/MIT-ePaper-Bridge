import AudioToolbox
import CoreNFC
import Combine
import Foundation
import UIKit

struct NFCDiagnostics: Identifiable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var modelName: String = "7.5inch e-Paper (800x480)"
    var alignmentDuration: Double = 0.0
    var transmissionDuration: Double = 0.0
    var refreshDuration: Double = 0.0
    var totalPackets: Int = 400
    var packetIntervalMs: Double = 5.0
    var finalResult: String = "成功"
}

// Legacy 0xCD protocol implementation for 7.5inch e-Paper (800 × 480).
final class NFCWriter: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published var message = "接收圖片後，按更新並將手機頂端靠近電子紙天線"
    @Published var busy = false
    @Published var progress = 0.0
    @Published var currentScore = 0
    @Published var diagnostics: NFCDiagnostics?

    private var session: NFCTagReaderSession?
    private var task: Task<Void, Never>?
    private var image = Data()
    private var deadline = Date.distantPast
    private var alignmentOnly = false

    // Normal update: transmits image and refreshes display
    func start(frame: Data) {
        guard !busy, frame.count == Frame.byteCount else { return }
        guard NFCTagReaderSession.readingAvailable else {
            message = "此裝置無法使用 NFC，請使用支援 NFC 的實體 iPhone"
            return
        }
        alignmentOnly = false
        image = frame
        busy = true
        progress = 0
        currentScore = 0
        message = "請將 iPhone 頂端平貼電子紙天線，微調尋找最佳位置"
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main)
        session?.alertMessage = message
        session?.begin()
    }

    // Pure alignment test: only tests RF coupling, displays percentage and vibrates (no image transmission)
    func startAlignmentTest() {
        guard !busy else { return }
        guard NFCTagReaderSession.readingAvailable else {
            message = "此裝置無法使用 NFC，請使用支援 NFC 的實體 iPhone"
            return
        }
        alignmentOnly = true
        busy = true
        progress = 0
        currentScore = 0
        message = "請將 iPhone 頂端平貼天線微調，測試即時感應強度"
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main)
        session?.alertMessage = message
        session?.begin()
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard self.session === session else { return }
        task?.cancel()
        task = nil
        self.session = nil
        busy = false
        currentScore = 0
        message = "NFC 已結束：\(error.localizedDescription)。可重新點擊按鈕重試。"
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard task == nil else { return }
        guard tags.count == 1 else {
            session.alertMessage = "請只靠近一台電子紙"
            session.restartPolling()
            return
        }
        guard case .miFare(let mifare) = tags[0] else {
            fail(session, "目前只實作 MIFARE／0xCD 更新協定；此標籤類型尚未支援")
            return
        }

        if alignmentOnly {
            task = Task { @MainActor in
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        session.connect(to: tags[0]) { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                    self.deadline = Date().addingTimeInterval(35)
                    try await self.runAlignmentTest(tag: mifare, session: session)
                    self.session = nil
                    self.busy = false
                    self.task = nil
                    self.progress = 1
                    session.alertMessage = self.message
                    session.invalidate()
                } catch {
                    guard self.session === session else { return }
                    self.fail(session, error.localizedDescription)
                }
            }
        } else {
            let frame = image
            task = Task { @MainActor in
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        session.connect(to: tags[0]) { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                    self.deadline = Date().addingTimeInterval(50)
                    try await self.write(frame, to: mifare, session: session)
                    self.session = nil
                    self.busy = false
                    self.task = nil
                    self.progress = 1
                    if self.message.isEmpty || !self.message.contains("刷新中") {
                        self.message = "電子紙已回報刷新完成，請確認實際畫面"
                    }
                    session.alertMessage = self.message
                    session.invalidate()
                } catch {
                    guard self.session === session else { return }
                    self.fail(session, error.localizedDescription)
                }
            }
        }
    }

    private func fail(_ session: NFCTagReaderSession, _ detail: String) {
        self.session = nil
        task = nil
        busy = false
        currentScore = 0
        message = "連線中斷：\(detail)。請微調手機頂端貼齊天線後重試。"
        session.invalidate(errorMessage: message)
    }

    @MainActor
    private func exchange(_ bytes: Data, tag: NFCMiFareTag) async throws -> Data {
        try Task.checkCancellation()
        guard Date() < deadline else { throw BridgeError.invalid("NFC 逾時") }
        return try await withCheckedThrowingContinuation { continuation in
            tag.sendMiFareCommand(commandPacket: bytes) { response, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: response) }
            }
        }
    }

    @MainActor
    private func acknowledged(_ command: [UInt8], tag: NFCMiFareTag) async throws {
        let response = try await exchange(Data(command), tag: tag)
        guard response == Data([0, 0]) else {
            let hex = response.map { String(format: "%02X", $0) }.joined(separator: " ")
            throw BridgeError.invalid("指令 \(command.map { String(format: "%02X", $0) }.joined(separator: " ")) 回應異常：\(hex)")
        }
    }

    // Pure alignment and RF strength test (no image payload sent)
    @MainActor
    private func runAlignmentTest(tag: NFCMiFareTag, session: NFCTagReaderSession) async throws {
        message = "已偵測天線，請微調滑動尋找強度最大處..."
        session.alertMessage = message

        var score = 0 // 0% to 100%
        var perfectCycles = 0
        let testDeadline = Date().addingTimeInterval(30)
        var lastVibratedScore = 0

        while Date() < testDeadline {
            try Task.checkCancellation()

            var probeOk = false
            do {
                let resp = try await exchange(Data([0xcd, 0x0d]), tag: tag)
                probeOk = (resp == Data([0, 0]))
            } catch {
                probeOk = false
            }

            if probeOk {
                score = min(100, score + 10)
                if score >= 60 && (score - lastVibratedScore >= 20 || score == 100) {
                    if score == 100 {
                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    } else {
                        AudioServicesPlaySystemSound(1519)
                    }
                    lastVibratedScore = score
                }
                if score == 100 {
                    perfectCycles += 1
                } else {
                    perfectCycles = 0
                }
            } else {
                score = max(0, score - 30)
                lastVibratedScore = min(lastVibratedScore, score)
                perfectCycles = 0
            }

            self.currentScore = score
            let statusHint: String
            if score >= 90 {
                statusHint = "🎯 最佳位置 (滿格)！保持此手勢"
            } else if score >= 60 {
                statusHint = "📶 訊號良好，微調頂端邊緣"
            } else if score >= 30 {
                statusHint = "🔍 訊號微弱，嘗試左右平移"
            } else {
                statusHint = "❌ 偏離線圈，請對準電子紙背部"
            }

            self.progress = Double(score) / 100.0
            self.message = "即時感應強度：\(score)%\n\(statusHint)"
            session.alertMessage = self.message

            if perfectCycles >= 25 {
                AudioServicesPlaySystemSound(1520)
                self.message = "✅ 最佳位置已鎖定 (100%)！測試完成，可開始傳圖更新。"
                session.alertMessage = self.message
                try await Task.sleep(nanoseconds: 800_000_000)
                return
            }

            try await Task.sleep(nanoseconds: 60_000_000)
        }
        self.message = "測試已結束，您可重新點擊測試"
    }

    // Normal update process with alignment lock + 400 packets image transmission + refresh
    @MainActor
    private func write(_ frame: Data, to tag: NFCMiFareTag, session: NFCTagReaderSession) async throws {
        var diag = NFCDiagnostics()
        let alignStart = Date()

        // Phase 1: Smart Alignment & Energy Accumulation
        message = "請將 iPhone 頂端平貼天線，微調尋找最佳位置..."
        session.alertMessage = message

        let targetStableCount = 25
        var stableCount = 0
        let alignmentDeadline = Date().addingTimeInterval(25)

        while stableCount < targetStableCount {
            try Task.checkCancellation()
            guard Date() < alignmentDeadline else {
                throw BridgeError.invalid("未能在時限內對準最佳位置，請微調手機頂端貼齊天線後重試")
            }

            var probeOk = false
            do {
                let resp = try await exchange(Data([0xcd, 0x0d]), tag: tag)
                probeOk = (resp == Data([0, 0]))
            } catch {
                probeOk = false
            }

            if probeOk {
                stableCount += 1
                let percent = Int(Double(stableCount) / Double(targetStableCount) * 100)
                self.currentScore = percent
                if stableCount % 5 == 0 {
                    AudioServicesPlaySystemSound(1519)
                }
                message = "已偵測訊號，對位充能中（\(percent)%）... 請保持不動"
                session.alertMessage = message
            } else {
                if stableCount > 0 {
                    stableCount = 0
                    self.currentScore = 0
                    message = "位置偏移或訊號微弱，請微調手機頂端貼齊天線"
                    session.alertMessage = message
                }
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        diag.alignmentDuration = Date().timeIntervalSince(alignStart)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        message = "最佳位置已鎖定！電量充足，開始傳送..."
        session.alertMessage = message
        try await Task.sleep(nanoseconds: 80_000_000)

        // Phase 2: Initialization (Model 14)
        message = "正在初始化電子紙，請保持不動"
        session.alertMessage = message
        let commands: [[UInt8]] = [
            [0xcd, 0x0d], [0xcd, 0x00, 0x0e], [0xcd, 0x01],
            [0xcd, 0x02], [0xcd, 0x03], [0xcd, 0x05], [0xcd, 0x06], [0xcd, 0x07]
        ]
        for command in commands {
            try await acknowledged(command, tag: tag)
            if command != [0xcd, 0x0d] {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }

        // Phase 3: Send 400 packets of 120 bytes (Optimized 5ms packet pacing)
        let txStart = Date()
        for offset in stride(from: 0, to: frame.count, by: 120) {
            var command = Data([0xcd, 0x08, 120])
            command.append(frame.subdata(in: offset..<(offset + 120)))
            let response = try await exchange(command, tag: tag)
            guard response == Data([0, 0]) else {
                throw BridgeError.invalid("電子紙未接受第 \(offset / 120 + 1) 段圖片；已停止，避免錯位")
            }
            progress = Double(offset + 120) / Double(frame.count) * 0.9
            if offset % 1200 == 0 {
                message = "NFC 傳送 \(Int(progress * 100))%，請保持不動"
                session.alertMessage = message
            }
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms pacing
        }
        diag.transmissionDuration = Date().timeIntervalSince(txStart)

        // Phase 4: Trigger Refresh
        try await acknowledged([0xcd, 0x18], tag: tag)
        try await acknowledged([0xcd, 0x09], tag: tag)
        message = "圖片已 100% 送達！電子紙正在刷新，請務必持續貼近保持不動..."
        session.alertMessage = message

        // Phase 5: Keep RF carrier power continuously active (6ms pacing) until 0xFF 00 is received
        let rfStart = Date()
        let refreshDeadline = min(deadline, Date().addingTimeInterval(20))
        while Date() < refreshDeadline {
            try await Task.sleep(nanoseconds: 6_000_000)
            let response: Data
            do {
                response = try await exchange(Data([0xcd, 0x0a]), tag: tag)
            } catch {
                // Keep the RF field active even if the board is busy drawing charge pump current!
                continue
            }
            if response == Data([0xff, 0]) {
                _ = try? await exchange(Data([0xcd, 0x04]), tag: tag)
                diag.refreshDuration = Date().timeIntervalSince(rfStart)
                diag.finalResult = "刷新完成"
                self.diagnostics = diag
                message = "電子紙已回報刷新完成，請確認實際畫面"
                return
            }
        }
        _ = try? await exchange(Data([0xcd, 0x04]), tag: tag)
        diag.refreshDuration = Date().timeIntervalSince(rfStart)
        diag.finalResult = "刷新結束"
        self.diagnostics = diag
        message = "刷新時間結束，請確認電子紙畫面"
    }
}
