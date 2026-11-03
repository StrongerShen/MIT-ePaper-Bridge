import Combine
import Foundation
import UIKit

struct TemplateItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String
    var category: Category
    var createdAt: Date = Date()
    var filename: String

    // Structured fields for Business Card
    var cardNameZh: String?
    var cardNameEn: String?
    var cardIsVertical: Bool?
    var cardIncludeQR: Bool?
    var cardStyle: String?
    var cardName: String? // legacy
    var cardTitle: String?
    var cardCompany: String?
    var cardPhone: String?
    var cardEmail: String?
    var cardNote: String?

    // Structured fields for Memo
    var memoTitle: String?
    var memoContent: String?
    var memoDate: String?
    var memoStyle: String?

    // Structured fields for QR Code
    var qrText: String?
    var qrTitle: String?
    var qrSubtitle: String?
    var qrStyle: String?

    enum Category: String, Codable, CaseIterable {
        case card = "名片"
        case memo = "備忘錄"
        case qrcode = "QR Code"
        case photo = "相片"
        case testPattern = "測試圖"

        var iconName: String {
            switch self {
            case .card: return "person.text.rectangle"
            case .memo: return "note.text"
            case .qrcode: return "qrcode"
            case .photo: return "photo"
            case .testPattern: return "checklist"
            }
        }
    }
}

final class TemplateStore: ObservableObject {
    @Published var items: [TemplateItem] = []

