# 開發與操作

本專案已完成端到端實機驗證（Mac 電腦選圖 ➔ BLE 交接 ➔ 區域網路傳圖 ➔ iPhone 預覽 ➔ NFC 刷新 Waveshare 7.5 吋電子紙）。電腦端提供 Tk 視窗與 CLI，iOS 提供 XcodeGen 管理的原生專案，已在 Mac mini 的 Xcode 27.2 完成編譯、MobileIT 簽章（含 NFC TAG entitlement），並成功部署至 iPhone 16e。

## 電腦端

在專案根目錄執行：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r desktop/requirements.txt
.venv/bin/python desktop/app.py
```

視窗依序操作：選擇圖片、搜尋 iPhone、選取裝置、傳送圖片。預設勾選「BLE 連線後使用區域網路快速傳圖」；電腦與 iPhone 必須在彼此可連線的同一區域網路。取消勾選可改用純 BLE。多網路介面時可在電腦 IP 欄指定手機可連到的位址。iPhone 須先開啟專用 App 的「接收電腦圖片」並保持前景。電腦顯示完整接收後，再在 iPhone 按「更新電子紙」。

Ubuntu 若缺少 tkinter，需安裝系統的 `python3-tk`，或先使用 CLI。系統亦需有可用的 BLE 藍牙介面與 BlueZ 服務。這是 BLE GATT 連線，不是傳統藍牙檔案分享。

```bash
# 只轉圖，不需要藍牙或手機
.venv/bin/python desktop/bridge.py prepare /path/to/image.png

# 搜尋專用 iPhone App；既有 NFC E-Tag 不會出現在此服務
.venv/bin/python desktop/bridge.py scan

# 預設 BLE 交接、區域網路下載；多台接收端可用 --address 指定
.venv/bin/python desktop/bridge.py send /path/to/image.png

# 多網路介面時，明確指定電腦的區域網路 IP
.venv/bin/python desktop/bridge.py send /path/to/image.png --host 192.168.1.20

# 沒有共同網路，或想測試純 BLE 備用模式
.venv/bin/python desktop/bridge.py send /path/to/image.png --transport ble

