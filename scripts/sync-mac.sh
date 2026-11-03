#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mac_destination="${MAC_DESTINATION:-user@mac-mini.local:~/Documents/Xcode/Waveshare_e-Paper/}"

# Source files only. Keep the Mac's generated Xcode project, signing choices,
# build products and local environment intact. Never delete destination files.
rsync -az --itemize-changes \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='*.xcodeproj/' \
  --exclude='build/' \
  --exclude='*.xcuserstate' \
  -- \
  "$project_root/.gitignore" \
  "$project_root/README.md" \
  "$project_root/desktop" \
  "$project_root/docs" \
  "$project_root/ios" \
  "$project_root/scripts" \
  "$project_root/samples" \
  "$mac_destination"

echo '已同步原始碼到目標 Mac mini'