    private static var baseDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Templates", isDirectory: true)
    }

    private static var indexURL: URL {
        baseDirectory.appendingPathComponent("templates_index.json")
    }

    init() {
        try? FileManager.default.createDirectory(at: Self.baseDirectory, withIntermediateDirectories: true)
        loadIndex()
        sanitizePresets()
    }

    func loadIndex() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? JSONDecoder().decode([TemplateItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    func saveIndex() {
        guard let encoded = try? JSONEncoder().encode(items) else { return }
        try? encoded.write(to: Self.indexURL, options: .atomic)
    }

    func save(
        title: String,
        subtitle: String,
        category: TemplateItem.Category,
        frame: Data,
        cardNameZh: String? = nil,
        cardNameEn: String? = nil,
        cardIsVertical: Bool? = nil,
        cardIncludeQR: Bool? = nil,
        cardStyle: String? = nil,
        cardName: String? = nil,
        cardTitle: String? = nil,
        cardCompany: String? = nil,
        cardPhone: String? = nil,
        cardEmail: String? = nil,
        cardNote: String? = nil,
        memoTitle: String? = nil,
        memoContent: String? = nil,
        memoDate: String? = nil,
        memoStyle: String? = nil,
        qrText: String? = nil,
        qrTitle: String? = nil,
        qrSubtitle: String? = nil,
        qrStyle: String? = nil
    ) {
        guard frame.count == Frame.byteCount else { return }
        let id = UUID()
        let filename = "item_\(id.uuidString).bin"
        let fileURL = Self.baseDirectory.appendingPathComponent(filename)
        try? frame.write(to: fileURL, options: .atomic)

        let item = TemplateItem(
            id: id,
            title: title.isEmpty ? category.rawValue : title,
            subtitle: subtitle,
            category: category,
            createdAt: Date(),
            filename: filename,
            cardNameZh: cardNameZh,
            cardNameEn: cardNameEn,
            cardIsVertical: cardIsVertical,
            cardIncludeQR: cardIncludeQR,
            cardStyle: cardStyle,
            cardName: cardName ?? cardNameZh,
            cardTitle: cardTitle,
            cardCompany: cardCompany,
            cardPhone: cardPhone,
            cardEmail: cardEmail,
            cardNote: cardNote,
            memoTitle: memoTitle,
            memoContent: memoContent,
            memoDate: memoDate,
            memoStyle: memoStyle,
            qrText: qrText,
            qrTitle: qrTitle,
            qrSubtitle: qrSubtitle,
            qrStyle: qrStyle
        )
        items.insert(item, at: 0)
        saveIndex()
    }

    func loadFrame(for item: TemplateItem) -> Data? {
        let fileURL = Self.baseDirectory.appendingPathComponent(item.filename)
        guard let data = try? Data(contentsOf: fileURL), data.count == Frame.byteCount else {
            return nil
        }
        return data
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            let fileURL = Self.baseDirectory.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.remove(atOffsets: offsets)
        saveIndex()
    }

    func delete(item: TemplateItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let fileURL = Self.baseDirectory.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: fileURL)
            items.remove(at: index)
            saveIndex()
        }
    }

    private func sanitizePresets() {
        var modified = false
        // Purge any legacy items referencing Waveshare from previous builds
        items.removeAll { item in
            if item.title.localizedCaseInsensitiveContains("waveshare") ||
               item.subtitle.localizedCaseInsensitiveContains("waveshare") {
                let fileURL = Self.baseDirectory.appendingPathComponent(item.filename)
                try? FileManager.default.removeItem(at: fileURL)
                modified = true
                return true
            }
            return false
        }

        // Update card subtitle from old to MIT
        for i in 0..<items.count {
            if items[i].subtitle.contains("MobileIT Studio") {
                items[i].subtitle = "Tech Lead · MIT 台灣智造"
                modified = true
            }
            // Backfill structured fields for default card if missing
            if items[i].category == .card {
                if items[i].cardNameZh == nil || items[i].cardEmail != "contact@mit.com.tw" {
                    items[i].cardNameZh = "陳智造"
                    items[i].cardNameEn = "Alex Chen"
                    items[i].cardIsVertical = false
                    items[i].cardIncludeQR = true
                    items[i].cardStyle = "商務現代"
                    items[i].cardTitle = "Tech Lead & Architect"
                    items[i].cardCompany = "Mobile Intelligence Technology"
                    items[i].cardPhone = "+886 2-1234-5678"
                    items[i].cardEmail = "contact@mit.com.tw"
                    items[i].cardNote = "MIT 7.5\" e-Paper Bridge"
                    modified = true
                }
            }
            // Backfill structured fields for default memo if missing
            if items[i].category == .memo && items[i].memoTitle == nil {
                items[i].memoTitle = "本日重點備忘事項"
                items[i].memoContent = "1. 檢視電子紙 800x480 更新成效\n2. 測試 NFC 最佳對位強度\n3. 完成展示畫面拍攝與紀錄"
                items[i].memoDate = "2026-11-03 · Taipei"
                items[i].memoStyle = "標準告示"
                modified = true
            }
            // Backfill structured fields for default QR code if missing
            if items[i].category == .qrcode && items[i].qrText == nil {
                items[i].qrText = "https://mit.com.tw/"
                items[i].qrTitle = "Mobile Intelligence Technology."
                items[i].qrSubtitle = "掃描造訪 MIT 台灣智造"
                items[i].qrStyle = "左圖右文"
                modified = true
            }
        }

        // Ensure MIT Taiwan QR Code is present
        if !items.contains(where: { $0.category == .qrcode }) {
            let qrImg = ImageProcessor.generateQRCode(
                text: "https://mit.com.tw/",
                title: "Mobile Intelligence Technology.",
                subtitle: "掃描造訪 MIT 台灣智造"
            )
            let qrData = ImageProcessor.binarize(image: qrImg, threshold: 140)
            save(
                title: "預設 QR Code：MIT 台灣智造",
                subtitle: "Mobile Intelligence Technology.",
                category: .qrcode,
                frame: qrData,
                qrText: "https://mit.com.tw/",
                qrTitle: "Mobile Intelligence Technology.",
                qrSubtitle: "掃描造訪 MIT 台灣智造",
                qrStyle: "左圖右文"
            )
            modified = true
        }

        if items.isEmpty {
            createDefaultPresets()
        } else if modified {
            saveIndex()
        }
    }

    private func createDefaultPresets() {
        // Preset 1: Business Card (With Chinese + English names and QR Code)
        let cardImg = ImageProcessor.generateBusinessCard(
            nameZh: "陳智造",
            nameEn: "Alex Chen",
            title: "Tech Lead & Architect",
            company: "Mobile Intelligence Technology",
            phone: "+886 2-1234-5678",
            email: "contact@mit.com.tw",
            note: "MIT 7.5\" e-Paper Bridge",
            orientation: .horizontal,
            style: .modern,
            includeQR: true
        )
        let cardData = ImageProcessor.binarize(image: cardImg, threshold: 140)
        save(
            title: "預設名片：陳智造 Alex",
            subtitle: "Tech Lead · MIT 台灣智造",
            category: .card,
            frame: cardData,
            cardNameZh: "陳智造",
            cardNameEn: "Alex Chen",
            cardIsVertical: false,
            cardIncludeQR: true,
            cardStyle: "商務現代",
            cardName: "陳智造",
            cardTitle: "Tech Lead & Architect",
            cardCompany: "Mobile Intelligence Technology",
            cardPhone: "+886 2-1234-5678",
            cardEmail: "contact@mit.com.tw",
            cardNote: "MIT 7.5\" e-Paper Bridge"
        )

        // Preset 2: Memo
        let memoImg = ImageProcessor.generateMemo(
            title: "本日重點備忘事項",
            content: "1. 檢視電子紙 800x480 更新成效\n2. 測試 NFC 最佳對位強度\n3. 完成展示畫面拍攝與紀錄",
            date: "2026-11-03 · Taipei"
        )
        let memoData = ImageProcessor.binarize(image: memoImg, threshold: 140)
        save(
            title: "預設備忘錄：重點事項",
            subtitle: "3 項待辦項目",
            category: .memo,
            frame: memoData,
            memoTitle: "本日重點備忘事項",
            memoContent: "1. 檢視電子紙 800x480 更新成效\n2. 測試 NFC 最佳對位強度\n3. 完成展示畫面拍攝與紀錄",
            memoDate: "2026-11-03 · Taipei",
            memoStyle: "標準告示"
        )

        // Preset 3: QR Code
        let qrImg = ImageProcessor.generateQRCode(
            text: "https://mit.com.tw/",
            title: "Mobile Intelligence Technology.",
            subtitle: "掃描造訪 MIT 台灣智造"
        )
        let qrData = ImageProcessor.binarize(image: qrImg, threshold: 140)
        save(
            title: "預設 QR Code：MIT 台灣智造",
            subtitle: "Mobile Intelligence Technology.",
            category: .qrcode,
            frame: qrData,
            qrText: "https://mit.com.tw/",
            qrTitle: "Mobile Intelligence Technology.",
            qrSubtitle: "掃描造訪 MIT 台灣智造",
            qrStyle: "左圖右文"
        )
    }
}
