#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
echo '請先在 iPhone 開啟「電子紙橋接」並按「接收電腦圖片」。'
echo '首次使用時，請允許 Terminal／Python 使用藍牙，並允許 iPhone 存取區域網路。'
.venv/bin/python -u desktop/bridge.py send samples/800x480-test.png \
  2>&1 | tee /tmp/waveshare-test-transfer.log
