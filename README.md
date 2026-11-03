# MIT 台灣智造 7.5" NFC 電子紙系統 (EpaperBridge)

本專案為 **MIT 台灣智造 (Mobile Intelligence Technology)** 7.5 吋無源 NFC 電子紙（800 × 480，1-bit 黑白點陣）之完整軟硬體橋接與手機獨立創作系統。

透過 **Mac / PC 桌面端 (Python)** 與 **iOS 原生 App (SwiftUI + CoreNFC)**，實現電腦端透過 BLE/區域網路高速傳圖，以及 iPhone 端免電腦直接進行名片、備忘告示、QR 碼看板與相片排版，並透過 NFC 為無源電子紙進行高速感應刷屏。

---

## 📱 App 功能亮點與架構

### 1. 手機獨立創作工坊（免電腦隨身使用）
- **相簿選圖與雙照並排**：
  - 支援單張全版（800 × 480）或雙照並排（各 400 × 480），具備左右對稱控制列，獨立選圖並支援 90° / 180° / 270° 旋轉。
  - 整合 Floyd-Steinberg 誤差擴散抖色（Dithering）演算法，在 1-bit 黑白螢幕上逼真呈現相片灰階過渡。
- **個人商務名片**：
  - 支援**中文姓名與英文姓名雙欄位**，層次分明。
  - 支援**橫式排版**與專為電子紙直立擺放設計的**直式排版**（自動 90° 旋轉適配）。
  - 可自由開關**名片專屬 QR Code**（自動將姓名、電話、Email、公司等聯絡資訊封裝為標準 **vCard**，掃描直接新增聯絡人）。
- **多風格備忘錄與 QR 碼看板**：
  - 備忘錄提供「標準告示」、「代辦清單」與「極簡便籤」三種排版風格。
  - QR 碼看板提供「左圖右文」、「置中大圖」與「科技看板」風格，預設導向 `https://mit.com.tw/`。
- **歷史紀錄儲存與「帶入」回填**：
  - 名片、備忘、QR 碼皆支援本地即時儲存。
  - 表單下方即時列出過去儲存清單，點選**【帶入】**按鈕即可秒速回填欄位並重新產生預覽。
- **iOS 原生手勢與鍵盤體驗**：
  - 碰觸輸入格以外的任何區域或滑動頁面，立即自動收起鍵盤。

### 2. 字體引擎與平滑防鋸齒（Smooth Anti-Aliasing）
- **真機原生 CJK 漢字字型庫**：
  - **黑體**（蘋方 PingFang TC + Avenir Next）：現代剛勁、飽滿俐落。
  - **明體**（柊野明朝體 HiraMinProN + Georgia）：正宗繁體漢字明體，具備端莊橫細豎粗與古典三角襯線。
  - **圓體**（柊野圓體 HiraMaruProN + Arial Rounded）：全字型轉角圓潤無銳角，親和手作感。
  - **等寬**（Menlo / Courier New）：終端機工程代碼感，數字與符號嚴格等寬對齊。
- **平滑描邊二值化演算法**：
  - 解決黑白電子紙傳統硬切二值化造成的文字階梯直角（狗牙鋸齒）問題。
  - 鎖定純淨白底與實心黑體核心，僅在筆劃邊緣進行微米級子像素過渡平滑處理，呈現如高級印刷品般的平滑曲線。
- **製作結果預覽即時切換**：
  - 預覽卡片整合快速切換列，直觀點擊即可即時變更版向、字體、排版風格與平滑描邊，即看即所得。

### 3. 主控台與 NFC 高速感應傳輸
- **BLE Handoff + LAN 下載**：電腦端選圖後，透過低功耗藍牙傳遞交接資訊，由 iPhone 經區域網路秒速抓取點陣圖。
- **NFC 無源供電最佳化**：
  - 採用 25+ 次射頻預熱，建立穩定諧振電壓。
  - 400 個 120-byte 傳輸分塊以 5~6 ms 高速脈衝發送。
  - 刷屏階段維持 6 ms 連續輪詢直到接收 `FF 00` ACK，確保提供充足物理能量完成黑白粒子反轉，杜絕殘影與反白凍結。
  - 整合 `AudioToolbox` 系統級實體觸覺震動引導。

