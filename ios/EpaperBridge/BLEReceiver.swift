import CoreBluetooth
import Combine
import Foundation
import UIKit

// CoreBluetooth delegate callbacks and UI calls all run on the main queue.
final class BLEReceiver: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let serviceID = CBUUID(string: "e3911000-7c21-4e12-9234-18a3347a6000")
    static let controlID = CBUUID(string: "e3911001-7c21-4e12-9234-18a3347a6000")
    static let dataID = CBUUID(string: "e3911002-7c21-4e12-9234-18a3347a6000")
    static let statusID = CBUUID(string: "e3911003-7c21-4e12-9234-18a3347a6000")

    @Published var message = "開啟接收後，請從電腦傳送圖片"
    @Published var receiving = false
    @Published var progress = 0.0
    @Published var image: UIImage?
    @Published var frame: Data?
    private var manager: CBPeripheralManager!
    private var serviceReady = false
    private var servicePending = false
    private var owner: UUID?
    private var lastWrite = Date.distantPast
    private var buffer = Data()
    private var expectedCRC: UInt32 = 0
    private var state: UInt8 = 0
    private var acceptedCRC: UInt32 = 0
    private var wifiMode = false
    private var expectedLength = Frame.byteCount
    private var downloadTask: Task<Void, Never>?
    private var generation = UUID()

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
        if let stored = try? Data(contentsOf: Self.storageURL), stored.count == Frame.byteCount {
            frame = stored
            image = Frame.preview(stored)
        }
    }

    private static var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last-frame.bin")
    }

    func start() {
        stop()
        receiving = true
        UIApplication.shared.isIdleTimerDisabled = true
        progress = 0
        owner = nil
        buffer.removeAll()
        state = 0
        message = "等待電腦連線；請保持 App 在前景"
        advertiseIfReady()
    }

    func stop() {
        generation = UUID()
        downloadTask?.cancel()
        downloadTask = nil
        if state == 1 || state == 3 { state = 0 }
        receiving = false
        manager.stopAdvertising()
        owner = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func advertiseIfReady() {
        guard receiving, manager.state == .poweredOn, serviceReady else { return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceID],
            CBAdvertisementDataLocalNameKey: "EpaperBridge"
        ])
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            serviceReady = false
            servicePending = false
            stop()
            message = "請開啟藍牙並允許 App 使用藍牙，再按接收"
            return
        }
        guard !serviceReady, !servicePending else { advertiseIfReady(); return }
        let service = CBMutableService(type: Self.serviceID, primary: true)
        service.characteristics = [
            CBMutableCharacteristic(type: Self.controlID, properties: [.write], value: nil, permissions: [.writeable]),
            CBMutableCharacteristic(type: Self.dataID, properties: [.write], value: nil, permissions: [.writeable]),
            CBMutableCharacteristic(type: Self.statusID, properties: [.read], value: nil, permissions: [.readable])
        ]
        servicePending = true
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        servicePending = false
        if let error { message = error.localizedDescription; stop(); return }
        serviceReady = true
        advertiseIfReady()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error { message = error.localizedDescription; stop() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == Self.statusID else {
            peripheral.respond(to: request, withResult: .requestNotSupported); return
        }
        var status = Data([state])
        status.appendLE(UInt32(buffer.count))
        status.appendLE(acceptedCRC)
        guard request.offset <= status.count else {
            peripheral.respond(to: request, withResult: .invalidOffset); return
        }
        request.value = status.subdata(in: request.offset..<status.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        // The protocol uses one acknowledged write at a time, never ATT long writes.
        guard requests.count == 1, first.offset == 0 else {
            peripheral.respond(to: first, withResult: .requestNotSupported); return
        }
        do {
            guard receiving, let value = first.value, !value.isEmpty else {
                throw BridgeError.invalid("請重新按接收，再從電腦傳送")
            }
            try consume(value, characteristic: first.characteristic.uuid, central: first.central.identifier)
            peripheral.respond(to: first, withResult: .success)
        } catch {
            message = error.localizedDescription
            peripheral.respond(to: first, withResult: .unlikelyError)
        }
    }

    private func consume(_ packet: Data, characteristic: CBUUID, central: UUID) throws {
        let isBegin = characteristic == Self.controlID && (packet[0] == 1 || packet[0] == 4)
        if isBegin {
            guard state != 3 else { throw BridgeError.invalid("正在下載圖片，請等待或取消接收") }
            guard owner == nil || owner == central || Date().timeIntervalSince(lastWrite) > 60 else {
                throw BridgeError.invalid("另一台電腦正在傳送")
            }
            if packet[0] == 4 {
                guard packet.count == 9, (1...1024).contains(Int(packet.littleEndian(1, 4))) else {
                    throw BridgeError.invalid("Wi-Fi 交接資料長度不正確")
                }
                wifiMode = true
                expectedLength = Int(packet.littleEndian(1, 4))
                expectedCRC = packet.littleEndian(5, 4)
            } else {
                guard packet.count == 13, packet.littleEndian(1, 2) == 800,
                  packet.littleEndian(3, 2) == 480, packet.littleEndian(5, 4) == 48000 else {
                    throw BridgeError.invalid("只接受 800 × 480 黑白圖片")
                }
                wifiMode = false
                expectedLength = Frame.byteCount
                expectedCRC = packet.littleEndian(9, 4)
            }
            owner = central
            buffer = Data()
            acceptedCRC = 0
            state = 1
            progress = 0
            message = wifiMode ? "BLE 已連線，正在取得快速傳圖資訊" : "正在透過 BLE 接收圖片"
        } else {
            guard owner == central, state == 1 else {
                throw BridgeError.invalid("傳送已中斷，請從頭重新傳送")
            }
            if characteristic == Self.dataID, packet[0] == 2 {
                guard (6...20).contains(packet.count), packet.littleEndian(1, 4) == UInt32(buffer.count),
                      buffer.count + packet.count - 5 <= expectedLength else {
                    throw BridgeError.invalid("圖片分段順序或長度錯誤，請從頭重新傳送")
                }
                buffer.append(packet.dropFirst(5))
                progress = Double(buffer.count) / Double(expectedLength)
            } else if characteristic == Self.controlID, packet == Data([3]) {
                guard buffer.count == expectedLength, Frame.crc32(buffer) == expectedCRC else {
                    throw BridgeError.invalid("圖片不完整或 CRC 檢查失敗，請從頭重新傳送")
                }
                if wifiMode {
                    let descriptor = try JSONDecoder().decode(LANImageDescriptor.self, from: buffer)
                    _ = try descriptor.checkedURL()
                    startDownload(descriptor)
                    return
                }
                try buffer.write(to: Self.storageURL, options: .atomic)
                frame = buffer
                image = Frame.preview(buffer)
                acceptedCRC = expectedCRC
                state = 2
                message = "圖片已完整接收，可以更新電子紙"
                stop()
            } else {
                throw BridgeError.invalid("無法辨識的傳送指令")
            }
        }
        lastWrite = Date()
    }

    private func startDownload(_ descriptor: LANImageDescriptor) {
        state = 3
        progress = 0
        message = "正在透過區域網路下載圖片；請允許區域網路存取並保持 App 在前景"
        let currentGeneration = generation
        downloadTask = Task { @MainActor in
            do {
                let downloaded = try await LANFetcher().fetch(descriptor)
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                try downloaded.write(to: Self.storageURL, options: .atomic)
                self.buffer = downloaded
                self.frame = downloaded
                self.image = Frame.preview(downloaded)
                self.acceptedCRC = descriptor.crc32
                self.state = 4
                self.progress = 1
                self.message = "圖片已透過區域網路完整接收，可以更新電子紙"
                self.downloadTask = nil
                self.stop()
            } catch {
                guard self.generation == currentGeneration else { return }
                self.state = 5
                self.message = "快速傳圖失敗：\(error.localizedDescription)。請確認同一區域網路、權限與電腦防火牆，或改用純 BLE 傳圖。"
                self.downloadTask = nil
                self.stop()
            }
        }
    }
}
