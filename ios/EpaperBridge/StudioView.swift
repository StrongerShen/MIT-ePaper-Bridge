import PhotosUI
import SwiftUI

struct StudioView: View {
    @ObservedObject var receiver: BLEReceiver
    @ObservedObject var templateStore: TemplateStore
    @Binding var selectedTab: Int

    @State private var studioMode = 0 // 0: 相簿選圖, 1: 個人名片, 2: 備忘告示, 3: QR Code, 4: 常用範本庫

    // Typography Settings
    @State private var currentFontFamily: AppFontFamily = .sansSerif
    @State private var smoothText = true // Smooth Anti-Aliasing (eliminates jaggies)

    // Photo Mode: Single (0) vs Dual Side-by-Side (1)
    @State private var photoLayout = 0
    @State private var useDithering = true

    // Single Photo
    @State private var singlePhotoItem: PhotosPickerItem?
    @State private var rawSingleImage: UIImage?
    @State private var singleRotation = 0

    // Dual Photos
    @State private var leftPhotoItem: PhotosPickerItem?
    @State private var rawLeftImage: UIImage?
    @State private var leftRotation = 0

    @State private var rightPhotoItem: PhotosPickerItem?
    @State private var rawRightImage: UIImage?
    @State private var rightRotation = 0

    // Business Card fields
    @State private var cardNameZh = "陳智造"
    @State private var cardNameEn = "Alex Chen"
    @State private var cardTitle = "Tech Lead & Architect"
    @State private var cardCompany = "Mobile Intelligence Technology"
    @State private var cardPhone = "+886 2-1234-5678"
    @State private var cardEmail = "contact@mit.com.tw"
    @State private var cardNote = "MIT 7.5\" e-Paper"
    @State private var cardOrientation: CardOrientation = .horizontal
    @State private var cardStyle: CardStyle = .modern
    @State private var cardIncludeQR = true

    // Memo fields
    @State private var memoTitle = "會議重點通知"
    @State private var memoContent = "1. 電子紙展示系統上線驗收\n2. NFC 感應更新流暢度最佳化\n3. 專案架構文件同步存檔"
    @State private var memoDate = "2026-11-03 · 台北"
    @State private var memoStyle: MemoStyle = .banner

    // QR Code fields (MIT Taiwan defaults)
    @State private var qrText = "https://mit.com.tw/"
    @State private var qrTitle = "Mobile Intelligence Technology."
    @State private var qrSubtitle = "掃描造訪 MIT 台灣智造"
    @State private var qrStyle: QRStyle = .sideBySide

