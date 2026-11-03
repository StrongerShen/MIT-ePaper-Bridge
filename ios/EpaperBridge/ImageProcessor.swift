import CoreGraphics
import CoreImage
import Foundation
import UIKit

// Card Layout Enums
enum CardOrientation: String, Codable, CaseIterable {
    case horizontal = "橫式"
    case vertical = "直式"
}

enum CardStyle: String, Codable, CaseIterable {
    case modern = "商務現代"
    case classic = "簡約經典"
    case tech = "科技風格"
}

// Memo Layout Enums
enum MemoStyle: String, Codable, CaseIterable {
    case banner = "標準告示"
    case checklist = "代辦清單"
    case frame = "極簡便籤"
}

// QR Code Layout Enums
enum QRStyle: String, Codable, CaseIterable {
    case sideBySide = "左圖右文"
    case centered = "置中大圖"
    case techBadge = "科技看板"
}

// Font Family Enum with verified pre-installed iOS CJK and Western fonts
enum AppFontFamily: String, Codable, CaseIterable {
    case sansSerif = "黑體"
    case serif = "明體"
    case rounded = "圓體"
    case monospace = "等寬"

    // Primary font (supports CJK Traditional Chinese + Western glyphs)
    func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch self {
        case .sansSerif:
            // PingFang TC: modern, crisp sans-serif
            let fontName = (weight == .heavy || weight == .bold) ? "PingFangTC-Semibold" : (weight == .medium ? "PingFangTC-Medium" : "PingFangTC-Regular")
            return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)