# 滿版裁切，停用抖色，改為直接黑白二值化
.venv/bin/python desktop/bridge.py prepare /path/to/image.png --fit cover --threshold
```

預設輸出到 `output/`：`preview-gray.png` 是灰階中間檔，`preview.png` 是實際傳送點陣預覽；CLI 另輸出 `frame.bin`。重跑會更新同名輸出。

## iOS 專案

使用者已確認有 Mac mini、Xcode 與開發者帳號，可安裝至手機。需要實體且支援 NFC 的 iPhone，以及可啟用 NFC Tag Reading capability 的簽章設定。本機 Ubuntu 無法產生可直接安裝的已簽章 iOS App。

1. 將專案放到 Mac，安裝 XcodeGen（如使用 Homebrew：`brew install xcodegen`）。
2. 在 `ios/` 執行 `xcodegen generate`，開啟生成的 `EpaperBridge.xcodeproj`。
3. 在 Signing & Capabilities 使用已設定的 MobileIT Team 與本專案 Bundle Identifier，確認 Near Field Communication Tag Reading capability 與 `TAG` entitlement。
4. 選擇實體 iPhone，編譯並安裝。若帳號或 provisioning profile 不支援 NFC capability，必須先解決簽章，不能藉由移除 entitlement 當作完成。
5. 開啟 App，允許藍牙，按「接收電腦圖片」，保持前景。首次快速傳圖時也需允許區域網路存取。完整收妥後確認預覽，按「更新電子紙」，將手機頂端貼近電子紙感應區。

App 保存最後完整接收的圖片；失敗或不完整的新傳輸不替換舊圖。進入背景會停止接收，返回後重新按接收。NFC 部分目前只實作一般 7.5 吋舊版協定，若回報標籤類型不符或初始化回應錯誤，應記錄錯誤與硬體版本，再開發對應協定。

## 驗證狀態

```bash
python3 -m unittest discover -s desktop -v
```

已通過十一項自動檢查：原有圖片與 BLE 封包檢查，加上 BLE 交接後的實際 loopback HTTP 下載、錯誤路徑拒絕、下載損毀拒絕、逾時關閉服務與非區域網路位址拒絕。BLE 接收端仍是模擬模型，不代表 CoreBluetooth、URLSession 或實機 Wi-Fi 已測試。測試需要允許本機 loopback socket。

iOS plist 與 XcodeGen YAML 已作格式解析，電腦端依賴已安裝於專案 `.venv`，800 × 480 測試圖已完成實際轉換與預覽檢視，見 `output/test-ready/preview.png`。已透過 SSH 在 Mac mini 完成 Xcode 27.2 編譯，含 BLE、區域網路下載與 NFC 原始碼，無 Swift 編譯錯誤。已完成 MobileIT 開發簽章與實體 iPhone 安裝、啟動。尚未完成完整視窗操作、電腦與 iPhone 的實機傳圖、專用 App NFC 更新與實際顯示確認。Ubuntu 缺少 tkinter；Mac 的 Xcode／XcodeGen 已可用。

## Mac mini 初次編譯

將專案複製到 Mac，進入專案根目錄後執行：

```bash
brew install xcodegen
cd ios
xcodegen generate
open EpaperBridge.xcodeproj
```

在 Xcode 選取 EpaperBridge target → Signing & Capabilities，選擇 MobileIT Team，確認本專案 Bundle Identifier，確認 NFC Tag Reading capability。以連接的實體 iPhone 執行（⌘R）。首次安裝依 iPhone 系統提示完成開發者模式與信任設定。

回到專案根目錄，以已設定的 Python 3 環境執行電腦端；Mac 的 Pillow、Bleak 與 PyObjC 已安裝於專案 .venv；十一項圖片／傳輸測試均通過，視窗已成功初始化，實機 BLE 與完整 GUI 操作仍待驗證。若是由 Ubuntu 傳圖，只需在 Mac 編譯安裝手機 App，傳送端仍留在 Ubuntu。

快速傳圖時不要先斷開 BLE；等電腦顯示手機完整收到後，再執行 NFC。若遇到區域網路下載失敗，先查看手機具體訊息、確認權限與電腦 IP；電腦防火牆需允許目前 Python 的入站連線。訪客 Wi-Fi 可能阻擋裝置互連，這時可手動改用純 BLE。

## 已建立的 Mac 工作目錄

- SSH：`user@mac-mini.local`
- 專案：`~/Documents/Xcode/Waveshare_e-Paper`
- Xcode 專案：`ios/EpaperBridge.xcodeproj`
- 編譯產物：`ios/build/Build/Products/Debug-iphoneos/EpaperBridge.app`
- 原始碼同步：在 Ubuntu 專案根目錄執行 `./scripts/sync-mac.sh`。同步為單向且不刪除遠端檔案，不複製 `.git`、`.venv`、憑證或其他工作區設定。
- 未簽章編譯紀錄：Mac 的 `/tmp/waveshare-ios-build.log`，結果 `BUILD SUCCEEDED`。

## 簽章狀態與重試

使用者已指定 MobileIT 開發者 Team，相關 Team 設定已寫入 `ios/project.yml`。Mac 上已配對的實體 iPhone 可作測試機。個人 Team 不支援本專案的 NFC capability，因此不使用個人 Team。

Apple Program License Agreement 已由使用者確認，Xcode 已成功取得本專案專用且含 NFC 的 provisioning profile。簽章已驗證：application identifier 格式為 `<TEAM_ID>.com.mit.EpaperBridge`，NFC formats 包含 `TAG`。

若要重新編譯，可在 Mac 的 Terminal 雙擊 `scripts/build-ios-mac.command`，或執行：

```bash
cd ios
xcodegen generate
xcodebuild -project EpaperBridge.xcodeproj -scheme EpaperBridge \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  -allowProvisioningUpdates build
```

已使用 `xcrun devicectl device install app` 安裝到解鎖的 iPhone 16e，並以 bundle ID `com.mit.EpaperBridge` 成功啟動。簽章紀錄在 Mac 的 `/tmp/waveshare-ios-signed-build.log`，安裝與啟動結果分別在 `/tmp/waveshare-ios-install.json`、`/tmp/waveshare-ios-launch.json`。

若 SSH 執行 codesign 回報 `errSecInternalComponent`，改從 Mac 可見的 Terminal 執行 `scripts/build-ios-mac.command`，讓已登入使用者的鑰匙圈正常處理簽章。若出現金鑰存取提示，使用者直接在 Mac 處理即可，不應將密碼輸入遠端對話。

## 先用 Mac mini 傳圖

使用者已選擇優先測試 Mac mini → iPhone。專案包含 `samples/800x480-test.png`，可檢查上下左右、完整邊框與抖色明暗。

在 Mac 以 Finder 雙擊 `scripts/start-mac.command`，或在 Terminal 執行：

```bash
cd ~/Documents/Xcode/Waveshare_e-Paper
./scripts/start-mac.command
```

已安裝 Homebrew `python-tk@3.14`，並驗證 Python 3.14.10／Tk 9.1 能建立本專案視窗；十一項測試再次通過。安裝 Tk 時 Homebrew 也更新了其 Python／sqlite 相依版本。此專案 .venv 使用穩定路徑 `/opt/homebrew/opt/python@3.14/bin/python3.14`。若系統詢問 Terminal／Python 藍牙權限，需允許；必要時到系統設定的「隱私權與安全性 → 藍牙」確認。iPhone 也須允許專用 App 的藍牙與區域網路權限。

Mac 的自動選擇位址為本機區域網路 IP，可在視窗的電腦 IP 欄指定另一個手機可達的位址（例如 `192.168.1.100`）。若其他主機的圖片服務由 Mac 連線逾時，先由 Mac 本機直接發送。這個測試不代表 Mac → iPhone 已驗證。

手機開啟接收後，可在 Mac 雙擊 `scripts/send-test-mac.command` 傳送測試圖。紀錄會存到 `/tmp/waveshare-test-transfer.log`；這會透過 BLE 交接，再以區域網路下載，最後等待手機確認完整接收。

## 已修正：Mac 搜尋後傳圖報 different loop

症狀：GUI 搜尋可找到 iPhone，但接著傳送時顯示 `got Future attached to a different loop`。原因是每個按鈕動作都建立新執行緒並呼叫 `asyncio.run()`，搜尋取得的 CoreBluetooth 物件／future 隨後被另一個迴圈使用。

修正為視窗生命週期共用一個背景執行緒與 asyncio 事件迴圈，搜尋與傳送均排入同一迴圈。`desktop/test_app.py` 直接測試 App 的兩個按鈕回呼，以綁定迴圈的 Future 重現錯誤；修正前失敗，修正後通過。Mac 十二項測試全部通過。

已用同一 GUI 搜尋後傳送流程實測，Mac 完成 BLE 交接，iPhone 經區域網路接收測試圖並通過長度與 CRC 檢查，使用者確認手機可見預覽。此結果確認電腦到手機這一段；NFC 按鈕可按且出現感應視窗，但更新電子紙目前仍報錯，另行診斷。

## NFC 實機驗證成功與關鍵修復

實測過程中曾遭遇 CoreNFC 報錯 `Tag connection lost`，經分析與實機對照已完全修復並驗收成功：

1. **RF 供電穩定階段**：
   - Waveshare 無源電子紙需足夠電能才能穩定執行 Flash 寫入與內部電路初始化。
   - 修正為在進入初始化前，連續發送 `CD 0D` 維持通訊至少 1 秒且不少於 12 次探測（實測約 70 次），每次間隔 6 ms，使天線維持主動 RF 能量場。
2. **緊湊指令間隔（6 ms）**：
   - 避免 CoreNFC 因過長的人為等待（如 100 ms）判定閒置或使板子掉電失聯。
   - 所有初始化指令（型號 14）、400 包（每包 120 位元組）點陣資料傳送均以 6 ms 間隔緊湊傳輸並嚴格檢驗 ACK。
3. **刷新確認與休眠**：
   - 傳送完畢後查詢刷新狀態（`CD 0A`），輪詢收到 `FF 00` 確認完成，最後送出關閉指令（`CD 04`）。
   - 實機更新電子紙已由使用者確認成功，更新後顯示清晰完整。
4. **診斷模組清理**：
   - 驗證成功後，已移除暫時的 `NFCTrace.swift` 及相關 trace 寫入呼叫，並刪除除錯指令腳本 `scripts/repro-nfc-mac.command`。
   - 核心供電穩定與短間隔邏輯正式保留於 `ios/EpaperBridge/NFCWriter.swift`。
