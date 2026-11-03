#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root/ios"
export PATH="/opt/homebrew/bin:$PATH"

# 載入本地私有開發設定檔（若存在）
if [ -f "$project_root/.env.local" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$project_root/.env.local"
    set +a
fi

echo "⚙️  正在產生 Xcode 專案結構..."
xcodegen generate

echo "🔨 正在編譯並簽章 EpaperBridge..."
echo "如出現 macOS 鑰匙圈提示，請點選「允許」讓 codesign 使用開發者金鑰。"

if xcodebuild -project EpaperBridge.xcodeproj -scheme EpaperBridge \
    -destination 'generic/platform=iOS' -derivedDataPath build \
    -allowProvisioningUpdates build > /tmp/waveshare-ios-signed-build.log 2>&1; then
    echo "✅ BUILD SUCCEEDED：編譯與簽章完成！"
else
    tail -35 /tmp/waveshare-ios-signed-build.log
    echo "❌ 編譯或簽章未完成，請檢視上方錯誤訊息。"
    exit 1
fi

app_path="$project_root/ios/build/Build/Products/Debug-iphoneos/EpaperBridge.app"

# 動態自動偵測目前已連接且信任的實體 iPhone (免寫死任何個人裝置識別碼)
connected_device=$(python3 -c "
import json, subprocess
try:
    out = subprocess.check_output(['xcrun', 'devicectl', 'list', 'devices', '--json-output', '-'], stderr=subprocess.DEVNULL)
    data = json.loads(out)
    for d in data.get('result', {}).get('devices', []):
        hw = d.get('hardwareProperties', {})
        if hw.get('reality') == 'physical' and hw.get('platform') == 'iOS':
            print(d.get('identifier'))
            break
except Exception:
    pass
" 2>/dev/null || true)

if [ -n "$connected_device" ]; then
    echo "📱 偵測到已連線的實體 iPhone ($connected_device)，正在自動安裝..."
    if xcrun devicectl device install app --device "$connected_device" "$app_path"; then
        echo "🚀 安裝成功！正在啟動 App..."
        xcrun devicectl device process launch --device "$connected_device" --terminate-existing com.mit.EpaperBridge || true
        echo "🎉 EpaperBridge 已成功在您的 iPhone 上更新並啟動！"
    else
        echo "⚠️  安裝提示：請確保 iPhone 螢幕處於解鎖狀態，並已信任此 Mac 電腦。"
    fi
else
    echo "ℹ️  目前未偵測到連線中的實體 iPhone。已編譯完成的 App 位於："
    echo "   $app_path"
fi