        case .serif:
            // Hiragino Mincho ProN (柊野明朝體): pre-installed on iOS, genuine CJK serif with thick/thin strokes & serifs
            let fontName = (weight == .heavy || weight == .bold) ? "HiraMinProN-W6" : "HiraMinProN-W3"
            return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)

        case .rounded:
            // Hiragino Maru Gothic ProN (柊野圓體): pre-installed on iOS, genuine CJK rounded font with round stroke ends
            return UIFont(name: "HiraMaruProN-W4", size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)

        case .monospace:
            // Menlo / Courier: developer & engineering aesthetic
            let fontName = (weight == .heavy || weight == .bold) ? "Menlo-Bold" : "Menlo-Regular"
            return UIFont(name: fontName, size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    // Western font pairing (dramatically accentuates font style for English names, titles, and contacts)
    func westernFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch self {
        case .sansSerif:
            let fontName = (weight == .heavy || weight == .bold) ? "AvenirNext-Bold" : "AvenirNext-Medium"
            return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)

        case .serif:
            let fontName = (weight == .heavy || weight == .bold) ? "Georgia-Bold" : "Georgia"
            return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)

        case .rounded:
            return UIFont(name: "ArialRoundedMTBold", size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)

        case .monospace:
            let fontName = (weight == .heavy || weight == .bold) ? "Menlo-Bold" : "Menlo-Regular"
            return UIFont(name: fontName, size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

// High-performance image processing and layout rendering for 800 × 480 1-bit e-Paper.
enum ImageProcessor {
    static let width = Frame.width
    static let height = Frame.height
    static let byteCount = Frame.byteCount

    // MARK: - Floyd-Steinberg Error Diffusion Dithering (For Photos)
    static func dither(image: UIImage) -> Data {
        var floatBuffer = renderGrayscaleFloats(image: image)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let oldPixel = floatBuffer[index]
                let newPixel: Float = oldPixel < 128.0 ? 0.0 : 255.0
                let error = oldPixel - newPixel
                floatBuffer[index] = newPixel

                if x + 1 < width {
                    floatBuffer[index + 1] += error * (7.0 / 16.0)
                }
                if y + 1 < height {
                    if x > 0 {
                        floatBuffer[(y + 1) * width + (x - 1)] += error * (3.0 / 16.0)
                    }
                    floatBuffer[(y + 1) * width + x] += error * (5.0 / 16.0)
                    if x + 1 < width {
                        floatBuffer[(y + 1) * width + (x + 1)] += error * (1.0 / 16.0)
                    }
                }
            }
        }

        return packBits(floatBuffer: floatBuffer)
    }

    // MARK: - Smooth Edge Anti-Aliasing Binarization (Eliminates Jaggies for Typography & Line Art)
    static func smoothBinarize(image: UIImage) -> Data {
        var floatBuffer = renderGrayscaleFloats(image: image)

        // Selective error diffusion restricted to anti-aliased glyph transition edges (55 < pixel < 245)
        // Background stays 100% spotless white, glyph centers stay 100% pitch black,
        // and curved/diagonal edges are rendered with smooth sub-pixel curves without staircasing.
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let oldPixel = floatBuffer[index]

                // Pure background: keep pristine white without noise
                if oldPixel >= 242.0 {
                    floatBuffer[index] = 255.0
                    continue
                }

                // Core glyph body: keep solid bold black
                if oldPixel <= 55.0 {
                    floatBuffer[index] = 0.0
                    continue
                }

                // Transition edge: smooth error diffusion
                let newPixel: Float = oldPixel < 150.0 ? 0.0 : 255.0
                let error = oldPixel - newPixel
                floatBuffer[index] = newPixel

                if x + 1 < width {
                    floatBuffer[index + 1] = min(255.0, max(0.0, floatBuffer[index + 1] + error * (7.0 / 16.0)))
                }
                if y + 1 < height {
                    if x > 0 {
                        floatBuffer[(y + 1) * width + (x - 1)] = min(255.0, max(0.0, floatBuffer[(y + 1) * width + (x - 1)] + error * (3.0 / 16.0)))
                    }
                    floatBuffer[(y + 1) * width + x] = min(255.0, max(0.0, floatBuffer[(y + 1) * width + x] + error * (5.0 / 16.0)))
                    if x + 1 < width {
                        floatBuffer[(y + 1) * width + (x + 1)] = min(255.0, max(0.0, floatBuffer[(y + 1) * width + (x + 1)] + error * (1.0 / 16.0)))
                    }
                }
            }
        }

        return packBits(floatBuffer: floatBuffer)
    }

    // MARK: - Direct Threshold Binarization (Hard Edge)
    static func binarize(image: UIImage, threshold: Float = 128.0) -> Data {
        var floatBuffer = renderGrayscaleFloats(image: image)
        for i in 0..<(width * height) {
            floatBuffer[i] = floatBuffer[i] < threshold ? 0.0 : 255.0
        }
        return packBits(floatBuffer: floatBuffer)
    }

    // Packs 800x480 float buffer (0.0=black, 255.0=white) into 48,000 bytes (1=white, 0=black, MSB first)
    private static func packBits(floatBuffer: [Float]) -> Data {
        var packed = Data(count: byteCount)
        let bytesPerRow = width / 8
        for y in 0..<height {
            for bx in 0..<bytesPerRow {
                var byte: UInt8 = 0
                for bit in 0..<8 {
                    let x = bx * 8 + bit
                    if floatBuffer[y * width + x] >= 128.0 {
                        byte |= (0x80 >> bit)
                    }
                }
                packed[y * bytesPerRow + bx] = byte
            }
        }
        return packed
    }

    // Extracts normalized grayscale float buffer (0.0 = black, 255.0 = white)
    // using UIKit's native top-to-bottom coordinate system and standard RGB luminance.
    private static func renderGrayscaleFloats(image: UIImage) -> [Float] {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Strictly 1x scale: exactly 800 x 480 pixels
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.setAllowsFontSmoothing(true)
            cg.setShouldSmoothFonts(true)

            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let wRatio = size.width / image.size.width
            let hRatio = size.height / image.size.height
            let scale = min(wRatio, hRatio)
            let drawWidth = image.size.width * scale
            let drawHeight = image.size.height * scale
            let drawRect = CGRect(
                x: (size.width - drawWidth) / 2.0,
                y: (size.height - drawHeight) / 2.0,
                width: drawWidth,
                height: drawHeight
            )
            image.draw(in: drawRect)
        }

        guard let cgImage = rendered.cgImage,
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return [Float](repeating: 255.0, count: width * height)
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var floatBuffer = [Float](repeating: 255.0, count: width * height)
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let pxOffset = rowOffset + x * bytesPerPixel
                let r = Float(ptr[pxOffset])
                let g = Float(ptr[pxOffset + 1])
                let b = Float(ptr[pxOffset + 2])
                let gray = 0.299 * r + 0.587 * g + 0.114 * b
                floatBuffer[y * width + x] = gray
            }
        }
        return floatBuffer
    }

    // MARK: - Image Transformation (Rotation & Dual Side-by-Side)

    static func rotate(image: UIImage, by degrees: Int) -> UIImage {
        let normalized = ((degrees % 360) + 360) % 360
        guard normalized != 0 else { return image }
        let radians = CGFloat(normalized) * .pi / 180.0

        var newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians)).integral.size
        newSize.width = floor(abs(newSize.width))
        newSize.height = floor(abs(newSize.height))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let context = ctx.cgContext
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.translateBy(x: newSize.width / 2.0, y: newSize.height / 2.0)
            context.rotate(by: radians)
            image.draw(in: CGRect(
                x: -image.size.width / 2.0,
                y: -image.size.height / 2.0,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    static func combineDualPhotos(left: UIImage?, right: UIImage?) -> UIImage {
        let size = CGSize(width: width, height: height)
        let halfWidth: CGFloat = 400.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            if let left {
                drawAspectFit(image: left, in: CGRect(x: 10, y: 10, width: halfWidth - 20, height: CGFloat(height) - 20))
            }

            UIColor.black.setFill()
            ctx.fill(CGRect(x: halfWidth - 1, y: 20, width: 2, height: CGFloat(height) - 40))

            if let right {
                drawAspectFit(image: right, in: CGRect(x: halfWidth + 10, y: 10, width: halfWidth - 20, height: CGFloat(height) - 20))
            }
        }
    }

    private static func drawAspectFit(image: UIImage, in rect: CGRect) {
        guard image.size.width > 0 && image.size.height > 0 else { return }
        let wRatio = rect.width / image.size.width
        let hRatio = rect.height / image.size.height
        let scale = min(wRatio, hRatio)
        let drawWidth = image.size.width * scale
        let drawHeight = image.size.height * scale
        let drawRect = CGRect(
            x: rect.minX + (rect.width - drawWidth) / 2.0,
            y: rect.minY + (rect.height - drawHeight) / 2.0,
            width: drawWidth,
            height: drawHeight
        )
        image.draw(in: drawRect)
    }

    // MARK: - CoreImage QR Code Generator Helper
    static func createQRCodeImage(from text: String, size: CGFloat) -> UIImage? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scale = size / ciImage.extent.width
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Business Card Generator (Supports Chinese & English names, Vertical/Horizontal, Font Families, and Optional QR Code)

    static func generateBusinessCard(
        nameZh: String,
        nameEn: String,
        title: String,
        company: String,
        phone: String,
        email: String,
        note: String,
        orientation: CardOrientation = .horizontal,
        style: CardStyle = .modern,
        fontFamily: AppFontFamily = .sansSerif,
        includeQR: Bool = true,
        qrPayload: String? = nil
    ) -> UIImage {
        if orientation == .vertical {
            let verticalImage = renderVerticalBusinessCard(
                nameZh: nameZh,
                nameEn: nameEn,
                title: title,
                company: company,
                phone: phone,
                email: email,
                note: note,
                style: style,
                fontFamily: fontFamily,
                includeQR: includeQR,
                qrPayload: qrPayload
            )
            return rotate(image: verticalImage, by: 90)
        } else {
            return renderHorizontalBusinessCard(
                nameZh: nameZh,
                nameEn: nameEn,
                title: title,
                company: company,
                phone: phone,
                email: email,
                note: note,
                style: style,
                fontFamily: fontFamily,
                includeQR: includeQR,
                qrPayload: qrPayload
            )
        }
    }

    // Legacy overload for backward compatibility
    static func generateBusinessCard(name: String, title: String, company: String, phone: String, email: String, note: String) -> UIImage {
        return generateBusinessCard(
            nameZh: name,
            nameEn: "",
            title: title,
            company: company,
            phone: phone,
            email: email,
            note: note,
            orientation: .horizontal,
            style: .modern,
            fontFamily: .sansSerif,
            includeQR: false
        )
    }

    // Horizontal Business Card (800 × 480)
    private static func renderHorizontalBusinessCard(
        nameZh: String,
        nameEn: String,
        title: String,
        company: String,
        phone: String,
        email: String,
        note: String,
        style: CardStyle,
        fontFamily: AppFontFamily,
        includeQR: Bool,
        qrPayload: String?
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.setAllowsFontSmoothing(true)
            cg.setShouldSmoothFonts(true)

            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let leftMargin: CGFloat = 50
            let contentWidth: CGFloat = includeQR ? 460 : 700

            switch style {
            case .modern:
                UIColor.black.setFill()
                // Top double bar
                ctx.fill(CGRect(x: 50, y: 35, width: 700, height: 6))
                ctx.fill(CGRect(x: 50, y: 45, width: 700, height: 2))
                // Bottom bar
                ctx.fill(CGRect(x: 50, y: 440, width: 700, height: 5))

            case .classic:
                UIColor.black.setStroke()
                let outerRect = CGRect(x: 25, y: 20, width: 750, height: 440)
                let innerRect = CGRect(x: 32, y: 27, width: 736, height: 426)
                ctx.cgContext.setLineWidth(2.0)
                ctx.stroke(outerRect)
                ctx.cgContext.setLineWidth(1.0)
                ctx.stroke(innerRect)

            case .tech:
                UIColor.black.setFill()
                ctx.fill(CGRect(x: 40, y: 25, width: 720, height: 65))
                let bannerAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                company.draw(in: CGRect(x: 55, y: 45, width: 690, height: 30), withAttributes: bannerAttr)
            }

            // Company (for Modern & Classic)
            if style != .tech {
                let compAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 24, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                company.draw(in: CGRect(x: leftMargin, y: 65, width: contentWidth, height: 32), withAttributes: compAttr)
            }

            // Chinese and English Names
            let nameStartY: CGFloat = (style == .tech) ? 105 : 108
            if !nameZh.isEmpty && !nameEn.isEmpty {
                let zhAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 46, weight: .heavy),
                    .foregroundColor: UIColor.black
                ]
                nameZh.draw(at: CGPoint(x: leftMargin, y: nameStartY), withAttributes: zhAttr)

                let enAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.westernFont(ofSize: 22, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
                nameEn.draw(at: CGPoint(x: leftMargin, y: nameStartY + 54), withAttributes: enAttr)
            } else {
                let displayName = nameZh.isEmpty ? nameEn : nameZh
                let nameAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 50, weight: .heavy),
                    .foregroundColor: UIColor.black
                ]
                displayName.draw(in: CGRect(x: leftMargin, y: nameStartY, width: contentWidth, height: 60), withAttributes: nameAttr)
            }

            // Title
            let titleY: CGFloat = nameStartY + 84
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: fontFamily.westernFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            title.draw(in: CGRect(x: leftMargin, y: titleY, width: contentWidth, height: 30), withAttributes: titleAttr)

            // Divider line
            UIColor.black.setFill()
            ctx.fill(CGRect(x: leftMargin, y: titleY + 36, width: contentWidth, height: 2))

            // Contact Info
            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: fontFamily.westernFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            var contactLines: [String] = []
            if !phone.isEmpty { contactLines.append("TEL:  \(phone)") }
            if !email.isEmpty { contactLines.append("MAIL: \(email)") }
            if !note.isEmpty { contactLines.append("NOTE: \(note)") }
            let contactText = contactLines.joined(separator: "\n")
            contactText.draw(in: CGRect(x: leftMargin, y: titleY + 48, width: contentWidth, height: 110), withAttributes: bodyAttr)

            // Optional QR Code on Right
            if includeQR {
                let qrPayloadStr = (qrPayload?.isEmpty == false) ? qrPayload! : buildVCard(
                    nameZh: nameZh,
                    nameEn: nameEn,
                    company: company,
                    title: title,
                    phone: phone,
                    email: email,
                    note: note
                )

                let qrSize: CGFloat = 190
                let qrRect = CGRect(x: 540, y: 110, width: qrSize, height: qrSize)

                if let qrImage = createQRCodeImage(from: qrPayloadStr, size: qrSize) {
                    qrImage.draw(in: qrRect)

                    UIColor.black.setStroke()
                    ctx.cgContext.setLineWidth(1.5)
                    ctx.stroke(qrRect.insetBy(dx: -4, dy: -4))

                    let tipAttr: [NSAttributedString.Key: Any] = [
                        .font: fontFamily.font(ofSize: 13, weight: .bold),
                        .foregroundColor: UIColor.black
                    ]
                    let tipText = "掃描名片通訊錄"
                    let tipWidth = (tipText as NSString).size(withAttributes: tipAttr).width
                    tipText.draw(at: CGPoint(x: qrRect.midX - tipWidth / 2.0, y: qrRect.maxY + 12), withAttributes: tipAttr)
                }
            }
        }
    }

    // Vertical Business Card (480 × 800)
    private static func renderVerticalBusinessCard(
        nameZh: String,
        nameEn: String,
        title: String,
        company: String,
        phone: String,
        email: String,
        note: String,
        style: CardStyle,
        fontFamily: AppFontFamily,
        includeQR: Bool,
        qrPayload: String?
    ) -> UIImage {
        let vSize = CGSize(width: 480, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: vSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.setAllowsFontSmoothing(true)
            cg.setShouldSmoothFonts(true)

            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: vSize))

            let leftMargin: CGFloat = 36
            let contentWidth: CGFloat = 480 - leftMargin * 2

            switch style {
            case .modern:
                UIColor.black.setFill()
                ctx.fill(CGRect(x: leftMargin, y: 35, width: contentWidth, height: 6))
                ctx.fill(CGRect(x: leftMargin, y: 45, width: contentWidth, height: 2))
                ctx.fill(CGRect(x: leftMargin, y: 765, width: contentWidth, height: 5))

            case .classic:
                UIColor.black.setStroke()
                let outerRect = CGRect(x: 18, y: 18, width: 444, height: 764)
                let innerRect = CGRect(x: 24, y: 24, width: 432, height: 752)
                ctx.cgContext.setLineWidth(2.0)
                ctx.stroke(outerRect)
                ctx.cgContext.setLineWidth(1.0)
                ctx.stroke(innerRect)

            case .tech:
                UIColor.black.setFill()
                ctx.fill(CGRect(x: leftMargin, y: 30, width: contentWidth, height: 60))
                let bannerAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 20, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                company.draw(in: CGRect(x: leftMargin + 10, y: 48, width: contentWidth - 20, height: 26), withAttributes: bannerAttr)
            }

            // Company
            if style != .tech {
                let compAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                company.draw(in: CGRect(x: leftMargin, y: 65, width: contentWidth, height: 28), withAttributes: compAttr)
            }

            // Names
            let nameStartY: CGFloat = (style == .tech) ? 110 : 115
            if !nameZh.isEmpty && !nameEn.isEmpty {
                let zhAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 44, weight: .heavy),
                    .foregroundColor: UIColor.black
                ]
                nameZh.draw(at: CGPoint(x: leftMargin, y: nameStartY), withAttributes: zhAttr)

                let enAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.westernFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
                nameEn.draw(at: CGPoint(x: leftMargin, y: nameStartY + 52), withAttributes: enAttr)
            } else {
                let displayName = nameZh.isEmpty ? nameEn : nameZh
                let nameAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 46, weight: .heavy),
                    .foregroundColor: UIColor.black
                ]
                displayName.draw(in: CGRect(x: leftMargin, y: nameStartY, width: contentWidth, height: 55), withAttributes: nameAttr)
            }

            // Title
            let titleY: CGFloat = nameStartY + 80
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: fontFamily.westernFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            title.draw(in: CGRect(x: leftMargin, y: titleY, width: contentWidth, height: 26), withAttributes: titleAttr)

            // Divider
            UIColor.black.setFill()
            ctx.fill(CGRect(x: leftMargin, y: titleY + 32, width: contentWidth, height: 2))

            // Contact
            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: fontFamily.westernFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            var contactLines: [String] = []
            if !phone.isEmpty { contactLines.append("TEL:  \(phone)") }
            if !email.isEmpty { contactLines.append("MAIL: \(email)") }
            if !note.isEmpty { contactLines.append("NOTE: \(note)") }
            let contactText = contactLines.joined(separator: "\n")
            contactText.draw(in: CGRect(x: leftMargin, y: titleY + 44, width: contentWidth, height: 110), withAttributes: bodyAttr)

            // Optional QR Code
            if includeQR {
                let qrPayloadStr = (qrPayload?.isEmpty == false) ? qrPayload! : buildVCard(
                    nameZh: nameZh,
                    nameEn: nameEn,
                    company: company,
                    title: title,
                    phone: phone,
                    email: email,
                    note: note
                )

                let qrSize: CGFloat = 200
                let qrRect = CGRect(x: (480 - qrSize) / 2.0, y: 470, width: qrSize, height: qrSize)

                if let qrImage = createQRCodeImage(from: qrPayloadStr, size: qrSize) {
                    qrImage.draw(in: qrRect)

                    UIColor.black.setStroke()
                    ctx.cgContext.setLineWidth(1.5)
                    ctx.stroke(qrRect.insetBy(dx: -4, dy: -4))

                    let tipAttr: [NSAttributedString.Key: Any] = [
                        .font: fontFamily.font(ofSize: 13, weight: .bold),
                        .foregroundColor: UIColor.black
                    ]
                    let tipText = "掃描名片通訊錄"
                    let tipWidth = (tipText as NSString).size(withAttributes: tipAttr).width
                    tipText.draw(at: CGPoint(x: qrRect.midX - tipWidth / 2.0, y: qrRect.maxY + 12), withAttributes: tipAttr)
                }
            }
        }
    }

    private static func buildVCard(
        nameZh: String,
        nameEn: String,
        company: String,
        title: String,
        phone: String,
        email: String,
        note: String
    ) -> String {
        let fullName = [nameZh, nameEn].filter { !$0.isEmpty }.joined(separator: " ")
        var lines: [String] = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "FN:\(fullName)",
            "N:\(nameZh);\(nameEn);;;"
        ]
        if !company.isEmpty { lines.append("ORG:\(company)") }
        if !title.isEmpty { lines.append("TITLE:\(title)") }
        if !phone.isEmpty { lines.append("TEL:\(phone)") }
        if !email.isEmpty { lines.append("EMAIL:\(email)") }
        if !note.isEmpty { lines.append("NOTE:\(note)") }
        lines.append("END:VCARD")
        return lines.joined(separator: "\n")
    }

    // MARK: - Memo Generator (Supports Multiple Styles and Font Families)

    static func generateMemo(
        title: String,
        content: String,
        date: String,
        style: MemoStyle = .banner,
        fontFamily: AppFontFamily = .sansSerif
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.setAllowsFontSmoothing(true)
            cg.setShouldSmoothFonts(true)

            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            switch style {
            case .banner:
                UIColor.black.setFill()
                ctx.fill(CGRect(x: 40, y: 35, width: 720, height: 6))

                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 42, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                title.draw(in: CGRect(x: 45, y: 55, width: 710, height: 55), withAttributes: titleAttr)

                ctx.fill(CGRect(x: 40, y: 120, width: 720, height: 3))

                let bodyAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 28, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                content.draw(in: CGRect(x: 45, y: 140, width: 710, height: 250), withAttributes: bodyAttr)

                let dateAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.westernFont(ofSize: 20, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
                date.draw(in: CGRect(x: 45, y: 405, width: 710, height: 30), withAttributes: dateAttr)

                ctx.fill(CGRect(x: 40, y: 445, width: 720, height: 3))

            case .checklist:
                UIColor.black.setFill()
                ctx.fill(CGRect(x: 40, y: 30, width: 720, height: 50))
                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 28, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                ("✓ " + title).draw(in: CGRect(x: 55, y: 40, width: 690, height: 35), withAttributes: titleAttr)

                let items = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                var currentY: CGFloat = 100
                let itemAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 26, weight: .medium),
                    .foregroundColor: UIColor.black
                ]
                for item in items.prefix(6) {
                    ctx.stroke(CGRect(x: 45, y: currentY + 3, width: 22, height: 22))
                    let clean = item.replacingOccurrences(of: #"^\d+[\.\、]\s*"#, with: "", options: .regularExpression)
                    clean.draw(in: CGRect(x: 80, y: currentY, width: 670, height: 38), withAttributes: itemAttr)
                    currentY += 46
                }

                let dateAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.westernFont(ofSize: 20, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
                date.draw(in: CGRect(x: 45, y: 425, width: 710, height: 30), withAttributes: dateAttr)

            case .frame:
                UIColor.black.setStroke()
                ctx.cgContext.setLineWidth(2.0)
                ctx.stroke(CGRect(x: 25, y: 20, width: 750, height: 440))

                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 36, weight: .heavy),
                    .foregroundColor: UIColor.black
                ]
                title.draw(in: CGRect(x: 45, y: 45, width: 710, height: 48), withAttributes: titleAttr)

                UIColor.black.setFill()
                ctx.fill(CGRect(x: 45, y: 100, width: 710, height: 2))

                let bodyAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 26, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                content.draw(in: CGRect(x: 45, y: 120, width: 710, height: 270), withAttributes: bodyAttr)

                let dateAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.westernFont(ofSize: 20, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                date.draw(in: CGRect(x: 45, y: 410, width: 710, height: 30), withAttributes: dateAttr)
            }
        }
    }

    // MARK: - QR Code Generator (Supports Multiple Styles and Font Families)

    static func generateQRCode(
        text: String,
        title: String,
        subtitle: String,
        style: QRStyle = .sideBySide,
        fontFamily: AppFontFamily = .sansSerif
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.setAllowsFontSmoothing(true)
            cg.setShouldSmoothFonts(true)

            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            switch style {
            case .sideBySide:
                let qrSize: CGFloat = 380
                let qrRect = CGRect(x: 50, y: (height - Int(qrSize)) / 2, width: Int(qrSize), height: Int(qrSize))

                if let qrImg = createQRCodeImage(from: text, size: qrSize) {
                    qrImg.draw(in: qrRect)
                }

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byWordWrapping
                paragraphStyle.alignment = .left

                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 32, weight: .bold),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraphStyle
                ]
                title.draw(in: CGRect(x: 460, y: 90, width: 290, height: 140), withAttributes: titleAttr)

                let subAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 24, weight: .regular),
                    .foregroundColor: UIColor.darkGray,
                    .paragraphStyle: paragraphStyle
                ]
                subtitle.draw(in: CGRect(x: 460, y: 240, width: 290, height: 160), withAttributes: subAttr)

            case .centered:
                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 32, weight: .heavy),
                    .foregroundColor: UIColor.black
                ]
                let tWidth = (title as NSString).size(withAttributes: titleAttr).width
                title.draw(at: CGPoint(x: (CGFloat(width) - tWidth) / 2.0, y: 25), withAttributes: titleAttr)

                let qrSize: CGFloat = 320
                let qrRect = CGRect(x: (CGFloat(width) - qrSize) / 2.0, y: 75, width: qrSize, height: qrSize)
                if let qrImg = createQRCodeImage(from: text, size: qrSize) {
                    qrImg.draw(in: qrRect)
                }

                let subAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 22, weight: .medium),
                    .foregroundColor: UIColor.darkGray
                ]
                let sWidth = (subtitle as NSString).size(withAttributes: subAttr).width
                subtitle.draw(at: CGPoint(x: (CGFloat(width) - sWidth) / 2.0, y: 415), withAttributes: subAttr)

            case .techBadge:
                UIColor.black.setFill()
                ctx.fill(CGRect(x: 30, y: 20, width: 740, height: 60))
                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 26, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                title.draw(in: CGRect(x: 50, y: 35, width: 700, height: 35), withAttributes: titleAttr)

                let qrSize: CGFloat = 330
                let qrRect = CGRect(x: 50, y: 110, width: qrSize, height: qrSize)
                if let qrImg = createQRCodeImage(from: text, size: qrSize) {
                    qrImg.draw(in: qrRect)
                }

                UIColor.black.setStroke()
                ctx.cgContext.setLineWidth(2.0)
                ctx.stroke(qrRect.insetBy(dx: -5, dy: -5))

                let subAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.font(ofSize: 22, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                subtitle.draw(in: CGRect(x: 420, y: 140, width: 340, height: 180), withAttributes: subAttr)

                let urlAttr: [NSAttributedString.Key: Any] = [
                    .font: fontFamily.westernFont(ofSize: 18, weight: .medium),
                    .foregroundColor: UIColor.darkGray
                ]
                text.draw(in: CGRect(x: 420, y: 340, width: 340, height: 90), withAttributes: urlAttr)
            }
        }
    }

    // MARK: - Diagnostic Test Patterns

    static func testPatternBorderGrid() -> Data {
        var data = Data(repeating: 0xff, count: byteCount)
        let bytesPerRow = width / 8
        for y in 0..<height {
            for bx in 0..<bytesPerRow {
                let x = bx * 8
                if y < 4 || y >= height - 4 || x < 8 || x >= width - 8 {
                    data[y * bytesPerRow + bx] = 0x00
                } else if abs(y - height / 2) < 2 || abs(x - width / 2) < 4 {
                    data[y * bytesPerRow + bx] = 0x00
                } else if y % 80 == 0 || x % 100 == 0 {
                    data[y * bytesPerRow + bx] = 0x00
                }
            }
        }
        return data
    }

    static func testPatternCheckerboard() -> Data {
        var data = Data(repeating: 0xff, count: byteCount)
        let bytesPerRow = width / 8
        for y in 0..<height {
            for bx in 0..<bytesPerRow {
                let x = bx * 8
                if ((x / 40) + (y / 40)) % 2 == 0 {
                    data[y * bytesPerRow + bx] = 0xaa
                }
            }
        }
        return data
    }

    static func testPatternResolution() -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            UIColor.black.setFill()
            ctx.fill(CGRect(x: 20, y: 20, width: 760, height: 4))
            ctx.fill(CGRect(x: 20, y: 456, width: 760, height: 4))

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            "7.5\" (800x480) 電子紙測試校準".draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttr)

            let sizes: [CGFloat] = [12, 16, 20, 24, 30, 38]
            var currentY: CGFloat = 100
            for sz in sizes {
                let attr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: sz, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                "字體 \(Int(sz))pt: The quick brown fox jumps over the lazy dog. 1234567890".draw(
                    at: CGPoint(x: 40, y: currentY),
                    withAttributes: attr
                )
                currentY += sz + 14
            }
        }
    }
}
