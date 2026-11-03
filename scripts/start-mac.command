#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
if [[ ! -x .venv/bin/python ]]; then
  echo '請先建立專案 Python 環境，參閱 docs/development.md。'
  exit 1
fi
exec .venv/bin/python desktop/app.py