    @State private var previewFrame: Data?
    @State private var previewImage: UIImage?
    @State private var showSaveAlert = false
    @State private var savePresetTitle = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Segmented Control
                Picker("創作工具", selection: $studioMode) {
                    Text("相簿").tag(0)
                    Text("名片").tag(1)
                    Text("備忘").tag(2)
                    Text("QR碼").tag(3)
                    Text("範本庫").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if studioMode == 0 {
                    photoSection
                } else if studioMode == 1 {
                    cardSection
                } else if studioMode == 2 {
                    memoSection
                } else if studioMode == 3 {
                    qrSection
                } else {
                    librarySection
                }

                // Studio Live Preview Card (if mode 0..3)
                if studioMode != 4 {
                    previewSection
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            TapGesture().onEnded {
                hideKeyboard()
            }
        )
        .navigationTitle("手機獨立創作")
        .alert("儲存至常用範本庫", isPresented: $showSaveAlert) {
            TextField("範本名稱", text: $savePresetTitle)
            Button("儲存") {
                if let previewFrame {
                    let cat: TemplateItem.Category = studioMode == 0 ? .photo : (studioMode == 1 ? .card : (studioMode == 2 ? .memo : .qrcode))
                    templateStore.save(title: savePresetTitle, subtitle: "自訂創作範本", category: cat, frame: previewFrame)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: singlePhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImg = UIImage(data: data) {
                    rawSingleImage = uiImg
                    updatePhotoPreview()
                }
            }
        }
        .onChange(of: leftPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImg = UIImage(data: data) {
                    rawLeftImage = uiImg
                    updatePhotoPreview()
                }
            }
        }
        .onChange(of: rightPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImg = UIImage(data: data) {
                    rawRightImage = uiImg
                    updatePhotoPreview()
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Preview Section (Allows switching layouts, fonts, and smoothing directly in preview)
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("製作結果預覽", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text("800 × 480 點陣")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Interactive Layout Switcher inside Preview
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                    Text("更換預覽排版與字體樣式")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if studioMode == 1 || studioMode == 2 || studioMode == 3 {
                    // Font Family Switcher
                    HStack(spacing: 8) {
                        Text("字體")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Picker("字體風格", selection: $currentFontFamily) {
                            ForEach(AppFontFamily.allCases, id: \.self) { font in
                                Text(font.rawValue).tag(font)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: currentFontFamily) { _ in regenerateCurrentMode() }
                    }

                    // Smooth Anti-Aliasing Toggle
                    HStack(spacing: 8) {
                        Text("邊緣")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Picker("文字邊緣處理", selection: $smoothText) {
                            Text("平滑描邊 (無鋸齒)").tag(true)
                            Text("傳統純硬邊").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: smoothText) { _ in regenerateCurrentMode() }
                    }
                }

                if studioMode == 1 {
                    // Card Layout Quick Switcher
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text("版向")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Picker("名片版向", selection: $cardOrientation) {
                                ForEach(CardOrientation.allCases, id: \.self) { ori in
                                    Text(ori.rawValue).tag(ori)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: cardOrientation) { _ in generateCardPreview() }
                        }

                        HStack(spacing: 8) {
                            Text("風格")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Picker("名片風格", selection: $cardStyle) {
                                ForEach(CardStyle.allCases, id: \.self) { sty in
                                    Text(sty.rawValue).tag(sty)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: cardStyle) { _ in generateCardPreview() }
                        }

                        HStack(spacing: 8) {
                            Text("QR碼")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Picker("附加QR碼", selection: $cardIncludeQR) {
                                Text("附加名片 QR 碼").tag(true)
                                Text("純文字無 QR 碼").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: cardIncludeQR) { _ in generateCardPreview() }
                        }
                    }
                } else if studioMode == 2 {
                    // Memo Layout Quick Switcher
                    HStack(spacing: 8) {
                        Text("風格")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Picker("備忘風格", selection: $memoStyle) {
                            ForEach(MemoStyle.allCases, id: \.self) { sty in
                                Text(sty.rawValue).tag(sty)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: memoStyle) { _ in generateMemoPreview() }
                    }
                } else if studioMode == 3 {
                    // QR Code Layout Quick Switcher
                    HStack(spacing: 8) {
                        Text("風格")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Picker("QR風格", selection: $qrStyle) {
                            ForEach(QRStyle.allCases, id: \.self) { sty in
                                Text(sty.rawValue).tag(sty)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: qrStyle) { _ in generateQRPreview() }
                    }
                } else if studioMode == 0 {
                    // Photo Layout Quick Switcher
                    HStack(spacing: 8) {
                        Text("排版")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Picker("照片排版", selection: $photoLayout) {
                            Text("單張全版").tag(0)
                            Text("雙照並排").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: photoLayout) { _ in updatePhotoPreview() }
                    }
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(10)

            if let previewImage {
                Image(uiImage: previewImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)

                VStack(spacing: 8) {
                    Button {
                        applyCurrentToBridge()
                    } label: {
                        Label("套用至主控台更新", systemImage: "arrow.up.circle.fill")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        savePresetTitle = defaultSaveTitle()
                        showSaveAlert = true
                    } label: {
                        Label("收藏至常用範本庫", systemImage: "bookmark.fill")
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("請點選下方產生按鈕預覽排版")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private func regenerateCurrentMode() {
        if studioMode == 1 {
            generateCardPreview()
        } else if studioMode == 2 {
            generateMemoPreview()
        } else if studioMode == 3 {
            generateQRPreview()
        }
    }

    // MARK: - Photo Section (Supports Rotation & Dual Side-by-Side)
    private var photoSection: some View {
        VStack(spacing: 14) {
            Picker("照片排版", selection: $photoLayout) {
                Text("單張全版").tag(0)
                Text("雙照並排 (400×480)").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: photoLayout) { _ in
                updatePhotoPreview()
            }

            if photoLayout == 0 {
                // Single Photo Mode
                HStack(spacing: 12) {
                    PhotosPicker(selection: $singlePhotoItem, matching: .images) {
                        Label(rawSingleImage == nil ? "挑選相片" : "重選相片", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        singleRotation = (singleRotation + 90) % 360
                        updatePhotoPreview()
                    } label: {
                        Label("旋轉 90° (\(singleRotation)°)", systemImage: "rotate.right")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(rawSingleImage == nil)
                }
            } else {
                // Dual Photos Mode: Left and Right side-by-side columns
                HStack(alignment: .top, spacing: 12) {
                    // Left Column
                    VStack(spacing: 8) {
                        Text("左側照片")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        PhotosPicker(selection: $leftPhotoItem, matching: .images) {
                            Label(rawLeftImage == nil ? "選左側照片" : "更換左圖", systemImage: "photo.badge.plus")
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            leftRotation = (leftRotation + 90) % 360
                            updatePhotoPreview()
                        } label: {
                            Label("旋轉 \(leftRotation)°", systemImage: "rotate.right")
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .disabled(rawLeftImage == nil)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    // Right Column
                    VStack(spacing: 8) {
                        Text("右側照片")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        PhotosPicker(selection: $rightPhotoItem, matching: .images) {
                            Label(rawRightImage == nil ? "選右側照片" : "更換右圖", systemImage: "photo.badge.plus")
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            rightRotation = (rightRotation + 90) % 360
                            updatePhotoPreview()
                        } label: {
                            Label("旋轉 \(rightRotation)°", systemImage: "rotate.right")
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .disabled(rawRightImage == nil)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
            }

            Toggle("啟用 Floyd-Steinberg 誤差擴散抖色（呈現漸層）", isOn: $useDithering)
                .font(.subheadline)
                .onChange(of: useDithering) { _ in
                    updatePhotoPreview()
                }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private func updatePhotoPreview() {
        let composite: UIImage?
        if photoLayout == 0 {
            guard let raw = rawSingleImage else { return }
            composite = ImageProcessor.rotate(image: raw, by: singleRotation)
        } else {
            let left = rawLeftImage != nil ? ImageProcessor.rotate(image: rawLeftImage!, by: leftRotation) : nil
            let right = rawRightImage != nil ? ImageProcessor.rotate(image: rawRightImage!, by: rightRotation) : nil
            guard left != nil || right != nil else { return }
            composite = ImageProcessor.combineDualPhotos(left: left, right: right)
        }

        guard let composite else { return }
        let frame = useDithering ? ImageProcessor.dither(image: composite) : ImageProcessor.binarize(image: composite)
        previewFrame = frame
        previewImage = Frame.preview(frame)
    }

    // MARK: - Business Card Section (Supports Chinese & English names, Orientation, QR Code, Fonts)
    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Layout Settings in Form
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Picker("版向", selection: $cardOrientation) {
                        ForEach(CardOrientation.allCases, id: \.self) { ori in
                            Text(ori.rawValue).tag(ori)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("風格", selection: $cardStyle) {
                        ForEach(CardStyle.allCases, id: \.self) { sty in
                            Text(sty.rawValue).tag(sty)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(isOn: $cardIncludeQR) {
                    Label("名片附個人聯絡 QR Code", systemImage: "qrcode")
                        .font(.subheadline)
                }
                .onChange(of: cardIncludeQR) { _ in generateCardPreview() }
            }
            .padding(.bottom, 4)

            // Input fields
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("中文姓名", text: $cardNameZh)
                    TextField("英文姓名", text: $cardNameEn)
                }
                TextField("職稱", text: $cardTitle)
                TextField("公司 / 組織", text: $cardCompany)
                TextField("電話", text: $cardPhone)
                TextField("Email", text: $cardEmail)
                TextField("備註 / 網站", text: $cardNote)
            }
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button {
                    generateCardPreview()
                } label: {
                    Label("產生排版", systemImage: "sparkles")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    saveCard()
                } label: {
                    Label("儲存名片", systemImage: "square.and.arrow.down")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            // Saved Cards List
            let savedCards = templateStore.items.filter { $0.category == .card }
            if !savedCards.isEmpty {
                Divider()
                Text("已儲存的名片清單 (點選帶入)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(savedCards) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()

                            Button("帶入") {
                                loadCard(item: item)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                templateStore.delete(item: item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .padding(.leading, 4)
                        }
                        .padding(8)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .onAppear {
            if previewFrame == nil && studioMode == 1 {
                generateCardPreview()
            }
        }
    }

    private func generateCardPreview() {
        hideKeyboard()
        let img = ImageProcessor.generateBusinessCard(
            nameZh: cardNameZh,
            nameEn: cardNameEn,
            title: cardTitle,
            company: cardCompany,
            phone: cardPhone,
            email: cardEmail,
            note: cardNote,
            orientation: cardOrientation,
            style: cardStyle,
            fontFamily: currentFontFamily,
            includeQR: cardIncludeQR
        )
        let frame = smoothText ? ImageProcessor.smoothBinarize(image: img) : ImageProcessor.binarize(image: img, threshold: 140)
        previewFrame = frame
        previewImage = Frame.preview(frame)
    }

    private func saveCard() {
        hideKeyboard()
        generateCardPreview()
        guard let previewFrame else { return }
        let displayName = [cardNameZh, cardNameEn].filter { !$0.isEmpty }.joined(separator: " ")
        let title = displayName.isEmpty ? "個人名片" : "名片：\(displayName)"
        let subtitle = "\(cardOrientation.rawValue) · \(currentFontFamily.rawValue) · \(cardCompany)"
        templateStore.save(
            title: title,
            subtitle: subtitle,
            category: .card,
            frame: previewFrame,
            cardNameZh: cardNameZh,
            cardNameEn: cardNameEn,
            cardIsVertical: cardOrientation == .vertical,
            cardIncludeQR: cardIncludeQR,
            cardStyle: cardStyle.rawValue,
            cardTitle: cardTitle,
            cardCompany: cardCompany,
            cardPhone: cardPhone,
            cardEmail: cardEmail,
            cardNote: cardNote
        )
    }

    private func loadCard(item: TemplateItem) {
        if let zh = item.cardNameZh { cardNameZh = zh }
        else if let name = item.cardName { cardNameZh = name }
        if let en = item.cardNameEn { cardNameEn = en }
        if let isVert = item.cardIsVertical { cardOrientation = isVert ? .vertical : .horizontal }
        if let incQR = item.cardIncludeQR { cardIncludeQR = incQR }
        if let styStr = item.cardStyle, let sty = CardStyle(rawValue: styStr) { cardStyle = sty }
        if let title = item.cardTitle { cardTitle = title }
        if let company = item.cardCompany { cardCompany = company }
        if let phone = item.cardPhone { cardPhone = phone }
        if let email = item.cardEmail { cardEmail = email }
        if let note = item.cardNote { cardNote = note }
        generateCardPreview()
    }

    // MARK: - Memo Section
    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("備忘排版風格", selection: $memoStyle) {
                ForEach(MemoStyle.allCases, id: \.self) { sty in
                    Text(sty.rawValue).tag(sty)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: memoStyle) { _ in generateMemoPreview() }

            VStack(spacing: 8) {
                TextField("備忘標題", text: $memoTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $memoContent)
                    .frame(minHeight: 100)
                    .padding(4)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                TextField("日期 / 簽名", text: $memoDate)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button {
                    generateMemoPreview()
                } label: {
                    Label("產生告示", systemImage: "square.and.pencil")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    saveMemo()
                } label: {
                    Label("儲存備忘", systemImage: "square.and.arrow.down")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            // Saved Memos List
            let savedMemos = templateStore.items.filter { $0.category == .memo }
            if !savedMemos.isEmpty {
                Divider()
                Text("已儲存的備忘清單 (點選帶入)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(savedMemos) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()

                            Button("帶入") {
                                loadMemo(item: item)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                templateStore.delete(item: item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .padding(.leading, 4)
                        }
                        .padding(8)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .onAppear {
            if previewFrame == nil && studioMode == 2 {
                generateMemoPreview()
            }
        }
    }

    private func generateMemoPreview() {
        hideKeyboard()
        let img = ImageProcessor.generateMemo(
            title: memoTitle,
            content: memoContent,
            date: memoDate,
            style: memoStyle,
            fontFamily: currentFontFamily
        )
        let frame = smoothText ? ImageProcessor.smoothBinarize(image: img) : ImageProcessor.binarize(image: img, threshold: 140)
        previewFrame = frame
        previewImage = Frame.preview(frame)
    }

    private func saveMemo() {
        hideKeyboard()
        generateMemoPreview()
        guard let previewFrame else { return }
        let title = memoTitle.isEmpty ? "備忘錄" : "備忘：\(memoTitle)"
        let subtitle = "\(memoStyle.rawValue) · \(currentFontFamily.rawValue) · \(memoDate.isEmpty ? "重點告示" : memoDate)"
        templateStore.save(
            title: title,
            subtitle: subtitle,
            category: .memo,
            frame: previewFrame,
            memoTitle: memoTitle,
            memoContent: memoContent,
            memoDate: memoDate,
            memoStyle: memoStyle.rawValue
        )
    }

    private func loadMemo(item: TemplateItem) {
        if let title = item.memoTitle { memoTitle = title }
        if let content = item.memoContent { memoContent = content }
        if let date = item.memoDate { memoDate = date }
        if let styStr = item.memoStyle, let sty = MemoStyle(rawValue: styStr) { memoStyle = sty }
        generateMemoPreview()
    }

    // MARK: - QR Code Section (MIT Taiwan Defaults & Multi-style)
    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("QR 碼排版風格", selection: $qrStyle) {
                ForEach(QRStyle.allCases, id: \.self) { sty in
                    Text(sty.rawValue).tag(sty)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: qrStyle) { _ in generateQRPreview() }

            VStack(spacing: 8) {
                TextField("網址、Wi-Fi 或文字內容", text: $qrText)
                TextField("主標題說明", text: $qrTitle)
                TextField("副標題說明", text: $qrSubtitle)
            }
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button {
                    generateQRPreview()
                } label: {
                    Label("產生看板", systemImage: "qrcode")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    saveQRCode()
                } label: {
                    Label("儲存 QR 碼", systemImage: "square.and.arrow.down")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            // Saved QR Codes List
            let savedQRs = templateStore.items.filter { $0.category == .qrcode }
            if !savedQRs.isEmpty {
                Divider()
                Text("已儲存的 QR 碼清單 (點選帶入)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(savedQRs) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()

                            Button("帶入") {
                                loadQRCode(item: item)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                templateStore.delete(item: item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .padding(.leading, 4)
                        }
                        .padding(8)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .onAppear {
            if previewFrame == nil && studioMode == 3 {
                generateQRPreview()
            }
        }
    }

    private func generateQRPreview() {
        hideKeyboard()
        let img = ImageProcessor.generateQRCode(
            text: qrText,
            title: qrTitle,
            subtitle: qrSubtitle,
            style: qrStyle,
            fontFamily: currentFontFamily
        )
        let frame = smoothText ? ImageProcessor.smoothBinarize(image: img) : ImageProcessor.binarize(image: img, threshold: 140)
        previewFrame = frame
        previewImage = Frame.preview(frame)
    }

    private func saveQRCode() {
        hideKeyboard()
        generateQRPreview()
        guard let previewFrame else { return }
        let title = qrTitle.isEmpty ? "QR Code" : "QR：\(qrTitle)"
        let subtitle = "\(qrStyle.rawValue) · \(currentFontFamily.rawValue) · \(qrSubtitle.isEmpty ? qrText : qrSubtitle)"
        templateStore.save(
            title: title,
            subtitle: subtitle,
            category: .qrcode,
            frame: previewFrame,
            qrText: qrText,
            qrTitle: qrTitle,
            qrSubtitle: qrSubtitle,
            qrStyle: qrStyle.rawValue
        )
    }

    private func loadQRCode(item: TemplateItem) {
        if let text = item.qrText { qrText = text }
        if let title = item.qrTitle { qrTitle = title }
        if let subtitle = item.qrSubtitle { qrSubtitle = subtitle }
        if let styStr = item.qrStyle, let sty = QRStyle(rawValue: styStr) { qrStyle = sty }
        generateQRPreview()
    }

    // MARK: - Library Section
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已儲存的常用範本")
                .font(.headline)
                .padding(.horizontal)

            if templateStore.items.isEmpty {
                Text("尚未儲存範本，可在製作名片、備忘錄後點擊「收藏此範本」。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(templateStore.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.category.iconName)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.bold())
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("套用") {
                            if let frame = templateStore.loadFrame(for: item) {
                                receiver.frame = frame
                                receiver.image = Frame.preview(frame)
                                selectedTab = 0 // jump to Dashboard
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
    }

    private func applyCurrentToBridge() {
        guard let previewFrame else { return }
        receiver.frame = previewFrame
        receiver.image = previewImage
        selectedTab = 0
    }

    private func defaultSaveTitle() -> String {
        switch studioMode {
        case 0: return photoLayout == 0 ? "相簿照片" : "並排雙照"
        case 1:
            let name = [cardNameZh, cardNameEn].filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? "個人名片" : "名片：\(name)"
        case 2: return "備忘：\(memoTitle)"
        case 3: return "QR碼：\(qrTitle)"
        default: return "自訂作品"
        }
    }
}
