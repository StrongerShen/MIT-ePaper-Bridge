#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p output
export PATH="$HOME/.local/bin:$PATH"
exec agy \
  --mode auto \
  --add-dir "$project_root" \
  --log-file "$project_root/output/agy-handoff.log" \
  --prompt-interactive "請先閱讀 $project_root/docs/AGY_HANDOFF.md，直接在這個 Mac 專案接手工作。使用者剛確認最新自製 App 的 NFC 更新已成功；請依交接檔保留成功流程，完成暫時診斷清理、測試、Xcode 簽章驗證與操作文件收尾，以繁體中文回報並在需要實體 NFC 感應時請使用者操作。"
