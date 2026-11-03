# Mac agy 交接：保留已成功的流程並完成收尾

使用者明確要求由 Mac mini 的 agy CLI 接手。最新 NFC 測試已成功，使用者已確認電子紙更新；目前任務是清理與驗證。

## 先做

1. 在專案根目錄工作。後續以 Mac 這份原始碼為準；Ubuntu 的 `scripts/sync-mac.sh` 是舊的單向推送工具，接手後先保留 Mac 的修改，避免被舊來源覆寫。
2. 讀取下方「實測證據」與 `docs/diagnostics/nfc-success.log`，確認最後成功版本的 NFC 行為。
3. 清理 `ios/EpaperBridge/NFCTrace.swift`、NFCWriter 的實驗標記與暫時 trace 呼叫。保留成功的供電穩定階段、短間隔、指令順序、ACK 檢查與刷新完成判斷。
4. 將 App 內「尚待本裝置驗證」文字改為適合使用者的操作提示；把 README、開發文件中的過期診斷狀態整理成目前已成功的流程。以交接檔與成功 trace 為最新事實來源。
5. 在 Mac 跑 `.venv/bin/python -m unittest discover -s desktop -v`，並用 Xcode 編譯、簽章、驗證 NFC TAG entitlement。前次 Mac 共 12 項測試通過。必要時更新安裝到同一支 iPhone，保留 App 文件中的最後圖片。
6. 回報具體修改、測試結果、App 是否已更新安裝，以及仍需使用者確認的實機項目。以繁體中文與使用者互動；需要貼近電子紙時請使用者操作。

完成條件：Mac 原始碼可編譯簽章、桌面測試通過、臨時執行期診斷已清除、成功 NFC 行為保持不變、操作文件與目前狀態一致。一次成功 trace 不是全部硬體版本相容性的證據。

## 實測證據

完整目標流程：Mac 選圖 → BLE 交接 → 同區域網路下載 → iPhone 預覽 → NFC 更新現有電子紙。現有電子紙無需增加 BLE 硬體。

- 桌面 GUI 原本的 `got Future attached to a different loop` 已修正：`desktop/app.py` 在視窗生命週期共用一個背景執行緒與 asyncio 迴圈，搜尋與傳送都排入同一迴圈。`desktop/test_app.py` 在實際兩個按鈕回呼的 seam 重現舊錯誤，已確認修正前失敗、修正後通過。
- Mac → BLE → 區域網路 → iPhone 已實機成功。圖片 800 × 480、1-bit、48000 bytes；iPhone 驗證長度與 CRC，使用者看得到測試圖。
- 官方 NFC E-Tag 對照：已看到一般 `7.5inch e-Paper` 標題與 54% 進度；使用者確認官方 App 此次真的更新了電子紙。型號不是 HD。官方 App 的畫面沒有提供原始 NFC 指令。
- 自製 App 初始失敗：`CD 0D` 正常 ACK；100 ms 後的 `CD 00 0E` 失聯。
- 移除第一段 100 ms 後：`CD 00 0E` ACK，但後面的 `CD 01` 失聯。
- 全部人工閒置縮短為 6 ms 後：仍在 `CD 01` 失聯，故只調短間隔並不足以修復。
- **最後成功版本**：初始化前連續以 `CD 0D` 正常 ACK 維持通訊至少 1 秒且至少 12 次，期間間隔 6 ms。成功 trace 記錄 70 次穩定探測；接著一般 7.5 吋型號代碼 14 初始化、400 包各 120 bytes 圖片、刷新查詢收到 `FF 00`、關閉指令收到 `00 00`；trace 沒有操作錯誤。使用者確認更新成功。
- Trace 最後的 `NFCError code=200 Session invalidated by user` 發生於成功 ACK 之後，是程式主動結束 session 的 delegate 訊息，不能單看它就把整次判成失敗。

請把成功解讀為這支手機與這塊板子的驗證結果；供電穩定是由單變因測試支持的改善方向，沒有實際量測 RF 電壓。

## Mac 工具與環境

- Xcode 27.2，XcodeGen：`/opt/homebrew/bin/xcodegen`。
- 使用者指定 MobileIT Team，最新 Program License Agreement 已由使用者確認。個人免費 Team 不支援本專案 NFC capability。
- Bundle ID：`com.mit.EpaperBridge`；NFC entitlement：`com.apple.developer.nfc.readersession.formats = [TAG]`。簽章驗證曾成功。
- 實體 iPhone 已配對，可用 devicectl 安裝與啟動；手機鎖定時啟動會被拒絕。
- Python `.venv` 已安裝 Pillow、Bleak、PyObjC。Tk 9.1 可建立傳圖視窗。Homebrew Python 穩定路徑為 `/opt/homebrew/opt/python@3.14/bin/python3.14`。
- `scripts/build-ios-mac.command`：在 Mac Terminal 生成專案並簽章。SSH 直接 codesign 曾報 `errSecInternalComponent`，改由可見 Terminal 執行便成功；帳號密碼由使用者在 Mac 本機處理。
- `scripts/start-mac.command`：桌面視窗；`scripts/send-test-mac.command`：傳送 `samples/800x480-test.png`；`scripts/repro-nfc-mac.command`：實機 HITL 擷取，診斷完成後可移除或改為正式支援工具。
- Mac LAN 可在電腦端自動選取本機區域網路 IP；跨不同子網段時可在視窗中手動指定，以確保 iPhone 可連通。使用者已選擇先從 Mac 傳圖。
- `xcrun devicectl device capture screenshot` 可擷取手機；這支 iPhone 不支援 devicectl 遠端 screen-record。`--timeout` 最少 5 秒。之前錯設為 4 秒的連續截圖沒有有效影格，勿用該批資料推算官方 App 耗時。
- Mac Terminal 已獲螢幕錄製權限。桌面截圖透過 Terminal 可行；純 SSH 的授權不一定相同。Tk 的輔助使用介面只暴露視窗標題，讀不到完整狀態文字。

## 參考與資料

照片、型號線索、UID 與官方連結見 `docs/hardware-identification.md`；BLE／LAN 格式見 `docs/protocol.md`。

官方 C 範例已下載在 Ubuntu `/tmp/waveshare-nfc-demo.zip`（Mac 若需可依下列網址重新下載）：
https://files.waveshare.com/wiki/ST25R3911B%20NFC%20Board/ST25R3911B-NFC-Demo.zip

其中 `epd-demo/User/Browser/Browser.c` 的 `Start_Dawring_V1`、`Read_RAM_V1` 是舊版協定依據；`epd-demo/Src/demo.c` 的 `RFLA_APDU_Send` 也有啟動 RF 後等待 1000 ms 的動作。外接讀寫器保持 RF 場的方式不能直接等同 iPhone 的 idle 行為。

公開參考（僅查過協定流程，沒有把其 Kotlin 程式複製進專案）：
https://github.com/goldhoorn/e-paper-nfc/blob/main/app/src/main/java/com/joshuatz/nfceinkwriter/WaveshareEpaperWriter.kt