### 4. 測試與診斷
- **對位訊號強度即時檢測**：靠近電子紙即可檢測 NFC 耦合百分比並觸發震動反饋，無須等待傳圖。
- **內建診斷校準圖**：邊界網格校正圖、50% 棋盤格棋盤圖、階梯字體解析度圖。

---

## 🎨 專屬 App 圖示 (App Icon)

已配置標準 1024 × 1024 像素的 iOS App 圖示（位於 `ios/EpaperBridge/Assets.xcassets/AppIcon.appiconset`）：
- **視覺意象**：消光曜石黑底座 + 7.5" 紙白水墨電子紙螢幕 + NFC 電光藍射頻波紋。
- 符合 Apple iOS 人機介面設計準則（HIG），大氣俐落且具備高辨識度。

---

## 🛠️ 開發與建置說明

### 系統環境
- **硬體平台**：Apple Mac mini (Apple Silicon M2 Pro) / iPhone 16e (實機 iOS 18+)
- **開發工具**：Xcode 27.2、XcodeGen、Python 3.14 (虛擬環境 `.venv`)
- **簽章憑證**：Apple Developer Team (MobileIT)，Bundle ID `com.mit.EpaperBridge`
- **權限設定**：已啟用 `com.apple.developer.nfc.readersession.formats = [TAG]`

### 建置與部署指令

1. **編譯 iOS App 並自動簽章**：
   ```bash
   ./scripts/build-ios-mac.command
   ```

2. **安裝並啟動至連接的 iPhone**：
   ```bash
   xcrun devicectl device install app --device <YOUR_DEVICE_UDID> ios/build/Build/Products/Debug-iphoneos/EpaperBridge.app
   xcrun devicectl device process launch --device <YOUR_DEVICE_UDID> --terminate-existing com.mit.EpaperBridge
   ```

3. **執行桌面端 Python 單元測試**：
   ```bash
   .venv/bin/python -m unittest discover -s desktop -v
   ```

4. **啟動桌面端傳圖程式**：
   ```bash
   ./scripts/start-mac.command
   ```

---

## 📁 專案目錄結構

```text
.
├── desktop/                # 電腦端 Python 橋接程式 (BLE + LAN 傳輸、800x480 二值化)
├── ios/                    # iOS 原生 SwiftUI 專案
│   ├── EpaperBridge/       # 原始碼目錄
│   │   ├── Assets.xcassets # App 圖示與靜態資源 (含 1024x1024 AppIcon)
│   │   ├── BLEReceiver.swift      # 電腦端 BLE 連線與交接接收
│   │   ├── DashboardView.swift    # 主控台分頁 (儀表、預覽、NFC 寫入)
│   │   ├── DiagnosticsView.swift  # 診斷分頁 (對位訊號測試、校準圖)
│   │   ├── EpaperBridgeApp.swift  # App 主入口與生命週期
│   │   ├── Frame.swift            # 800x480 點陣緩衝區處理與預覽
│   │   ├── ImageProcessor.swift   # 影像抖色、平滑防鋸齒、多字體名片/備忘/QR 引擎
│   │   ├── LANFetcher.swift       # 區域網路 HTTP 圖檔高速下載
│   │   ├── NFCWriter.swift        # CoreNFC 驅動 (預熱、分包、刷屏輪詢、震動)
│   │   ├── StudioView.swift       # 手機創作工坊 (相簿、名片、備忘、QR 碼、範本)
│   │   └── TemplateStore.swift    # 本地範本儲存與歷史資料模型
│   └── project.yml         # XcodeGen 專案產生描述檔
├── docs/                   # 硬體辨識、通訊協定與系統規格文件
├── samples/                # 800x480 範例圖片
└── scripts/                # 自動化建置、安裝與執行腳本
```

---

## 🏢 品牌與版權

- **品牌設定**：MIT 台灣智造 (Mobile Intelligence Technology)
- **官方網站**：[https://mit.com.tw/](https://mit.com.tw/)
