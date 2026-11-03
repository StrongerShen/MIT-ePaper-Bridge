# 電腦與 iPhone 傳輸協定 v1

## BLE

iPhone 發布 GATT service，電腦擔任 central。第一版前景操作，按「接收電腦圖片」才接受傳入資料；一張完整接收後停止廣播與接收，既有連線仍可讀取完成狀態。要傳下一張需再次按接收。這是本專案的自訂服務，既有 NFC E-Tag App 不會提供此服務。

| 用途 | UUID | 屬性 |
| --- | --- | --- |
| Service | `e3911000-7c21-4e12-9234-18a3347a6000` | Primary |
| Control | `e3911001-7c21-4e12-9234-18a3347a6000` | Write with response |
| Data | `e3911002-7c21-4e12-9234-18a3347a6000` | Write with response |
| Status | `e3911003-7c21-4e12-9234-18a3347a6000` | Read |

所有多位元組整數皆為 little endian。每次 write 均等待 ATT 回應；封包最多 20 bytes，適用最低 MTU 23，不依賴平台協商較大的 MTU。

1. Begin 寫到 Control：`01 | width:u16 | height:u16 | length:u32 | crc32:u32`，共 13 bytes，只接受 800、480、48000。
2. 讀取 Status，確認 state=1、received=0。
3. Data 寫到 Data：`02 | offset:u32 | payload:1…15 bytes`，offset 必須等於已收到的 byte 數，防止跳段、重複或超量資料。
4. Commit 寫到 Control：`03`。確認完整長度與 CRC32 後，原子寫入最後圖片並更新預覽；不完整則保留先前圖片。
5. 讀取 Status：`state:u8 | received:u32 | crc32:u32`，共 9 bytes。state=0 尚未開始，1 接收中，2 已完整接收。只有 state=2、48000 與 CRC 全部吻合，電腦才回報接收完成。

同一時間只接受一個 central 的傳輸。原 central 可用 Begin 從頭重傳；超過 60 秒沒有寫入後另一台可重新開始，或由使用者取消接收後重開。不做斷點續傳。CRC 用於完整性檢查，不是身分驗證；目前接收窗口內未加入應用層配對或授權機制。

## BLE 交接、區域網路傳圖（預設）

沿用相同 GATT service、Data 分段與 Commit，新增 Begin opcode `04`：`04 | descriptorLength:u32 | descriptorCRC32:u32`，共 9 bytes。描述資料最多 1024 bytes，使用 UTF-8 JSON：`url`、`width`、`height`、`length` 與 `crc32`。尺寸固定為 800 × 480，圖片長度 48000。

1. 電腦只在指定／自動偵測的區域網路 IPv4 上開啟臨時 HTTP 服務，以隨機 token 路徑提供記憶體中的單張圖片；不提供檔案目錄或其他檔案。
2. Begin `04` 後狀態為 1，分段傳送 JSON，Commit 驗證 JSON 長度與 CRC 並啟動下載。
3. 狀態 3 表示區域網路下載中；iPhone 只接受 RFC1918 或 169.254/16 數字 IPv4，不允許重新導向，先核對 HTTP 狀態與 Content-Length，再限制接收上限並檢查圖片 CRC。
4. 狀態 4 表示區域網路圖片完整接收，此時 Status 的 received 與 CRC 對應圖片本身；狀態 5 表示下載失敗，具體原因顯示在手機。
5. 電腦每 250 ms 經 BLE 查詢下載結果，最多等待 60 秒；確認完成、失敗、取消或連線異常後關閉 HTTP 服務。iPhone 的請求等待 15 秒、資源上限 45 秒。

下載與結果確認期間需維持 BLE 連線，手機保持前景。iPhone 進入背景或取消接收時，取消下載且保留先前完整圖片；新接收不會被舊下載結果覆蓋。完成後可斷開電腦，再單獨操作 NFC。

第一版使用本地 HTTP 與暫時隨機網址，無網際網路中繼、TLS 或應用層身分驗證；CRC 是資料完整性檢查。來源 IP 選錯、防火牆阻擋、訪客 Wi-Fi 裝置隔離、權限拒絕或未在共同網路時都可能失敗。使用者可指定電腦 `--host` 或改用 `--transport ble`，不會默默改用其他網路或自動更改防火牆。

## 圖片點陣

- 800 × 480，48000 bytes，逐列由上至下，每列由左至右，高位元為左側像素。
- 1 表示白，0 表示黑，沒有 BMP 標頭或行尾填補。
- 預覽顯示相同點陣；灰階效果先由電腦抖色為黑白點。
- 解析度、方向與極性仍需用實機畫面確認。

## NFC 初版支援

依 [Waveshare 官方 ST25R3911B 範例](https://files.waveshare.com/wiki/ST25R3911B%20NFC%20Board/ST25R3911B-NFC-Demo.zip) 中 `epd-demo/User/Browser/Browser.c` 的 `Start_Dawring_V1` 與 `Read_RAM_V1` 實作：一般 7.5 吋型號代碼 14，120 bytes 圖片資料一包，共 400 包；以 `0xCD` 系列指令初始化、傳圖、啟動刷新與查詢完成。只對 MIFARE 類型使用 CoreNFC raw command，未實作新版 APDU 協定。

每個資料包都檢查回應，異常即終止；中斷後需重新傳送整張，避免盲目重送造成位址錯位。完成判斷為裝置的刷新完成回應，並非只等候固定時間。整體流程設有 45 秒期限，刷新查詢最多 20 秒；iOS NFC 系統工作階段也可能更早因標籤離開或其他原因結束。

官方範例提供舊／新版多條路徑，不能由 iPhone 可讀到 UID 或既有 App 可傳圖，推定本機一定使用初版路徑。此實作尚未經本機硬體驗證。

## API 依據

- [Apple：Peripheral role tasks](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonPeripheralRoleTasks/PerformingCommonPeripheralRoleTasks.html)
- [Apple：Core NFC raw tag communication](https://developer.apple.com/videos/play/wwdc2020/10209/)
- [Bleak：GATT client operations](https://bleak.readthedocs.io/en/latest/api/client.html)

- [Apple：區域網路權限](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Apple：NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
