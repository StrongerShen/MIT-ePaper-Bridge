# 硬體辨識紀錄

更新日期：2026-11-03。

## 使用者提供的照片

原始檔均已複製到專案內，保留檔名，不修改原圖。另收到兩張 iPhone App 截圖，亦保存為辨識線索。

| 照片 | 可見線索 |
| --- | --- |
| [先前的驅動板照片](images/driver-board.jpg) | 既有辨識依據 |
| [PXL_20261103_032302478.jpg](images/PXL_20261103_032302478.jpg) | 排線印字 `WFT0583CZ61`；micro-USB 接口；SWDIO、GND、SWCLK、3V3、5V、RST 標示 |
| [PXL_20261103_032313296.jpg](images/PXL_20261103_032313296.jpg) | 電容陣列、電路與驅動板局部；晶片字樣不足以可靠辨識 |
| [PXL_20261103_032308484.jpg](images/PXL_20261103_032308484.jpg) | `Waveshare 7.5inch NFC e-Paper Driver Board` 印字與天線走線 |
| [IMG_1134.PNG](images/IMG_1134.PNG) | `Select e-Paper type` 選單，有 `7.5inch e-Paper` 與 `7.5inch HD e-Paper` 兩個選項 |
| [IMG_1133.PNG](images/IMG_1133.PNG) | `Get UID` 畫面，顯示 `UID : 5753445A31306D` |

接口外觀不能證明 micro-USB 支援 USB 資料通訊；本次未驗證其用途。

## 解析度判斷

- **直接觀察**：板上標示 7.5inch NFC，排線標示 `WFT0583CZ61`。
- **文件依據**：[Zephyr 官方原始碼文件](https://github.com/zephyrproject-rtos/zephyr/blob/main/boards/shields/waveshare_epaper/doc/index.rst) 將此排線標示對應至 Good Display GDEW075T7。排線代碼是線索，不能單獨保證面板與整機版本。
- **規格交叉核對**：[Waveshare 官方一般 7.5 吋 NFC 電子紙 Wiki](https://www.waveshare.com/wiki/7.5inch_NFC-Powered_e-Paper) 列出 800 × 480、黑白；[中文版](https://www.waveshare.net/wiki/7.5inch_NFC-Powered_e-Paper) 亦列出相同規格。
- **目前推定**：以一般 7.5 吋 NFC 黑白款的 **800 × 480** 作為圖片製作目標，可信度較高，但尚未實測確認。板子 revision、整機 V1/V2 與精確面板型號仍待確認。
- 不因排線含有 `0583` 就判斷是 5.83 吋；也不僅依螢幕尺寸就選 HD。不得將面板型號與 NFC 驅動板版本混為一談。

## 手機與 NFC 狀態

- 使用者確認 iPhone 可以讀到 UID；截圖顯示值為 `5753445A31306D`，依 App 畫面原樣記錄，不自行反轉位元組或推斷晶片型號。使用者已提供 App Store 連結，確認使用 [NFC E-Tag（App ID 1518982217）](https://apps.apple.com/app/id1518982217)，與官方手冊指定 App 相符。iPhone 型號、iOS 與已安裝 App 版本尚未提供。
- 2026-11-03 使用者進一步回報「iOS App 可以傳送、有作用」，已確認 NFC E-Tag 傳送會讓裝置產生反應；實測所選型號與完整顯示效果尚未提供，不據此直接確認解析度或原生灰階。
- [Waveshare 官方手冊](https://files.waveshare.com/upload/d/d7/NFC-Powered%20e-Paper.pdf) 提供 iOS 的 **NFC E-Tag** 操作說明，並列有一般 `7.5inch e-Paper` 與 HD 選項。
- [NFC E-Tag App Store 頁面](https://apps.apple.com/us/app/nfc-e-tag/id1518982217) 說明用途為更新 Waveshare NFC 電子紙。使用者已確認此 App 對手邊裝置傳送有作用；此結果僅適用於目前組合，不能據此推定所有驅動板版本的相容性。
- 下一步補記成功傳送時使用的型號選項，並用符合目標解析度的圖片確認完整畫面、方向與邊界；傳送期間保持手機位置穩定。

## 圖片輸出要求

- 使用者觀察裝置似乎也能呈現灰階，先保留此觀察，原生多階灰階能力尚未確認。[官方 NFC 套件規格](https://www.waveshare.com/product/displays/e-paper/7.5inch-nfc-e-paper-eval-kit.htm) 標示 `Grey scale: 2`，即黑、白兩階，並非 2-bit 四階。[官方手冊](https://files.waveshare.com/upload/d/d7/NFC-Powered%20e-Paper.pdf) 另列有 `Gray Effect` 影像處理選項；有灰階效果不等於 NFC 韌體支援原生多階灰階。不得將其他 SPI 面板的灰階能力直接套用到本裝置。
- 後續製圖保留灰階中間檔，再產生適合目前 NFC 黑白規格的抖色輸出；若實測證實支援原生多階灰階，再依實際階數與工具格式輸出。
- 使用者要求圖片符合裝置解析度，目前暫定橫向寬 800、高 480 像素，比例 5:3。
- 黑白 1-bit；照片可採抖色呈現明暗，文字與線稿可視內容採閾值二值化。
- 預設保留完整內容、等比例縮放並補白，避免拉伸。滿版裁切依使用者指定。
- 預覽／App 匯入候選格式為 PNG；讀寫板的 BMP 或原始點陣格式需求另行確認，不能把 PNG 當作 NFC 協定資料直接傳送。
- 尚未提供要顯示的原始圖片，因此本次未產生顯示用圖檔；三張硬體照片與兩張 App 截圖只作辨識線索。
- 最終須用實際刷新結果確認畫面尺寸、方向與邊界。
